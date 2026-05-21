#ifndef EMOTION_CRYPTO_H_
#define EMOTION_CRYPTO_H_

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace emotion {
namespace native_sdk {

struct AesGcmDecryptResult {
  bool ok = false;
  std::vector<uint8_t> plaintext;
  std::string error;
};

struct AesGcmEncryptResult {
  bool ok = false;
  std::vector<uint8_t> ciphertext;
  std::vector<uint8_t> tag;
  std::string error;
};

std::array<uint8_t, 32> sha256(const uint8_t* data, size_t data_len);
std::array<uint8_t, 32> sha256(const std::vector<uint8_t>& data);

std::string sha256_hex(const uint8_t* data, size_t data_len);
std::string sha256_hex(const std::vector<uint8_t>& data);

std::array<uint8_t, 32> hmac_sha256(const uint8_t* key,
                                    size_t key_len,
                                    const uint8_t* data,
                                    size_t data_len);
std::array<uint8_t, 32> hmac_sha256(const std::vector<uint8_t>& key,
                                    const std::vector<uint8_t>& data);
std::string hmac_sha256_hex(const std::vector<uint8_t>& key,
                            const std::vector<uint8_t>& data);

std::array<uint8_t, 32> hkdf_sha256_extract(const std::vector<uint8_t>& salt,
                                            const std::vector<uint8_t>& ikm);
std::vector<uint8_t> hkdf_sha256_expand(const std::vector<uint8_t>& prk,
                                        const std::vector<uint8_t>& info,
                                        size_t output_len);
std::vector<uint8_t> hkdf_sha256(const std::vector<uint8_t>& ikm,
                                 const std::vector<uint8_t>& salt,
                                 const std::vector<uint8_t>& info,
                                 size_t output_len);

AesGcmEncryptResult aes_256_gcm_encrypt(const std::array<uint8_t, 32>& key,
                                        const std::vector<uint8_t>& nonce,
                                        const std::vector<uint8_t>& aad,
                                        const std::vector<uint8_t>& plaintext,
                                        size_t tag_len);
AesGcmDecryptResult aes_256_gcm_decrypt(const std::array<uint8_t, 32>& key,
                                        const std::vector<uint8_t>& nonce,
                                        const std::vector<uint8_t>& aad,
                                        const std::vector<uint8_t>& ciphertext,
                                        const std::vector<uint8_t>& tag);

bool verify_sha256_hex(const uint8_t* data,
                       size_t data_len,
                       const std::string& expected_hex);
bool verify_sha256_hex(const std::vector<uint8_t>& data,
                       const std::string& expected_hex);

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_CRYPTO_H_
