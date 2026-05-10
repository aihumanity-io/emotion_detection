#include "emotion_crypto.h"

#include <array>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

using emotion::native_sdk::hkdf_sha256;
using emotion::native_sdk::hkdf_sha256_expand;
using emotion::native_sdk::hkdf_sha256_extract;
using emotion::native_sdk::hmac_sha256_hex;

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

std::vector<uint8_t> repeat_byte(uint8_t value, size_t count) {
  return std::vector<uint8_t>(count, value);
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

template <size_t Size>
std::string hex_from_array(const std::array<uint8_t, Size>& bytes) {
  return hex_from_bytes(std::vector<uint8_t>(bytes.begin(), bytes.end()));
}

void hmac_matches_rfc4231_case_1() {
  const std::vector<uint8_t> key = repeat_byte(0x0bu, 20u);
  const std::vector<uint8_t> data = bytes_from_string("Hi There");

  expect_true(
      hmac_sha256_hex(key, data) ==
          "b0344c61d8db38535ca8afceaf0bf12b"
          "881dc200c9833da726e9376c2e32cff7",
      "HMAC-SHA256 RFC 4231 case 1 should match");
}

void hmac_matches_rfc4231_case_2() {
  const std::vector<uint8_t> key = bytes_from_string("Jefe");
  const std::vector<uint8_t> data =
      bytes_from_string("what do ya want for nothing?");

  expect_true(
      hmac_sha256_hex(key, data) ==
          "5bdcc146bf60754e6a042426089575c7"
          "5a003f089d2739839dec58b964ec3843",
      "HMAC-SHA256 RFC 4231 case 2 should match");
}

void hkdf_matches_rfc5869_case_1() {
  const std::vector<uint8_t> ikm = repeat_byte(0x0bu, 22u);
  const std::vector<uint8_t> salt = bytes_from_hex("000102030405060708090a0b0c");
  const std::vector<uint8_t> info = bytes_from_hex("f0f1f2f3f4f5f6f7f8f9");

  const std::array<uint8_t, 32> prk = hkdf_sha256_extract(salt, ikm);
  const std::vector<uint8_t> okm = hkdf_sha256_expand(
      std::vector<uint8_t>(prk.begin(), prk.end()), info, 42u);
  const std::vector<uint8_t> one_shot = hkdf_sha256(ikm, salt, info, 42u);

  expect_true(
      hex_from_array(prk) ==
          "077709362c2e32df0ddc3f0dc47bba63"
          "90b6c73bb50f9c3122ec844ad7c2b3e5",
      "HKDF-SHA256 RFC 5869 case 1 PRK should match");
  expect_true(
      hex_from_bytes(okm) ==
          "3cb25f25faacd57a90434f64d0362f2a"
          "2d2d0a90cf1a5a4c5db02d56ecc4c5bf"
          "34007208d5b887185865",
      "HKDF-SHA256 RFC 5869 case 1 OKM should match");
  expect_true(okm == one_shot, "HKDF one-shot should match extract plus expand");
}

void hkdf_rejects_oversized_output() {
  const std::vector<uint8_t> ikm = bytes_from_string("input key material");
  const std::vector<uint8_t> salt = bytes_from_string("salt");
  const std::vector<uint8_t> info = bytes_from_string("info");

  expect_true(hkdf_sha256(ikm, salt, info, 255u * 32u + 1u).empty(),
              "HKDF should reject output longer than 255 SHA-256 blocks");
}

}  // namespace

int main() {
  hmac_matches_rfc4231_case_1();
  hmac_matches_rfc4231_case_2();
  hkdf_matches_rfc5869_case_1();
  hkdf_rejects_oversized_output();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
