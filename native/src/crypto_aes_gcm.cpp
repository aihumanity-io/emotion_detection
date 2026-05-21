#include "emotion_crypto.h"

#include <mbedtls/gcm.h>

namespace emotion {
namespace native_sdk {
namespace {

bool valid_tag_len(size_t tag_len) {
  return tag_len >= 12u && tag_len <= 16u;
}

bool valid_nonce(const std::vector<uint8_t>& nonce) {
  return !nonce.empty();
}

}  // namespace

AesGcmEncryptResult aes_256_gcm_encrypt(const std::array<uint8_t, 32>& key,
                                        const std::vector<uint8_t>& nonce,
                                        const std::vector<uint8_t>& aad,
                                        const std::vector<uint8_t>& plaintext,
                                        size_t tag_len) {
  AesGcmEncryptResult result;
  if (!valid_nonce(nonce)) {
    result.error = "invalid nonce";
    return result;
  }
  if (!valid_tag_len(tag_len)) {
    result.error = "invalid tag length";
    return result;
  }

  mbedtls_gcm_context context;
  mbedtls_gcm_init(&context);
  int status = mbedtls_gcm_setkey(&context, MBEDTLS_CIPHER_ID_AES, key.data(),
                                  256u);
  if (status != 0) {
    mbedtls_gcm_free(&context);
    result.error = "aes-gcm key setup failed";
    return result;
  }

  result.ciphertext.resize(plaintext.size());
  result.tag.resize(tag_len);
  status = mbedtls_gcm_crypt_and_tag(
      &context, MBEDTLS_GCM_ENCRYPT, plaintext.size(), nonce.data(),
      nonce.size(), aad.data(), aad.size(), plaintext.data(),
      result.ciphertext.data(), tag_len, result.tag.data());
  mbedtls_gcm_free(&context);
  if (status != 0) {
    result.ciphertext.clear();
    result.tag.clear();
    result.error = "aes-gcm encrypt failed";
    return result;
  }

  result.ok = true;
  return result;
}

AesGcmDecryptResult aes_256_gcm_decrypt(const std::array<uint8_t, 32>& key,
                                        const std::vector<uint8_t>& nonce,
                                        const std::vector<uint8_t>& aad,
                                        const std::vector<uint8_t>& ciphertext,
                                        const std::vector<uint8_t>& tag) {
  AesGcmDecryptResult result;
  if (!valid_nonce(nonce)) {
    result.error = "invalid nonce";
    return result;
  }
  if (!valid_tag_len(tag.size())) {
    result.error = "invalid tag length";
    return result;
  }

  mbedtls_gcm_context context;
  mbedtls_gcm_init(&context);
  int status = mbedtls_gcm_setkey(&context, MBEDTLS_CIPHER_ID_AES, key.data(),
                                  256u);
  if (status != 0) {
    mbedtls_gcm_free(&context);
    result.error = "aes-gcm key setup failed";
    return result;
  }

  result.plaintext.resize(ciphertext.size());
  status = mbedtls_gcm_auth_decrypt(
      &context, ciphertext.size(), nonce.data(), nonce.size(), aad.data(),
      aad.size(), tag.data(), tag.size(), ciphertext.data(),
      result.plaintext.data());
  mbedtls_gcm_free(&context);
  if (status != 0) {
    result.plaintext.clear();
    result.error = "aes-gcm authentication failed";
    return result;
  }

  result.ok = true;
  return result;
}

}  // namespace native_sdk
}  // namespace emotion
