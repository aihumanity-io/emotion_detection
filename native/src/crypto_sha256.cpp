#include "emotion_crypto.h"

#include <iomanip>
#include <sstream>

namespace emotion {
namespace native_sdk {
namespace {

const uint32_t kSha256InitialState[8] = {
    0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
    0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};

const uint32_t kSha256RoundConstants[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
    0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
    0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
    0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
    0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
    0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};

uint32_t rotate_right(uint32_t value, uint32_t bits) {
  return (value >> bits) | (value << (32u - bits));
}

uint32_t choose(uint32_t x, uint32_t y, uint32_t z) {
  return (x & y) ^ (~x & z);
}

uint32_t majority(uint32_t x, uint32_t y, uint32_t z) {
  return (x & y) ^ (x & z) ^ (y & z);
}

uint32_t big_sigma0(uint32_t value) {
  return rotate_right(value, 2) ^ rotate_right(value, 13) ^
         rotate_right(value, 22);
}

uint32_t big_sigma1(uint32_t value) {
  return rotate_right(value, 6) ^ rotate_right(value, 11) ^
         rotate_right(value, 25);
}

uint32_t small_sigma0(uint32_t value) {
  return rotate_right(value, 7) ^ rotate_right(value, 18) ^ (value >> 3);
}

uint32_t small_sigma1(uint32_t value) {
  return rotate_right(value, 17) ^ rotate_right(value, 19) ^ (value >> 10);
}

uint32_t read_big_endian_u32(const uint8_t* data) {
  return (static_cast<uint32_t>(data[0]) << 24) |
         (static_cast<uint32_t>(data[1]) << 16) |
         (static_cast<uint32_t>(data[2]) << 8) |
         static_cast<uint32_t>(data[3]);
}

void write_big_endian_u32(uint32_t value, uint8_t* output) {
  output[0] = static_cast<uint8_t>(value >> 24);
  output[1] = static_cast<uint8_t>(value >> 16);
  output[2] = static_cast<uint8_t>(value >> 8);
  output[3] = static_cast<uint8_t>(value);
}

void write_big_endian_u64(uint64_t value, std::vector<uint8_t>* output) {
  for (int shift = 56; shift >= 0; shift -= 8) {
    output->push_back(static_cast<uint8_t>(value >> shift));
  }
}

bool is_lower_hex_sha256(const std::string& value) {
  if (value.size() != 64u) {
    return false;
  }
  for (char character : value) {
    const bool is_digit = character >= '0' && character <= '9';
    const bool is_lower_hex = character >= 'a' && character <= 'f';
    if (!is_digit && !is_lower_hex) {
      return false;
    }
  }
  return true;
}

}  // namespace

std::array<uint8_t, 32> sha256(const uint8_t* data, size_t data_len) {
  uint32_t state[8];
  for (size_t i = 0; i < 8u; ++i) {
    state[i] = kSha256InitialState[i];
  }

  std::vector<uint8_t> padded;
  if (data_len > 0u) {
    padded.assign(data, data + data_len);
  }
  const uint64_t bit_len = static_cast<uint64_t>(data_len) * 8u;
  padded.push_back(0x80u);
  while ((padded.size() % 64u) != 56u) {
    padded.push_back(0u);
  }
  write_big_endian_u64(bit_len, &padded);

  for (size_t offset = 0; offset < padded.size(); offset += 64u) {
    uint32_t words[64] = {0};
    for (size_t i = 0; i < 16u; ++i) {
      words[i] = read_big_endian_u32(&padded[offset + i * 4u]);
    }
    for (size_t i = 16u; i < 64u; ++i) {
      words[i] = small_sigma1(words[i - 2u]) + words[i - 7u] +
                 small_sigma0(words[i - 15u]) + words[i - 16u];
    }

    uint32_t a = state[0];
    uint32_t b = state[1];
    uint32_t c = state[2];
    uint32_t d = state[3];
    uint32_t e = state[4];
    uint32_t f = state[5];
    uint32_t g = state[6];
    uint32_t h = state[7];

    for (size_t i = 0; i < 64u; ++i) {
      const uint32_t temp1 =
          h + big_sigma1(e) + choose(e, f, g) + kSha256RoundConstants[i] +
          words[i];
      const uint32_t temp2 = big_sigma0(a) + majority(a, b, c);
      h = g;
      g = f;
      f = e;
      e = d + temp1;
      d = c;
      c = b;
      b = a;
      a = temp1 + temp2;
    }

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;
  }

  std::array<uint8_t, 32> digest = {};
  for (size_t i = 0; i < 8u; ++i) {
    write_big_endian_u32(state[i], &digest[i * 4u]);
  }
  return digest;
}

std::array<uint8_t, 32> sha256(const std::vector<uint8_t>& data) {
  return sha256(data.data(), data.size());
}

std::string sha256_hex(const uint8_t* data, size_t data_len) {
  const std::array<uint8_t, 32> digest = sha256(data, data_len);
  std::ostringstream output;
  output << std::hex << std::setfill('0');
  for (uint8_t byte : digest) {
    output << std::setw(2) << static_cast<int>(byte);
  }
  return output.str();
}

std::string sha256_hex(const std::vector<uint8_t>& data) {
  return sha256_hex(data.data(), data.size());
}

bool verify_sha256_hex(const uint8_t* data,
                       size_t data_len,
                       const std::string& expected_hex) {
  if (!is_lower_hex_sha256(expected_hex)) {
    return false;
  }
  return sha256_hex(data, data_len) == expected_hex;
}

bool verify_sha256_hex(const std::vector<uint8_t>& data,
                       const std::string& expected_hex) {
  return verify_sha256_hex(data.data(), data.size(), expected_hex);
}

}  // namespace native_sdk
}  // namespace emotion
