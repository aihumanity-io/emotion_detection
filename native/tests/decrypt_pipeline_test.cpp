#include "emotion_decrypt_pipeline.h"

#include <array>
#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "emotion_crypto.h"

namespace {

using emotion::native_sdk::DecryptPipelineResult;
using emotion::native_sdk::EncryptedModelPackage;
using emotion::native_sdk::KeyShard;
using emotion::native_sdk::ModelManifest;
using emotion::native_sdk::NativeLogger;
using emotion::native_sdk::aes_256_gcm_encrypt;
using emotion::native_sdk::decrypt_model_package;
using emotion::native_sdk::sha256_hex;

struct LogEvent {
  emotion_log_level_t level;
  std::string stage;
  std::string model_id;
  std::string message;
};

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

void collect_log(emotion_log_level_t level,
                 const char* stage,
                 const char* model_id,
                 const char* message,
                 void* user_data) {
  std::vector<LogEvent>* events = static_cast<std::vector<LogEvent>*>(user_data);
  events->push_back({level, stage, model_id, message});
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

std::array<uint8_t, 32> sequential_user_code() {
  std::array<uint8_t, 32> user_code = {};
  for (size_t i = 0; i < user_code.size(); ++i) {
    user_code[i] = static_cast<uint8_t>(i);
  }
  return user_code;
}

std::array<uint8_t, 32> fixture_cek() {
  const std::vector<uint8_t> bytes = bytes_from_hex(
      "c35f976060b3f8090522d7ca71cac866"
      "ea310f396c582f9abc6c2c0609c1a0b2");
  std::array<uint8_t, 32> key = {};
  std::copy(bytes.begin(), bytes.end(), key.begin());
  return key;
}

KeyShard test_shard() {
  KeyShard shard;
  shard.bytes = {0xa0u, 0xa1u, 0xa2u, 0xa3u, 0xa4u, 0xa5u, 0xa6u, 0xa7u};
  shard.expires_at_ms = 2000;
  return shard;
}

ModelManifest test_manifest() {
  ModelManifest manifest;
  manifest.model_id = "aih_fer2025";
  manifest.aad = "com.tartalabs.emotion/aih_fer2025";
  manifest.kdf_info.algorithm = "hkdf-sha256";
  manifest.kdf_info.salt_b64 = "base64:AAAAAAAAAAAAAAAAAAAAAA==";
  manifest.kdf_info.info = "emotion-sdk:model:aih_fer2025";
  manifest.encrypted_sha256 = "";
  manifest.plaintext_sha256 =
      "b19f9eea2705e910be9654ebbee8becdefad237fbb441005954cfcf3f8a7330b";
  return manifest;
}

std::string write_fixture_ciphertext(const std::vector<uint8_t>& bytes) {
  const std::string path = "fixture_model_aes_gcm.enc";
  std::ofstream output(path.c_str(), std::ios::out | std::ios::binary);
  output.write(reinterpret_cast<const char*>(bytes.data()),
               static_cast<std::streamsize>(bytes.size()));
  return path;
}

EncryptedModelPackage test_package() {
  const std::vector<uint8_t> plaintext = {
      'f', 'i', 'x', 't', 'u', 'r', 'e', ' ', 'p', 'l', 'a', 'i', 'n',
      't', 'e', 'x', 't', ' ', 'm', 'o', 'd', 'e', 'l', ' ', 'b', 'y',
      't', 'e', 's', '\n'};
  const std::vector<uint8_t> aad = {
      'c', 'o', 'm', '.', 't', 'a', 'r', 't', 'a', 'l', 'a', 'b',
      's', '.', 'e', 'm', 'o', 't', 'i', 'o', 'n', '/', 'a', 'i',
      'h', '_', 'f', 'e', 'r', '2', '0', '2', '5'};
  const std::vector<uint8_t> nonce = bytes_from_hex("101112131415161718191a1b");
  const emotion::native_sdk::AesGcmEncryptResult encrypted =
      aes_256_gcm_encrypt(fixture_cek(), nonce, aad, plaintext, 16u);

  EncryptedModelPackage package;
  package.manifest = test_manifest();
  package.manifest.encrypted_sha256 = sha256_hex(encrypted.ciphertext);
  package.encrypted_model_path = write_fixture_ciphertext(encrypted.ciphertext);
  package.nonce = nonce;
  package.tag = encrypted.tag;
  return package;
}

void valid_package_decrypts_and_verifies_plaintext_hash() {
  std::vector<LogEvent> events;
  const NativeLogger logger(collect_log, &events, true);

  const DecryptPipelineResult result =
      decrypt_model_package(test_package(), sequential_user_code(), test_shard(),
                            1000, &logger);

  expect_true(result.ok, "valid package should decrypt");
  expect_true(std::string(result.plaintext.begin(), result.plaintext.end()) ==
                  "fixture plaintext model bytes\n",
              "plaintext bytes should match fixture");
  expect_true(events.empty(), "valid decrypt should not log errors");
}

void expired_shard_fails_before_decrypt() {
  std::vector<LogEvent> events;
  const NativeLogger logger(collect_log, &events, true);

  const DecryptPipelineResult result =
      decrypt_model_package(test_package(), sequential_user_code(), test_shard(),
                            2000, &logger);

  expect_true(!result.ok, "expired shard should fail");
  expect_true(result.error == "expired key shard",
              "expired shard error should be reported");
  expect_true(events.size() == 1u, "expired shard should be logged");
  expect_true(events[0].stage == "key_material",
              "expired shard stage should be key material");
}

void wrong_tag_fails_without_plaintext() {
  std::vector<LogEvent> events;
  const NativeLogger logger(collect_log, &events, true);
  EncryptedModelPackage package = test_package();
  package.tag[0] ^= 0x01u;

  const DecryptPipelineResult result =
      decrypt_model_package(package, sequential_user_code(), test_shard(), 1000,
                            &logger);

  expect_true(!result.ok, "wrong tag should fail");
  expect_true(result.error == "aes-gcm authentication failed",
              "auth failure should be reported");
  expect_true(result.plaintext.empty(), "auth failure should not expose plaintext");
  expect_true(events.size() == 1u, "auth failure should be logged");
  expect_true(events[0].stage == "decrypt", "auth failure stage should decrypt");
}

void plaintext_hash_mismatch_fails_closed() {
  std::vector<LogEvent> events;
  const NativeLogger logger(collect_log, &events, true);
  EncryptedModelPackage package = test_package();
  package.manifest.plaintext_sha256 =
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

  const DecryptPipelineResult result =
      decrypt_model_package(package, sequential_user_code(), test_shard(), 1000,
                            &logger);

  expect_true(!result.ok, "plaintext hash mismatch should fail");
  expect_true(result.error == "plaintext model hash mismatch",
              "plaintext mismatch error should be reported");
  expect_true(events.size() == 1u, "plaintext mismatch should be logged");
  expect_true(events[0].stage == "manifest",
              "plaintext mismatch stage should be manifest");
}

}  // namespace

int main() {
  valid_package_decrypts_and_verifies_plaintext_hash();
  expired_shard_fails_before_decrypt();
  wrong_tag_fails_without_plaintext();
  plaintext_hash_mismatch_fails_closed();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
