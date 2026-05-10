#ifndef EMOTION_KEY_MATERIAL_H_
#define EMOTION_KEY_MATERIAL_H_

#include <array>
#include <cstdint>
#include <map>
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

class KeyMaterialStore {
 public:
  void set_user_code(const std::string& user_name,
                     const std::string& model_id,
                     const std::array<uint8_t, 32>& user_code);
  void set_key_shard(const std::string& model_id, const KeyShard& shard);
  void clear_model(const std::string& model_id);

  KeyMaterialResult derive_model_cek(const std::string& user_name,
                                     const std::string& model_id,
                                     const KdfInfo& kdf_info,
                                     int64_t now_ms) const;

 private:
  static std::string user_code_key(const std::string& user_name,
                                   const std::string& model_id);

  std::map<std::string, std::array<uint8_t, 32>> user_codes_;
  std::map<std::string, KeyShard> key_shards_;
};

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_KEY_MATERIAL_H_
