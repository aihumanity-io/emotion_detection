#include "emotion_model_registry.h"

namespace emotion {
namespace native_sdk {
namespace {

bool empty(const char* value) {
  return value == nullptr || value[0] == '\0';
}

}  // namespace

emotion_status_t ModelRegistry::register_model(
    const emotion_model_config_t& config) {
  if (config.abi_version != EMOTION_SDK_ABI_VERSION ||
      empty(config.model_id) || empty(config.manifest_path) ||
      empty(config.encrypted_model_path)) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  if (models_.find(config.model_id) != models_.end()) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }

  RegisteredModel model;
  model.model_id = config.model_id;
  model.manifest_path = config.manifest_path;
  model.encrypted_model_path = config.encrypted_model_path;
  model.runtime_preference = config.runtime_preference;
  model.accelerator_preference = config.accelerator_preference;
  models_[model.model_id] = model;
  return EMOTION_STATUS_OK;
}

emotion_status_t ModelRegistry::mark_warmed(const std::string& model_id) {
  std::map<std::string, RegisteredModel>::iterator it = models_.find(model_id);
  if (it == models_.end() || it->second.state == ModelLifecycleState::kUnloaded) {
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }
  it->second.state = ModelLifecycleState::kWarmed;
  return EMOTION_STATUS_OK;
}

emotion_status_t ModelRegistry::unload(const std::string& model_id) {
  std::map<std::string, RegisteredModel>::iterator it = models_.find(model_id);
  if (it == models_.end()) {
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }
  it->second.state = ModelLifecycleState::kUnloaded;
  return EMOTION_STATUS_OK;
}

emotion_status_t ModelRegistry::remove(const std::string& model_id) {
  std::map<std::string, RegisteredModel>::iterator it = models_.find(model_id);
  if (it == models_.end()) {
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }
  models_.erase(it);
  return EMOTION_STATUS_OK;
}

void ModelRegistry::clear() {
  models_.clear();
}

const RegisteredModel* ModelRegistry::find(const std::string& model_id) const {
  std::map<std::string, RegisteredModel>::const_iterator it =
      models_.find(model_id);
  if (it == models_.end()) {
    return nullptr;
  }
  return &it->second;
}

size_t ModelRegistry::size() const {
  return models_.size();
}

}  // namespace native_sdk
}  // namespace emotion
