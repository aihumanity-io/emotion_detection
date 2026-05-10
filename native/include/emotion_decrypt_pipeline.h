#ifndef EMOTION_DECRYPT_PIPELINE_H_
#define EMOTION_DECRYPT_PIPELINE_H_

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "emotion_key_material.h"
#include "emotion_logging.h"
#include "emotion_model_manifest.h"

namespace emotion {
namespace native_sdk {

struct EncryptedModelPackage {
  ModelManifest manifest;
  std::string encrypted_model_path;
  std::vector<uint8_t> nonce;
  std::vector<uint8_t> tag;
};

struct DecryptPipelineResult {
  bool ok = false;
  std::vector<uint8_t> plaintext;
  std::string error;
};

DecryptPipelineResult decrypt_model_package(
    const EncryptedModelPackage& package,
    const std::array<uint8_t, 32>& user_code,
    const KeyShard& shard,
    int64_t now_ms,
    const NativeLogger* logger);

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_DECRYPT_PIPELINE_H_
