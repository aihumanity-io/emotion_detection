#include "emotion_model_package.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

using emotion::native_sdk::ModelManifest;
using emotion::native_sdk::ModelPackageVerificationResult;
using emotion::native_sdk::NativeLogger;
using emotion::native_sdk::verify_model_package;

struct LogEvent {
  emotion_log_level_t level;
  std::string stage;
  std::string model_id;
  std::string message;
};

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

void collect_log(emotion_log_level_t level,
                 const char* stage,
                 const char* model_id,
                 const char* message,
                 void* user_data) {
  std::vector<LogEvent>* events = static_cast<std::vector<LogEvent>*>(user_data);
  events->push_back({level, stage, model_id, message});
}

std::string fixture_path() {
  return std::string(EMOTION_TEST_PACKAGE_DIR) + "/fixture_model.enc";
}

ModelManifest valid_manifest() {
  ModelManifest manifest;
  manifest.model_id = "aih_fer2025";
  manifest.expiry_epoch_ms = 0;
  manifest.encrypted_sha256 =
      "6bca76ae3c19d6397aee52469c0a12b73d43b86b65a3bd3278c45254cc0fd545";
  return manifest;
}

void valid_package_verifies() {
  std::vector<LogEvent> events;
  const NativeLogger logger(collect_log, &events, true);

  const ModelPackageVerificationResult result =
      verify_model_package(valid_manifest(), fixture_path(), 1000, &logger);

  expect_true(result.ok, "valid package should verify");
  expect_true(events.empty(), "valid package should not emit errors");
}

void encrypted_hash_mismatch_fails_closed() {
  std::vector<LogEvent> events;
  const NativeLogger logger(collect_log, &events, true);
  ModelManifest manifest = valid_manifest();
  manifest.encrypted_sha256 =
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

  const ModelPackageVerificationResult result =
      verify_model_package(manifest, fixture_path(), 1000, &logger);

  expect_true(!result.ok, "hash mismatch should fail");
  expect_true(result.error == "encrypted model hash mismatch",
              "hash mismatch error should be reported");
  expect_true(events.size() == 1u, "hash mismatch should be logged");
  expect_true(events[0].stage == "manifest", "hash mismatch stage should log");
}

void expired_package_fails_closed() {
  ModelManifest manifest = valid_manifest();
  manifest.expiry_epoch_ms = 1000;

  const ModelPackageVerificationResult result =
      verify_model_package(manifest, fixture_path(), 1000, nullptr);

  expect_true(!result.ok, "expired package should fail");
  expect_true(result.error == "model package expired",
              "expiry error should be reported");
}

void missing_payload_fails_closed() {
  std::vector<LogEvent> events;
  const NativeLogger logger(collect_log, &events, true);

  const ModelPackageVerificationResult result =
      verify_model_package(valid_manifest(), "/missing/model.enc", 1000, &logger);

  expect_true(!result.ok, "missing payload should fail");
  expect_true(result.error == "encrypted model not readable",
              "missing payload error should be reported");
  expect_true(events.size() == 1u, "missing payload should be logged");
  expect_true(events[0].stage == "load", "missing payload stage should log");
}

}  // namespace

int main() {
  valid_package_verifies();
  encrypted_hash_mismatch_fails_closed();
  expired_package_fails_closed();
  missing_payload_fails_closed();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
