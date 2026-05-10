#include "emotion_key_material.h"

#include <array>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

using emotion::native_sdk::KeyMaterialResult;
using emotion::native_sdk::KeyMaterialStore;
using emotion::native_sdk::KeyShard;
using emotion::native_sdk::KdfInfo;
using emotion::native_sdk::derive_model_cek;
using emotion::native_sdk::is_key_shard_expired;

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

std::array<uint8_t, 32> sequential_user_code() {
  std::array<uint8_t, 32> user_code = {};
  for (size_t i = 0; i < user_code.size(); ++i) {
    user_code[i] = static_cast<uint8_t>(i);
  }
  return user_code;
}

std::array<uint8_t, 32> shifted_user_code() {
  std::array<uint8_t, 32> user_code = {};
  for (size_t i = 0; i < user_code.size(); ++i) {
    user_code[i] = static_cast<uint8_t>(0x80u + i);
  }
  return user_code;
}

std::string hex_from_array(const std::array<uint8_t, 32>& bytes) {
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

KdfInfo test_kdf_info() {
  KdfInfo kdf_info;
  kdf_info.algorithm = "hkdf-sha256";
  kdf_info.salt_b64 = "base64:AAAAAAAAAAAAAAAAAAAAAA==";
  kdf_info.info = "emotion-sdk:model:aih_fer2025";
  return kdf_info;
}

KeyShard test_shard() {
  KeyShard shard;
  shard.bytes = {0xa0u, 0xa1u, 0xa2u, 0xa3u, 0xa4u, 0xa5u, 0xa6u, 0xa7u};
  shard.expires_at_ms = 2000;
  return shard;
}

void valid_material_derives_stable_cek() {
  const KeyMaterialResult result = derive_model_cek(
      sequential_user_code(), test_shard(), test_kdf_info(), 1000);

  expect_true(result.ok, "valid key material should derive CEK");
  expect_true(
      hex_from_array(result.cek) ==
          "c35f976060b3f8090522d7ca71cac866"
          "ea310f396c582f9abc6c2c0609c1a0b2",
      "derived CEK should match stable test vector");
}

void shard_expiry_is_enforced() {
  const KeyShard shard = test_shard();

  expect_true(!is_key_shard_expired(shard, 1999),
              "shard should be valid before expiry");
  expect_true(is_key_shard_expired(shard, 2000),
              "shard should expire at expiry timestamp");

  const KeyMaterialResult result =
      derive_model_cek(sequential_user_code(), shard, test_kdf_info(), 2000);
  expect_true(!result.ok, "expired shard should fail CEK derivation");
  expect_true(result.error == "expired key shard",
              "expired shard error should be reported");
}

void unsupported_kdf_is_rejected() {
  KdfInfo kdf_info = test_kdf_info();
  kdf_info.algorithm = "pbkdf2-sha256";

  const KeyMaterialResult result =
      derive_model_cek(sequential_user_code(), test_shard(), kdf_info, 1000);

  expect_true(!result.ok, "unsupported KDF should fail");
  expect_true(result.error == "unsupported kdf_info.algorithm",
              "unsupported KDF error should be reported");
}

void missing_shard_is_rejected() {
  KeyShard shard;
  shard.expires_at_ms = 2000;

  const KeyMaterialResult result =
      derive_model_cek(sequential_user_code(), shard, test_kdf_info(), 1000);

  expect_true(!result.ok, "missing shard should fail");
  expect_true(result.error == "missing key shard",
              "missing shard error should be reported");
}

void store_isolates_user_code_by_user_and_model() {
  KeyMaterialStore store;
  store.set_key_shard("model-a", test_shard());
  store.set_key_shard("model-b", test_shard());
  store.set_user_code("david@example.com", "model-a", sequential_user_code());
  store.set_user_code("david@example.com", "model-b", shifted_user_code());
  store.set_user_code("alex@example.com", "model-a", shifted_user_code());

  const KeyMaterialResult david_model_a = store.derive_model_cek(
      "david@example.com", "model-a", test_kdf_info(), 1000);
  const KeyMaterialResult david_model_b = store.derive_model_cek(
      "david@example.com", "model-b", test_kdf_info(), 1000);
  const KeyMaterialResult alex_model_a = store.derive_model_cek(
      "alex@example.com", "model-a", test_kdf_info(), 1000);

  expect_true(david_model_a.ok, "user/model A should derive CEK");
  expect_true(david_model_b.ok, "same user/model B should derive CEK");
  expect_true(alex_model_a.ok, "different user/same model should derive CEK");
  expect_true(david_model_a.cek != david_model_b.cek,
              "same user state should be isolated by model");
  expect_true(david_model_a.cek != alex_model_a.cek,
              "same model state should be isolated by user");
}

void store_reports_missing_user_code() {
  KeyMaterialStore store;
  store.set_key_shard("model-a", test_shard());

  const KeyMaterialResult result = store.derive_model_cek(
      "missing@example.com", "model-a", test_kdf_info(), 1000);

  expect_true(!result.ok, "missing user code should fail");
  expect_true(result.error == "missing user code",
              "missing user code error should be reported");
}

void clear_model_removes_shard_and_user_codes() {
  KeyMaterialStore store;
  store.set_key_shard("model-a", test_shard());
  store.set_user_code("david@example.com", "model-a", sequential_user_code());
  store.clear_model("model-a");

  const KeyMaterialResult result = store.derive_model_cek(
      "david@example.com", "model-a", test_kdf_info(), 1000);

  expect_true(!result.ok, "cleared model should fail");
  expect_true(result.error == "missing user code",
              "cleared user code should be reported first");
}

}  // namespace

int main() {
  valid_material_derives_stable_cek();
  shard_expiry_is_enforced();
  unsupported_kdf_is_rejected();
  missing_shard_is_rejected();
  store_isolates_user_code_by_user_and_model();
  store_reports_missing_user_code();
  clear_model_removes_shard_and_user_codes();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
