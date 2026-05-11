#include "emotion_windows_secure_store.h"

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <fstream>
#include <limits>
#include <string>
#include <vector>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <direct.h>
#include <windows.h>
#include <wincrypt.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#endif

namespace emotion {
namespace native_sdk {
namespace {

bool empty(const char* value) {
  return value == nullptr || value[0] == '\0';
}

char path_separator() {
#if defined(_WIN32)
  return '\\';
#else
  return '/';
#endif
}

bool make_directory(const std::string& path) {
  if (path.empty()) {
    return false;
  }
#if defined(_WIN32)
  return _mkdir(path.c_str()) == 0 || errno == EEXIST;
#else
  return mkdir(path.c_str(), 0700) == 0 || errno == EEXIST;
#endif
}

std::string join_path(const std::string& left, const std::string& right) {
  if (left.empty()) {
    return right;
  }
  if (left[left.size() - 1u] == '/' || left[left.size() - 1u] == '\\') {
    return left + right;
  }
  return left + path_separator() + right;
}

std::string hex_encode(const char* value) {
  static const char* digits = "0123456789abcdef";
  std::string encoded;
  if (value == nullptr) {
    return encoded;
  }
  while (*value != '\0') {
    const unsigned char byte = static_cast<unsigned char>(*value);
    encoded.push_back(digits[byte >> 4]);
    encoded.push_back(digits[byte & 0x0f]);
    ++value;
  }
  return encoded;
}

std::vector<uint8_t> entropy_for(const char* namespace_id, const char* key) {
  const std::string material = std::string(namespace_id) + "\n" + key;
  return std::vector<uint8_t>(material.begin(), material.end());
}

emotion_status_t read_file(const std::string& path,
                           std::vector<uint8_t>* out_value) {
  std::ifstream input(path.c_str(), std::ios::binary | std::ios::ate);
  if (!input) {
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }
  const std::ifstream::pos_type end_position = input.tellg();
  if (end_position < 0) {
    return EMOTION_STATUS_INTERNAL;
  }
  const size_t value_len = static_cast<size_t>(end_position);
  out_value->assign(value_len, 0u);
  input.seekg(0, std::ios::beg);
  if (value_len > 0u) {
    input.read(reinterpret_cast<char*>(out_value->data()),
               static_cast<std::streamsize>(value_len));
    if (!input) {
      out_value->clear();
      return EMOTION_STATUS_INTERNAL;
    }
  }
  return EMOTION_STATUS_OK;
}

emotion_status_t write_file(const std::string& path,
                            const std::vector<uint8_t>& value) {
  std::ofstream output(path.c_str(), std::ios::binary | std::ios::trunc);
  if (!output) {
    return EMOTION_STATUS_INTERNAL;
  }
  if (!value.empty()) {
    output.write(reinterpret_cast<const char*>(value.data()),
                 static_cast<std::streamsize>(value.size()));
  }
  return output ? EMOTION_STATUS_OK : EMOTION_STATUS_INTERNAL;
}

emotion_status_t copy_plaintext(const std::vector<uint8_t>& plaintext,
                                uint8_t* out_value,
                                size_t* in_out_value_len) {
  if (in_out_value_len == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  if (out_value == nullptr || *in_out_value_len < plaintext.size()) {
    *in_out_value_len = plaintext.size();
    return EMOTION_STATUS_BUFFER_TOO_SMALL;
  }
  if (!plaintext.empty()) {
    std::copy(plaintext.begin(), plaintext.end(), out_value);
  }
  *in_out_value_len = plaintext.size();
  return EMOTION_STATUS_OK;
}

#if defined(_WIN32)

bool fits_dword(size_t value_len) {
  return value_len <= static_cast<size_t>(std::numeric_limits<DWORD>::max());
}

DATA_BLOB blob_from_vector(std::vector<uint8_t>* value) {
  DATA_BLOB blob;
  blob.cbData = static_cast<DWORD>(value->size());
  blob.pbData = value->empty() ? nullptr : value->data();
  return blob;
}

emotion_status_t protect_data(const uint8_t* value,
                              size_t value_len,
                              const std::vector<uint8_t>& entropy,
                              std::vector<uint8_t>* out_protected) {
  if ((value == nullptr && value_len > 0u) || !fits_dword(value_len) ||
      !fits_dword(entropy.size())) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  DATA_BLOB input;
  input.cbData = static_cast<DWORD>(value_len);
  input.pbData = value_len == 0u ? nullptr : const_cast<BYTE*>(value);
  DATA_BLOB optional_entropy;
  optional_entropy.cbData = static_cast<DWORD>(entropy.size());
  optional_entropy.pbData =
      entropy.empty() ? nullptr : const_cast<BYTE*>(entropy.data());
  DATA_BLOB output = {};

  if (!CryptProtectData(&input, L"Emotion Native SDK secret", &optional_entropy,
                        nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    return EMOTION_STATUS_CRYPTO_FAILED;
  }
  out_protected->assign(output.pbData, output.pbData + output.cbData);
  LocalFree(output.pbData);
  return EMOTION_STATUS_OK;
}

emotion_status_t unprotect_data(std::vector<uint8_t>* protected_value,
                                const std::vector<uint8_t>& entropy,
                                std::vector<uint8_t>* out_plaintext) {
  if (!fits_dword(protected_value->size()) || !fits_dword(entropy.size())) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  DATA_BLOB input = blob_from_vector(protected_value);
  DATA_BLOB optional_entropy;
  optional_entropy.cbData = static_cast<DWORD>(entropy.size());
  optional_entropy.pbData =
      entropy.empty() ? nullptr : const_cast<BYTE*>(entropy.data());
  DATA_BLOB output = {};

  if (!CryptUnprotectData(&input, nullptr, &optional_entropy, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    return EMOTION_STATUS_CRYPTO_FAILED;
  }
  out_plaintext->assign(output.pbData, output.pbData + output.cbData);
  LocalFree(output.pbData);
  return EMOTION_STATUS_OK;
}

#endif

}  // namespace

WindowsSecureStore::WindowsSecureStore(const std::string& root_dir)
    : root_dir_(root_dir), adapter_() {
  adapter_.abi_version = EMOTION_SDK_ABI_VERSION;
  adapter_.get = &WindowsSecureStore::get_callback;
  adapter_.set = &WindowsSecureStore::set_callback;
  adapter_.delete_value = &WindowsSecureStore::delete_callback;
  adapter_.user_data = this;
}

const emotion_secure_store_adapter_t* WindowsSecureStore::adapter() const {
  return &adapter_;
}

bool WindowsSecureStore::is_supported() const {
#if defined(_WIN32)
  return true;
#else
  return false;
#endif
}

std::string WindowsSecureStore::path_for(const char* namespace_id,
                                         const char* key) const {
  return join_path(join_path(root_dir_, hex_encode(namespace_id)),
                   hex_encode(key));
}

emotion_status_t WindowsSecureStore::get_callback(const char* namespace_id,
                                                  const char* key,
                                                  uint8_t* out_value,
                                                  size_t* in_out_value_len,
                                                  void* user_data) {
  if (empty(namespace_id) || empty(key) || user_data == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  const WindowsSecureStore* store =
      static_cast<const WindowsSecureStore*>(user_data);
  if (store->root_dir_.empty()) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
#if defined(_WIN32)
  std::vector<uint8_t> protected_value;
  emotion_status_t status =
      read_file(store->path_for(namespace_id, key), &protected_value);
  if (status != EMOTION_STATUS_OK) {
    return status;
  }
  std::vector<uint8_t> plaintext;
  status = unprotect_data(&protected_value, entropy_for(namespace_id, key),
                          &plaintext);
  if (status != EMOTION_STATUS_OK) {
    return status;
  }
  return copy_plaintext(plaintext, out_value, in_out_value_len);
#else
  (void)out_value;
  (void)in_out_value_len;
  return EMOTION_STATUS_UNSUPPORTED;
#endif
}

emotion_status_t WindowsSecureStore::set_callback(const char* namespace_id,
                                                  const char* key,
                                                  const uint8_t* value,
                                                  size_t value_len,
                                                  void* user_data) {
  if (empty(namespace_id) || empty(key) || user_data == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  WindowsSecureStore* store = static_cast<WindowsSecureStore*>(user_data);
  if (store->root_dir_.empty()) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
#if defined(_WIN32)
  const std::string namespace_dir =
      join_path(store->root_dir_, hex_encode(namespace_id));
  if (!make_directory(store->root_dir_) || !make_directory(namespace_dir)) {
    return EMOTION_STATUS_INTERNAL;
  }
  std::vector<uint8_t> protected_value;
  const emotion_status_t status =
      protect_data(value, value_len, entropy_for(namespace_id, key),
                   &protected_value);
  if (status != EMOTION_STATUS_OK) {
    return status;
  }
  return write_file(store->path_for(namespace_id, key), protected_value);
#else
  (void)value;
  (void)value_len;
  return EMOTION_STATUS_UNSUPPORTED;
#endif
}

emotion_status_t WindowsSecureStore::delete_callback(const char* namespace_id,
                                                     const char* key,
                                                     void* user_data) {
  if (empty(namespace_id) || empty(key) || user_data == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  const WindowsSecureStore* store =
      static_cast<const WindowsSecureStore*>(user_data);
  if (store->root_dir_.empty()) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
#if defined(_WIN32)
  return std::remove(store->path_for(namespace_id, key).c_str()) == 0
             ? EMOTION_STATUS_OK
             : EMOTION_STATUS_MODEL_NOT_FOUND;
#else
  return EMOTION_STATUS_UNSUPPORTED;
#endif
}

}  // namespace native_sdk
}  // namespace emotion
