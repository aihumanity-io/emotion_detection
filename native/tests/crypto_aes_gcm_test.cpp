#include "emotion_crypto.h"

#include <array>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

using emotion::native_sdk::AesGcmDecryptResult;
using emotion::native_sdk::AesGcmEncryptResult;
using emotion::native_sdk::aes_256_gcm_decrypt;
using emotion::native_sdk::aes_256_gcm_encrypt;

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

std::vector<uint8_t> bytes_from_hex(const std::string& hex) {
  std::vector<uint8_t> bytes;
  for (size_t i = 0; i + 1u < hex.size(); i += 2u) {
    const std::string byte_hex = hex.substr(i, 2u);
    bytes.push_back(
        static_cast<uint8_t>(std::strtoul(byte_hex.c_str(), nullptr, 16)));
  }
  return bytes;
}

std::string hex_from_bytes(const std::vector<uint8_t>& bytes) {
  std::ostringstream output;
  output << std::hex;
  for (uint8_t byte : bytes) {
    if (byte < 16u) {
      output << '0';
    }
    output << static_cast<int>(byte);
  }
  return output.str();
}

std::array<uint8_t, 32> zero_key() {
  std::array<uint8_t, 32> key = {};
  return key;
}

void nist_empty_plaintext_vector_matches() {
  const std::vector<uint8_t> nonce = bytes_from_hex("000000000000000000000000");

  const AesGcmEncryptResult encrypted =
      aes_256_gcm_encrypt(zero_key(), nonce, {}, {}, 16u);

  expect_true(encrypted.ok, "empty plaintext encrypt should succeed");
  expect_true(encrypted.ciphertext.empty(), "empty plaintext has no ciphertext");
  expect_true(hex_from_bytes(encrypted.tag) == "530f8afbc74536b9a963b4f1c4cb738b",
              "AES-256-GCM empty vector tag should match");
}

void nist_single_block_vector_matches_and_decrypts() {
  const std::vector<uint8_t> nonce = bytes_from_hex("000000000000000000000000");
  const std::vector<uint8_t> plaintext =
      bytes_from_hex("00000000000000000000000000000000");

  const AesGcmEncryptResult encrypted =
      aes_256_gcm_encrypt(zero_key(), nonce, {}, plaintext, 16u);
  const AesGcmDecryptResult decrypted = aes_256_gcm_decrypt(
      zero_key(), nonce, {}, encrypted.ciphertext, encrypted.tag);

  expect_true(encrypted.ok, "single block encrypt should succeed");
  expect_true(hex_from_bytes(encrypted.ciphertext) ==
                  "cea7403d4d606b6e074ec5d3baf39d18",
              "AES-256-GCM ciphertext should match NIST vector");
  expect_true(hex_from_bytes(encrypted.tag) ==
                  "d0d1c8a799996bf0265b98b5d48ab919",
              "AES-256-GCM tag should match NIST vector");
  expect_true(decrypted.ok, "single block decrypt should succeed");
  expect_true(decrypted.plaintext == plaintext,
              "decrypt should recover plaintext");
}

void aad_round_trip_succeeds() {
  const std::vector<uint8_t> nonce = bytes_from_hex("101112131415161718191a1b");
  const std::vector<uint8_t> aad = bytes_from_hex("0001020304050607");
  const std::vector<uint8_t> plaintext = bytes_from_hex("2021222324252627");

  const AesGcmEncryptResult encrypted =
      aes_256_gcm_encrypt(zero_key(), nonce, aad, plaintext, 16u);
  const AesGcmDecryptResult decrypted = aes_256_gcm_decrypt(
      zero_key(), nonce, aad, encrypted.ciphertext, encrypted.tag);

  expect_true(encrypted.ok, "AAD encrypt should succeed");
  expect_true(decrypted.ok, "AAD decrypt should succeed");
  expect_true(decrypted.plaintext == plaintext,
              "AAD decrypt should recover plaintext");
}

void wrong_tag_fails_closed() {
  const std::vector<uint8_t> nonce = bytes_from_hex("000000000000000000000000");
  const std::vector<uint8_t> plaintext =
      bytes_from_hex("00000000000000000000000000000000");
  AesGcmEncryptResult encrypted =
      aes_256_gcm_encrypt(zero_key(), nonce, {}, plaintext, 16u);
  encrypted.tag[0] ^= 0x01u;

  const AesGcmDecryptResult decrypted = aes_256_gcm_decrypt(
      zero_key(), nonce, {}, encrypted.ciphertext, encrypted.tag);

  expect_true(!decrypted.ok, "wrong tag should fail");
  expect_true(decrypted.error == "aes-gcm authentication failed",
              "wrong tag error should be reported");
  expect_true(decrypted.plaintext.empty(),
              "failed auth should not return plaintext");
}

void invalid_inputs_fail_closed() {
  const AesGcmEncryptResult bad_nonce =
      aes_256_gcm_encrypt(zero_key(), {}, {}, {}, 16u);
  const AesGcmEncryptResult bad_tag_len = aes_256_gcm_encrypt(
      zero_key(), bytes_from_hex("000000000000000000000000"), {}, {}, 8u);

  expect_true(!bad_nonce.ok, "empty nonce should fail");
  expect_true(bad_nonce.error == "invalid nonce",
              "empty nonce error should be reported");
  expect_true(!bad_tag_len.ok, "short tag should fail");
  expect_true(bad_tag_len.error == "invalid tag length",
              "short tag error should be reported");
}

}  // namespace

int main() {
  nist_empty_plaintext_vector_matches();
  nist_single_block_vector_matches_and_decrypts();
  aad_round_trip_succeeds();
  wrong_tag_fails_closed();
  invalid_inputs_fail_closed();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
