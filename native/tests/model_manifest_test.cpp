#include "emotion_model_manifest.h"

#include <cstdlib>
#include <iostream>
#include <string>

namespace {

using emotion::native_sdk::ManifestParseResult;
using emotion::native_sdk::parse_model_manifest_file;
using emotion::native_sdk::parse_model_manifest_json;

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

bool has_error(const ManifestParseResult& result, const std::string& message) {
  for (const std::string& error : result.errors) {
    if (error == message) {
      return true;
    }
  }
  return false;
}

std::string valid_manifest_json() {
  return R"json({
    "manifest_schema_version": 1,
    "model_id": "aih_fer2025",
    "model_version": "2025.03.13",
    "model_format": "onnx",
    "input_shape": [1, 224, 224, 3],
    "labels": ["neutral"],
    "aad": "com.tartalabs.emotion/aih_fer2025",
    "kdf_info": {
      "algorithm": "hkdf-sha256",
      "salt_b64": "AAAAAAAAAAAAAAAAAAAAAA==",
      "info": "emotion-sdk:model:aih_fer2025"
    },
    "shard_required": true,
    "expiry_epoch_ms": 0,
    "encrypted_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "plaintext_sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
    "runtime_min_version": "0.1.0",
    "sdk_min_version": "0.2.0",
    "signature_algorithm": "ed25519"
  })json";
}

std::string replace_once(std::string input,
                         const std::string& needle,
                         const std::string& replacement) {
  const std::string::size_type position = input.find(needle);
  if (position != std::string::npos) {
    input.replace(position, needle.size(), replacement);
  }
  return input;
}

std::string manifest_path(const std::string& name) {
  return std::string(EMOTION_TEST_MANIFEST_DIR) + "/" + name;
}

void valid_manifest_parses() {
  const ManifestParseResult result =
      parse_model_manifest_file(manifest_path("valid_fer2025.json"));

  expect_true(result.ok, "valid manifest should parse");
  expect_true(result.manifest.model_id == "aih_fer2025",
              "model_id should be populated");
  expect_true(result.manifest.input_shape.size() == 4,
              "input_shape should be populated");
  expect_true(result.manifest.labels.size() == 5, "labels should be populated");
  expect_true(result.manifest.kdf_info.algorithm == "hkdf-sha256",
              "kdf algorithm should be populated");
}

void unsupported_schema_rejected() {
  const ManifestParseResult result = parse_model_manifest_file(
      manifest_path("invalid_unsupported_version.json"));

  expect_true(!result.ok, "unsupported schema should fail");
  expect_true(has_error(result, "unsupported manifest_schema_version"),
              "unsupported schema error should be reported");
}

void unsupported_model_format_rejected() {
  const ManifestParseResult result = parse_model_manifest_json(
      replace_once(valid_manifest_json(), "\"model_format\": \"onnx\"",
                   "\"model_format\": \"tflite\""));

  expect_true(!result.ok, "unsupported model_format should fail");
  expect_true(has_error(result, "unsupported model_format"),
              "unsupported model format error should be reported");
}

void malformed_hash_rejected() {
  const ManifestParseResult result = parse_model_manifest_json(
      replace_once(
          valid_manifest_json(),
          "\"encrypted_sha256\": "
          "\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"",
          "\"encrypted_sha256\": \"not-a-hash\""));

  expect_true(!result.ok, "malformed hash should fail");
  expect_true(has_error(result, "invalid encrypted_sha256"),
              "hash error should be reported");
}

void missing_required_field_rejected() {
  const ManifestParseResult result = parse_model_manifest_json("{}");

  expect_true(!result.ok, "missing required fields should fail");
  expect_true(has_error(result, "missing model_id"),
              "missing field error should be reported");
}

}  // namespace

int main() {
  valid_manifest_parses();
  unsupported_schema_rejected();
  unsupported_model_format_rejected();
  malformed_hash_rejected();
  missing_required_field_rejected();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
