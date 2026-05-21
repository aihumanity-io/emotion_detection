#include "emotion_model_registry.h"

#include <cstdlib>
#include <iostream>
#include <string>

namespace {

using emotion::native_sdk::ModelLifecycleState;
using emotion::native_sdk::ModelRegistry;
using emotion::native_sdk::RegisteredModel;

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

emotion_model_config_t model_config(const char* model_id) {
  emotion_model_config_t config = {};
  config.abi_version = EMOTION_SDK_ABI_VERSION;
  config.model_id = model_id;
  config.manifest_path = "/models/model.manifest.json";
  config.encrypted_model_path = "/models/model.enc";
  config.runtime_preference = EMOTION_RUNTIME_ONNX;
  config.accelerator_preference = EMOTION_ACCELERATOR_CPU;
  return config;
}

void register_and_lookup_model() {
  ModelRegistry registry;

  expect_true(registry.register_model(model_config("aih_fer2025")) ==
                  EMOTION_STATUS_OK,
              "register should succeed");
  const RegisteredModel* model = registry.find("aih_fer2025");

  expect_true(model != nullptr, "registered model should be found");
  expect_true(model->model_id == "aih_fer2025", "model id should be stored");
  expect_true(model->runtime_preference == EMOTION_RUNTIME_ONNX,
              "runtime preference should be stored");
  expect_true(model->state == ModelLifecycleState::kRegistered,
              "initial state should be registered");
}

void duplicate_model_is_rejected() {
  ModelRegistry registry;
  registry.register_model(model_config("aih_fer2025"));

  expect_true(registry.register_model(model_config("aih_fer2025")) ==
                  EMOTION_STATUS_INVALID_ARGUMENT,
              "duplicate model should be rejected");
  expect_true(registry.size() == 1u, "duplicate should not grow registry");
}

void invalid_config_is_rejected() {
  ModelRegistry registry;
  emotion_model_config_t config = model_config("aih_fer2025");
  config.manifest_path = nullptr;

  expect_true(registry.register_model(config) == EMOTION_STATUS_INVALID_ARGUMENT,
              "missing manifest path should fail");
  expect_true(registry.size() == 0u, "invalid config should not be stored");
}

void warm_and_unload_lifecycle() {
  ModelRegistry registry;
  registry.register_model(model_config("aih_fer2025"));

  expect_true(registry.mark_warmed("aih_fer2025") == EMOTION_STATUS_OK,
              "warm should succeed");
  expect_true(registry.find("aih_fer2025")->state == ModelLifecycleState::kWarmed,
              "state should be warmed");
  expect_true(registry.unload("aih_fer2025") == EMOTION_STATUS_OK,
              "unload should succeed");
  expect_true(registry.find("aih_fer2025")->state ==
                  ModelLifecycleState::kUnloaded,
              "state should be unloaded");
  expect_true(registry.mark_warmed("aih_fer2025") ==
                  EMOTION_STATUS_MODEL_NOT_FOUND,
              "unloaded model should not warm again");
}

void missing_model_operations_fail_closed() {
  ModelRegistry registry;

  expect_true(registry.find("missing") == nullptr, "missing lookup returns null");
  expect_true(registry.mark_warmed("missing") == EMOTION_STATUS_MODEL_NOT_FOUND,
              "missing warm should fail");
  expect_true(registry.unload("missing") == EMOTION_STATUS_MODEL_NOT_FOUND,
              "missing unload should fail");
}

void clear_removes_all_models() {
  ModelRegistry registry;
  registry.register_model(model_config("a"));
  registry.register_model(model_config("b"));
  registry.clear();

  expect_true(registry.size() == 0u, "clear should remove models");
  expect_true(registry.find("a") == nullptr, "cleared model should be missing");
}

void remove_deletes_model_entry() {
  ModelRegistry registry;
  registry.register_model(model_config("aih_fer2025"));

  expect_true(registry.remove("aih_fer2025") == EMOTION_STATUS_OK,
              "remove should succeed");
  expect_true(registry.find("aih_fer2025") == nullptr,
              "removed model should be missing");
  expect_true(registry.remove("aih_fer2025") == EMOTION_STATUS_MODEL_NOT_FOUND,
              "missing remove should fail");
}

}  // namespace

int main() {
  register_and_lookup_model();
  duplicate_model_is_rejected();
  invalid_config_is_rejected();
  warm_and_unload_lifecycle();
  missing_model_operations_fail_closed();
  clear_removes_all_models();
  remove_deletes_model_entry();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
