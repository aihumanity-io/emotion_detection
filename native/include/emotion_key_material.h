#ifndef EMOTION_KEY_MATERIAL_H_
#define EMOTION_KEY_MATERIAL_H_

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "emotion_model_manifest.h"

namespace emotion {
namespace native_sdk {

struct KeyShard {
  std::vector<uint8_t> bytes;
  int64_t expires_at_ms = 0;
};

struct KeyMaterialResult {
  bool ok = false;
  std::array<uint8_t, 32> cek = {};
  std::string error;
};

bool is_key_shard_expired(const KeyShard& shard, int64_t now_ms);

KeyMaterialResult derive_model_cek(const std::array<uint8_t, 32>& user_code,
                                   const KeyShard& shard,
                                   const KdfInfo& kdf_info,
                                   int64_t now_ms);

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_KEY_MATERIAL_H_
