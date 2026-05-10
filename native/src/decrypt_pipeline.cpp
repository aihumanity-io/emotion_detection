#include "emotion_decrypt_pipeline.h"

#include <fstream>
#include <sstream>

#include "emotion_crypto.h"
#include "emotion_model_package.h"

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

DecryptPipelineResult decrypt_model_package(
    const EncryptedModelPackage& package,
    const std::array<uint8_t, 32>& user_code,
    const KeyShard& shard,
    int64_t now_ms,
    const NativeLogger* logger) {
  DecryptPipelineResult result;
  const ModelPackageVerificationResult package_result = verify_model_package(
      package.manifest, package.encrypted_model_path, now_ms, logger);
  if (!package_result.ok) {
    result.error = package_result.error;
    return result;
  }

  const KeyMaterialResult key_result =
      derive_model_cek(user_code, shard, package.manifest.kdf_info, now_ms);
  if (!key_result.ok) {
    result.error = key_result.error;
    log_error(logger, kLogStageKeyMaterial, package.manifest.model_id,
              result.error);
    return result;
  }

  std::vector<uint8_t> ciphertext;
  if (!read_file(package.encrypted_model_path, &ciphertext)) {
    result.error = "encrypted model not readable";
    log_error(logger, kLogStageLoad, package.manifest.model_id, result.error);
    return result;
  }

  const std::vector<uint8_t> aad(package.manifest.aad.begin(),
                                 package.manifest.aad.end());
  const AesGcmDecryptResult decrypt_result = aes_256_gcm_decrypt(
      key_result.cek, package.nonce, aad, ciphertext, package.tag);
  if (!decrypt_result.ok) {
    result.error = decrypt_result.error;
    log_error(logger, kLogStageDecrypt, package.manifest.model_id,
              result.error);
    return result;
  }

  if (!verify_sha256_hex(decrypt_result.plaintext,
                         package.manifest.plaintext_sha256)) {
    result.error = "plaintext model hash mismatch";
    log_error(logger, kLogStageManifest, package.manifest.model_id,
              result.error);
    return result;
  }

  result.ok = true;
  result.plaintext = decrypt_result.plaintext;
  return result;
}

}  // namespace native_sdk
}  // namespace emotion
