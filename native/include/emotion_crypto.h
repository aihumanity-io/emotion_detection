#ifndef EMOTION_CRYPTO_H_
#define EMOTION_CRYPTO_H_

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace emotion {
namespace native_sdk {

std::array<uint8_t, 32> sha256(const uint8_t* data, size_t data_len);
std::array<uint8_t, 32> sha256(const std::vector<uint8_t>& data);

std::string sha256_hex(const uint8_t* data, size_t data_len);
std::string sha256_hex(const std::vector<uint8_t>& data);

bool verify_sha256_hex(const uint8_t* data,
                       size_t data_len,
                       const std::string& expected_hex);
bool verify_sha256_hex(const std::vector<uint8_t>& data,
                       const std::string& expected_hex);

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_CRYPTO_H_
