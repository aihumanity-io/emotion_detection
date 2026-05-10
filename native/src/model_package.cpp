#include "emotion_model_package.h"

#include <fstream>
#include <sstream>

#include "emotion_crypto.h"

namespace emotion {
namespace native_sdk {
namespace {

bool read_file(const std::string& path, std::vector<uint8_t>* output) {
  std::ifstream input(path.c_str(), std::ios::in | std::ios::binary);
  if (!input) {
    return false;
  }
  std::ostringstream buffer;
  buffer << input.rdbuf();
  const std::string bytes = buffer.str();
  output->assign(bytes.begin(), bytes.end());
  return true;
}

void log_error(const NativeLogger* logger,
               const std::string& stage,
               const std::string& model_id,
               const std::string& message) {
  if (logger != nullptr) {
    logger->error(stage, model_id, message);
  }
}

}  // namespace

ModelPackageVerificationResult verify_model_package(
    const ModelManifest& manifest,
    const std::string& encrypted_model_path,
    int64_t now_ms,
    const NativeLogger* logger) {
  ModelPackageVerificationResult result;
  if (manifest.expiry_epoch_ms > 0 && now_ms >= manifest.expiry_epoch_ms) {
    result.error = "model package expired";
    log_error(logger, kLogStageManifest, manifest.model_id, result.error);
    return result;
  }

  std::vector<uint8_t> encrypted_payload;
  if (!read_file(encrypted_model_path, &encrypted_payload)) {
    result.error = "encrypted model not readable";
    log_error(logger, kLogStageLoad, manifest.model_id, result.error);
    return result;
  }

  if (!verify_sha256_hex(encrypted_payload, manifest.encrypted_sha256)) {
    result.error = "encrypted model hash mismatch";
    log_error(logger, kLogStageManifest, manifest.model_id, result.error);
    return result;
  }

  result.ok = true;
  return result;
}

}  // namespace native_sdk
}  // namespace emotion
