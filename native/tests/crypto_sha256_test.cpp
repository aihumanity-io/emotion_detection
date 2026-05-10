#include "emotion_crypto.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

using emotion::native_sdk::sha256_hex;
using emotion::native_sdk::verify_sha256_hex;

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

std::vector<uint8_t> bytes_from_string(const std::string& value) {
  return std::vector<uint8_t>(value.begin(), value.end());
}

void empty_string_matches_nist_vector() {
  const std::vector<uint8_t> input;

  expect_true(
      sha256_hex(input) ==
          "e3b0c44298fc1c149afbf4c8996fb924"
          "27ae41e4649b934ca495991b7852b855",
      "empty string SHA-256 should match known vector");
}

void abc_matches_nist_vector() {
  const std::vector<uint8_t> input = bytes_from_string("abc");

  expect_true(
      sha256_hex(input) ==
          "ba7816bf8f01cfea414140de5dae2223"
          "b00361a396177a9cb410ff61f20015ad",
      "abc SHA-256 should match known vector");
}

void long_message_matches_nist_vector() {
  const std::vector<uint8_t> input =
      bytes_from_string("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");

  expect_true(
      sha256_hex(input) ==
          "248d6a61d20638b8e5c026930c3e6039"
          "a33ce45964ff2167f6ecedd419db06c1",
      "long message SHA-256 should match known vector");
}

void verify_accepts_matching_lowercase_hex() {
  const std::vector<uint8_t> input = bytes_from_string("abc");

  expect_true(
      verify_sha256_hex(input,
                        "ba7816bf8f01cfea414140de5dae2223"
                        "b00361a396177a9cb410ff61f20015ad"),
      "matching hash should verify");
}

void verify_rejects_mismatch_and_malformed_hex() {
  const std::vector<uint8_t> input = bytes_from_string("abc");

  expect_true(!verify_sha256_hex(input,
                                 "e3b0c44298fc1c149afbf4c8996fb924"
                                 "27ae41e4649b934ca495991b7852b855"),
              "mismatched hash should fail");
  expect_true(!verify_sha256_hex(input, "not-a-sha256"),
              "malformed hash should fail");
  expect_true(!verify_sha256_hex(input,
                                 "BA7816BF8F01CFEA414140DE5DAE2223"
                                 "B00361A396177A9CB410FF61F20015AD"),
              "uppercase hash should fail schema validation");
}

}  // namespace

int main() {
  empty_string_matches_nist_vector();
  abc_matches_nist_vector();
  long_message_matches_nist_vector();
  verify_accepts_matching_lowercase_hex();
  verify_rejects_mismatch_and_malformed_hex();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
