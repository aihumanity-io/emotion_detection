#include "emotion_sdk.h"

#include <algorithm>
#include <array>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "emotion_key_material.h"
#include "emotion_license_state.h"
#include "emotion_logging.h"
#include "emotion_model_manifest.h"
#include "emotion_model_registry.h"
#include "emotion_postprocessing.h"
#include "emotion_preprocessing.h"
#include "emotion_runtime_session.h"

namespace {

using emotion::native_sdk::FakeRuntimeSession;
using emotion::native_sdk::KeyMaterialStore;
using emotion::native_sdk::KeyShard;
using emotion::native_sdk::LicenseState;
using emotion::native_sdk::LicenseStore;
using emotion::native_sdk::ModelManifest;
using emotion::native_sdk::ModelRegistry;
using emotion::native_sdk::NativeLogger;
using emotion::native_sdk::PostprocessResult;
using emotion::native_sdk::PreprocessOptions;
using emotion::native_sdk::PreprocessResult;
using emotion::native_sdk::RegisteredModel;
using emotion::native_sdk::RuntimeLoadResult;
using emotion::native_sdk::RuntimeSession;
using emotion::native_sdk::parse_model_manifest_file;
using emotion::native_sdk::predict_and_postprocess;

struct SdkState {
  explicit SdkState(const emotion_config_t& sdk_config)
      : logger(&sdk_config), secure_store(sdk_config.secure_store) {}

  NativeLogger logger;
  const emotion_secure_store_adapter_t* secure_store = nullptr;
  ModelRegistry registry;
  KeyMaterialStore key_store;
  LicenseStore license_store;
  std::map<std::string, ModelManifest> manifests;
  std::map<std::string, std::unique_ptr<RuntimeSession>> sessions;
};

std::unique_ptr<SdkState> g_state;

bool empty(const char* value) {
  return value == nullptr || value[0] == '\0';
}

emotion_status_t require_initialized() {
  return g_state == nullptr ? EMOTION_STATUS_NOT_INITIALIZED : EMOTION_STATUS_OK;
}

std::vector<float> fake_logits_for(const ModelManifest& manifest) {
  const size_t count = manifest.labels.empty() ? 2u : manifest.labels.size();
  std::vector<float> logits(count, 0.0f);
  for (size_t i = 0; i < count; ++i) {
    logits[i] = static_cast<float>(i);
  }
  return logits;
}

std::vector<std::string> labels_for(const ModelManifest& manifest) {
  if (!manifest.labels.empty()) {
    return manifest.labels;
  }
  return {"neutral", "happy"};
}

PreprocessOptions preprocess_options_for(const ModelManifest& manifest) {
  PreprocessOptions options;
  if (manifest.input_shape.size() == 4u) {
    options.target_height = static_cast<uint32_t>(manifest.input_shape[1]);
    options.target_width = static_cast<uint32_t>(manifest.input_shape[2]);
  }
  if (options.target_width == 0u || options.target_height == 0u) {
    options.target_width = 1u;
    options.target_height = 1u;
  }
  return options;
}

void write_error(emotion_result_t* result,
                 emotion_status_t status,
                 const std::string& message) {
  if (result == nullptr) {
    return;
  }
  result->abi_version = EMOTION_SDK_ABI_VERSION;
  result->status = status;
  result->scores_count = 0u;
  result->error_message[0] = '\0';
  std::strncpy(result->error_message, message.c_str(),
               EMOTION_SDK_ERROR_MESSAGE_SIZE - 1u);
  result->error_message[EMOTION_SDK_ERROR_MESSAGE_SIZE - 1u] = '\0';
}

LicenseState parse_license_json(const char* model_id, const char* license_json) {
  LicenseState license;
  license.model_id = model_id == nullptr ? "" : model_id;
  if (license_json == nullptr || license_json[0] == '\0') {
    return license;
  }
  try {
    const nlohmann::json json = nlohmann::json::parse(license_json);
    if (json.contains("model_id") && json["model_id"].is_string()) {
      license.model_id = json["model_id"].get<std::string>();
    }
    if (json.contains("not_before_ms") && json["not_before_ms"].is_number_integer()) {
      license.not_before_ms = json["not_before_ms"].get<int64_t>();
    }
    if (json.contains("expires_at_ms") && json["expires_at_ms"].is_number_integer()) {
      license.expires_at_ms = json["expires_at_ms"].get<int64_t>();
    }
  } catch (const nlohmann::json::exception&) {
    license.model_id = "";
  }
  return license;
}

}  // namespace

extern "C" {

emotion_status_t emotion_init(const emotion_config_t* config) {
  if (config == nullptr || config->abi_version != EMOTION_SDK_ABI_VERSION) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  g_state.reset(new SdkState(*config));
  return EMOTION_STATUS_OK;
}

emotion_status_t emotion_register_model(const emotion_model_config_t* config) {
  if (require_initialized() != EMOTION_STATUS_OK) {
    return EMOTION_STATUS_NOT_INITIALIZED;
  }
  if (config == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  const emotion_status_t status = g_state->registry.register_model(*config);
  if (status != EMOTION_STATUS_OK) {
    return status;
  }
  const emotion::native_sdk::ManifestParseResult manifest_result =
      parse_model_manifest_file(config->manifest_path);
  if (!manifest_result.ok) {
    g_state->registry.remove(config->model_id);
    return EMOTION_STATUS_MANIFEST_INVALID;
  }
  g_state->manifests[config->model_id] = manifest_result.manifest;
  return EMOTION_STATUS_OK;
}

emotion_status_t emotion_set_user_code(const char* user_name,
                                       const char* model_id,
                                       const uint8_t* code32) {
  if (require_initialized() != EMOTION_STATUS_OK) {
    return EMOTION_STATUS_NOT_INITIALIZED;
  }
  if (empty(user_name) || empty(model_id) || code32 == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  if (g_state->registry.find(model_id) == nullptr) {
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }
  std::array<uint8_t, EMOTION_SDK_USER_CODE_SIZE> user_code = {};
  std::copy(code32, code32 + EMOTION_SDK_USER_CODE_SIZE, user_code.begin());
  g_state->key_store.set_user_code(user_name, model_id, user_code);
  return EMOTION_STATUS_OK;
}

emotion_status_t emotion_set_key_shard(const char* model_id,
                                       const uint8_t* shard,
                                       size_t shard_len,
                                       int64_t expires_at_ms) {
  if (require_initialized() != EMOTION_STATUS_OK) {
    return EMOTION_STATUS_NOT_INITIALIZED;
  }
  if (empty(model_id) || shard == nullptr || shard_len == 0u) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  if (g_state->registry.find(model_id) == nullptr) {
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }
  KeyShard key_shard;
  key_shard.bytes.assign(shard, shard + shard_len);
  key_shard.expires_at_ms = expires_at_ms;
  g_state->key_store.set_key_shard(model_id, key_shard);
  return EMOTION_STATUS_OK;
}

emotion_status_t emotion_set_license(const char* model_id,
                                     const char* license_json) {
  if (require_initialized() != EMOTION_STATUS_OK) {
    return EMOTION_STATUS_NOT_INITIALIZED;
  }
  if (empty(model_id) || license_json == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  if (g_state->registry.find(model_id) == nullptr) {
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }
  const LicenseState license = parse_license_json(model_id, license_json);
  if (license.model_id.empty() || license.model_id != model_id) {
    return EMOTION_STATUS_LICENSE_INVALID;
  }
  g_state->license_store.set_license(license);
  return EMOTION_STATUS_OK;
}

emotion_status_t emotion_warmup(const char* model_id) {
  if (require_initialized() != EMOTION_STATUS_OK) {
    return EMOTION_STATUS_NOT_INITIALIZED;
  }
  if (empty(model_id)) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  const RegisteredModel* model = g_state->registry.find(model_id);
  if (model == nullptr) {
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }
  const ModelManifest& manifest = g_state->manifests[model_id];
  std::unique_ptr<RuntimeSession> session(
      new FakeRuntimeSession(fake_logits_for(manifest)));
  const RuntimeLoadResult load_result = session->load({1u});
  if (!load_result.ok) {
    return EMOTION_STATUS_RUNTIME_FAILED;
  }
  const RuntimeLoadResult warmup_result = session->warmup();
  if (!warmup_result.ok) {
    return EMOTION_STATUS_RUNTIME_FAILED;
  }
  g_state->sessions[model_id] = std::move(session);
  return g_state->registry.mark_warmed(model_id);
}

emotion_status_t emotion_predict_image(const char* model_id,
                                       const emotion_image_t* image,
                                       const emotion_face_box_t* face_box,
                                       emotion_result_t* result) {
  if (require_initialized() != EMOTION_STATUS_OK) {
    write_error(result, EMOTION_STATUS_NOT_INITIALIZED, "not initialized");
    return EMOTION_STATUS_NOT_INITIALIZED;
  }
  if (empty(model_id) || image == nullptr || result == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  if (g_state->registry.find(model_id) == nullptr) {
    write_error(result, EMOTION_STATUS_MODEL_NOT_FOUND, "model not found");
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }
  std::map<std::string, std::unique_ptr<RuntimeSession>>::iterator session_it =
      g_state->sessions.find(model_id);
  if (session_it == g_state->sessions.end()) {
    write_error(result, EMOTION_STATUS_RUNTIME_FAILED, "runtime not warmed");
    return EMOTION_STATUS_RUNTIME_FAILED;
  }

  const ModelManifest& manifest = g_state->manifests[model_id];
  const PreprocessResult preprocessed =
      preprocess_image(*image, face_box, preprocess_options_for(manifest));
  if (!preprocessed.ok) {
    write_error(result, EMOTION_STATUS_INVALID_ARGUMENT, preprocessed.error);
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }

  const PostprocessResult postprocessed = predict_and_postprocess(
      session_it->second.get(), preprocessed.tensor, labels_for(manifest));
  const emotion_status_t copy_status =
      copy_postprocess_to_c_result(postprocessed, result);
  return copy_status;
}

emotion_status_t emotion_unload(const char* model_id) {
  if (require_initialized() != EMOTION_STATUS_OK) {
    return EMOTION_STATUS_NOT_INITIALIZED;
  }
  if (empty(model_id)) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  std::map<std::string, std::unique_ptr<RuntimeSession>>::iterator session_it =
      g_state->sessions.find(model_id);
  if (session_it != g_state->sessions.end()) {
    session_it->second->unload();
    g_state->sessions.erase(session_it);
  }
  return g_state->registry.unload(model_id);
}

emotion_status_t emotion_shutdown(void) {
  g_state.reset();
  return EMOTION_STATUS_OK;
}

}  // extern "C"
