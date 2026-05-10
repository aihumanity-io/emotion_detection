#include "emotion_key_material.h"

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

}  // namespace native_sdk
}  // namespace emotion
