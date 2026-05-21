#include "emotion_file_secure_store.h"

#include <cerrno>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <vector>

#if defined(_WIN32)
#include <direct.h>
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

emotion_status_t read_file(const std::string& path,
                           uint8_t* out_value,
                           size_t* in_out_value_len) {
  if (in_out_value_len == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }

  std::ifstream input(path.c_str(), std::ios::binary | std::ios::ate);
  if (!input) {
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }
  const std::ifstream::pos_type end_position = input.tellg();
  if (end_position < 0) {
    return EMOTION_STATUS_INTERNAL;
  }
  const size_t value_len = static_cast<size_t>(end_position);
  if (out_value == nullptr || *in_out_value_len < value_len) {
    *in_out_value_len = value_len;
    return EMOTION_STATUS_BUFFER_TOO_SMALL;
  }

  input.seekg(0, std::ios::beg);
  if (value_len > 0u) {
    input.read(reinterpret_cast<char*>(out_value),
               static_cast<std::streamsize>(value_len));
    if (!input) {
      return EMOTION_STATUS_INTERNAL;
    }
  }
  *in_out_value_len = value_len;
  return EMOTION_STATUS_OK;
}

emotion_status_t write_file(const std::string& path,
                            const uint8_t* value,
                            size_t value_len) {
  if (value == nullptr && value_len > 0u) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  std::ofstream output(path.c_str(), std::ios::binary | std::ios::trunc);
  if (!output) {
    return EMOTION_STATUS_INTERNAL;
  }
  if (value_len > 0u) {
    output.write(reinterpret_cast<const char*>(value),
                 static_cast<std::streamsize>(value_len));
  }
  return output ? EMOTION_STATUS_OK : EMOTION_STATUS_INTERNAL;
}

}  // namespace

FileSecureStore::FileSecureStore(const std::string& root_dir)
    : root_dir_(root_dir), adapter_() {
  adapter_.abi_version = EMOTION_SDK_ABI_VERSION;
  adapter_.get = &FileSecureStore::get_callback;
  adapter_.set = &FileSecureStore::set_callback;
  adapter_.delete_value = &FileSecureStore::delete_callback;
  adapter_.user_data = this;
}

const emotion_secure_store_adapter_t* FileSecureStore::adapter() const {
  return &adapter_;
}

bool FileSecureStore::is_development_fallback() const {
  return true;
}

std::string FileSecureStore::path_for(const char* namespace_id,
                                      const char* key) const {
  return join_path(join_path(root_dir_, hex_encode(namespace_id)),
                   hex_encode(key));
}

emotion_status_t FileSecureStore::get_callback(const char* namespace_id,
                                               const char* key,
                                               uint8_t* out_value,
                                               size_t* in_out_value_len,
                                               void* user_data) {
  if (empty(namespace_id) || empty(key) || user_data == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  const FileSecureStore* store = static_cast<const FileSecureStore*>(user_data);
  if (store->root_dir_.empty()) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  return read_file(store->path_for(namespace_id, key), out_value,
                   in_out_value_len);
}

emotion_status_t FileSecureStore::set_callback(const char* namespace_id,
                                               const char* key,
                                               const uint8_t* value,
                                               size_t value_len,
                                               void* user_data) {
  if (empty(namespace_id) || empty(key) || user_data == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  FileSecureStore* store = static_cast<FileSecureStore*>(user_data);
  if (store->root_dir_.empty()) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  const std::string namespace_dir =
      join_path(store->root_dir_, hex_encode(namespace_id));
  if (!make_directory(store->root_dir_) || !make_directory(namespace_dir)) {
    return EMOTION_STATUS_INTERNAL;
  }
  return write_file(store->path_for(namespace_id, key), value, value_len);
}

emotion_status_t FileSecureStore::delete_callback(const char* namespace_id,
                                                  const char* key,
                                                  void* user_data) {
  if (empty(namespace_id) || empty(key) || user_data == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  const FileSecureStore* store = static_cast<const FileSecureStore*>(user_data);
  if (store->root_dir_.empty()) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  return std::remove(store->path_for(namespace_id, key).c_str()) == 0
             ? EMOTION_STATUS_OK
             : EMOTION_STATUS_MODEL_NOT_FOUND;
}

}  // namespace native_sdk
}  // namespace emotion
