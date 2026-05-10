#include "emotion_key_material.h"

#include <algorithm>
#include <cstdlib>

#include "emotion_crypto.h"

namespace emotion {
namespace native_sdk {
namespace {

int hex_value(char character) {
  if (character >= '0' && character <= '9') {
    return character - '0';
  }
  if (character >= 'a' && character <= 'f') {
    return 10 + character - 'a';
  }
  if (character >= 'A' && character <= 'F') {
    return 10 + character - 'A';
  }
  return -1;
}

bool decode_hex(const std::string& hex, std::vector<uint8_t>* output) {
  if ((hex.size() % 2u) != 0u) {
    return false;
  }
  output->clear();
  output->reserve(hex.size() / 2u);
  for (size_t i = 0; i < hex.size(); i += 2u) {
    const int high = hex_value(hex[i]);
    const int low = hex_value(hex[i + 1u]);
    if (high < 0 || low < 0) {
      return false;
    }
    output->push_back(static_cast<uint8_t>((high << 4) | low));
  }
  return true;
}

bool decode_base64(const std::string& base64, std::vector<uint8_t>* output) {
  static const std::string alphabet =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  output->clear();
  int value = 0;
  int bits = -8;
  for (char character : base64) {
    if (character == '=') {
      break;
    }
    const std::string::size_type index = alphabet.find(character);
    if (index == std::string::npos) {
      return false;
    }
    value = (value << 6) + static_cast<int>(index);
    bits += 6;
    if (bits >= 0) {
      output->push_back(static_cast<uint8_t>((value >> bits) & 0xff));
      bits -= 8;
    }
  }
  return true;
}

bool decode_kdf_salt(const std::string& salt, std::vector<uint8_t>* output) {
  if (salt.find("hex:") == 0u) {
    return decode_hex(salt.substr(4u), output);
  }
  if (salt.find("base64:") == 0u) {
    return decode_base64(salt.substr(7u), output);
  }
  return decode_base64(salt, output);
}

std::vector<uint8_t> bytes_from_string(const std::string& value) {
  return std::vector<uint8_t>(value.begin(), value.end());
}

}  // namespace

bool is_key_shard_expired(const KeyShard& shard, int64_t now_ms) {
  return shard.expires_at_ms > 0 && now_ms >= shard.expires_at_ms;
}

KeyMaterialResult derive_model_cek(const std::array<uint8_t, 32>& user_code,
                                   const KeyShard& shard,
                                   const KdfInfo& kdf_info,
                                   int64_t now_ms) {
  KeyMaterialResult result;
  if (kdf_info.algorithm != "hkdf-sha256") {
    result.error = "unsupported kdf_info.algorithm";
    return result;
  }
  if (shard.bytes.empty()) {
    result.error = "missing key shard";
    return result;
  }
  if (is_key_shard_expired(shard, now_ms)) {
    result.error = "expired key shard";
    return result;
  }

  std::vector<uint8_t> salt;
  if (!decode_kdf_salt(kdf_info.salt_b64, &salt)) {
    result.error = "invalid kdf_info.salt_b64";
    return result;
  }

  std::vector<uint8_t> ikm(user_code.begin(), user_code.end());
  ikm.insert(ikm.end(), shard.bytes.begin(), shard.bytes.end());
  const std::vector<uint8_t> info = bytes_from_string(kdf_info.info);
  const std::vector<uint8_t> cek = hkdf_sha256(ikm, salt, info, 32u);
  if (cek.size() != result.cek.size()) {
    result.error = "cek derivation failed";
    return result;
  }

  std::copy(cek.begin(), cek.end(), result.cek.begin());
  result.ok = true;
  return result;
}

void KeyMaterialStore::set_user_code(
    const std::string& user_name,
    const std::string& model_id,
    const std::array<uint8_t, 32>& user_code) {
  user_codes_[user_code_key(user_name, model_id)] = user_code;
}

void KeyMaterialStore::set_key_shard(const std::string& model_id,
                                     const KeyShard& shard) {
  key_shards_[model_id] = shard;
}

void KeyMaterialStore::clear_model(const std::string& model_id) {
  key_shards_.erase(model_id);
  for (std::map<std::string, std::array<uint8_t, 32>>::iterator it =
           user_codes_.begin();
       it != user_codes_.end();) {
    const std::string suffix = "\n" + model_id;
    if (it->first.size() >= suffix.size() &&
        it->first.compare(it->first.size() - suffix.size(), suffix.size(),
                          suffix) == 0) {
      it = user_codes_.erase(it);
    } else {
      ++it;
    }
  }
}

KeyMaterialResult KeyMaterialStore::derive_model_cek(
    const std::string& user_name,
    const std::string& model_id,
    const KdfInfo& kdf_info,
    int64_t now_ms) const {
  const std::map<std::string, std::array<uint8_t, 32>>::const_iterator user_it =
      user_codes_.find(user_code_key(user_name, model_id));
  if (user_it == user_codes_.end()) {
    KeyMaterialResult result;
    result.error = "missing user code";
    return result;
  }

  const std::map<std::string, KeyShard>::const_iterator shard_it =
      key_shards_.find(model_id);
  if (shard_it == key_shards_.end()) {
    KeyMaterialResult result;
    result.error = "missing key shard";
    return result;
  }

  return native_sdk::derive_model_cek(user_it->second, shard_it->second,
                                      kdf_info, now_ms);
}

std::string KeyMaterialStore::user_code_key(const std::string& user_name,
                                            const std::string& model_id) {
  return user_name + "\n" + model_id;
}

}  // namespace native_sdk
}  // namespace emotion
