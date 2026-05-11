#include "emotion_linux_secret_store.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <string>
#include <vector>

#if defined(__linux__) && EMOTION_ENABLE_LIBSECRET
#include <libsecret/secret.h>
#endif

namespace emotion {
namespace native_sdk {
namespace {

bool empty(const char* value) {
  return value == nullptr || value[0] == '\0';
}

char hex_digit(uint8_t value) {
  return value < 10u ? static_cast<char>('0' + value)
                     : static_cast<char>('a' + (value - 10u));
}

std::string hex_encode(const uint8_t* value, size_t value_len) {
  std::string encoded;
  encoded.reserve(value_len * 2u);
  for (size_t i = 0; i < value_len; ++i) {
    encoded.push_back(hex_digit(value[i] >> 4));
    encoded.push_back(hex_digit(value[i] & 0x0fu));
  }
  return encoded;
}

bool hex_value(char value, uint8_t* out_value) {
  if (value >= '0' && value <= '9') {
    *out_value = static_cast<uint8_t>(value - '0');
    return true;
  }
  if (value >= 'a' && value <= 'f') {
    *out_value = static_cast<uint8_t>(10 + value - 'a');
    return true;
  }
  if (value >= 'A' && value <= 'F') {
    *out_value = static_cast<uint8_t>(10 + value - 'A');
    return true;
  }
  return false;
}

bool hex_decode(const char* value, std::vector<uint8_t>* out_value) {
  if (value == nullptr) {
    return false;
  }
  const std::string encoded(value);
  if (encoded.size() % 2u != 0u) {
    return false;
  }
  out_value->clear();
  out_value->reserve(encoded.size() / 2u);
  for (size_t i = 0; i < encoded.size(); i += 2u) {
    uint8_t high = 0u;
    uint8_t low = 0u;
    if (!hex_value(encoded[i], &high) || !hex_value(encoded[i + 1u], &low)) {
      out_value->clear();
      return false;
    }
    out_value->push_back(static_cast<uint8_t>((high << 4) | low));
  }
  return true;
}

emotion_status_t copy_value(const std::vector<uint8_t>& value,
                            uint8_t* out_value,
                            size_t* in_out_value_len) {
  if (in_out_value_len == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  if (out_value == nullptr || *in_out_value_len < value.size()) {
    *in_out_value_len = value.size();
    return EMOTION_STATUS_BUFFER_TOO_SMALL;
  }
  if (!value.empty()) {
    std::copy(value.begin(), value.end(), out_value);
  }
  *in_out_value_len = value.size();
  return EMOTION_STATUS_OK;
}

#if defined(__linux__) && EMOTION_ENABLE_LIBSECRET

const SecretSchema emotion_secret_schema = {
    "com.tartalabs.EmotionNativeSDK.Secret",
    SECRET_SCHEMA_NONE,
    {
        {"namespace", SECRET_SCHEMA_ATTRIBUTE_STRING},
        {"key", SECRET_SCHEMA_ATTRIBUTE_STRING},
        {nullptr, static_cast<SecretSchemaAttributeType>(0)},
    }};

emotion_status_t status_from_error(GError* error) {
  if (error != nullptr) {
    g_error_free(error);
  }
  return EMOTION_STATUS_RUNTIME_FAILED;
}

#endif

}  // namespace

LinuxSecretStore::LinuxSecretStore() : adapter_() {
  adapter_.abi_version = EMOTION_SDK_ABI_VERSION;
  adapter_.get = &LinuxSecretStore::get_callback;
  adapter_.set = &LinuxSecretStore::set_callback;
  adapter_.delete_value = &LinuxSecretStore::delete_callback;
  adapter_.user_data = this;
}

const emotion_secure_store_adapter_t* LinuxSecretStore::adapter() const {
  return &adapter_;
}

bool LinuxSecretStore::is_supported() const {
#if defined(__linux__) && EMOTION_ENABLE_LIBSECRET
  return true;
#else
  return false;
#endif
}

emotion_status_t LinuxSecretStore::get_callback(const char* namespace_id,
                                                const char* key,
                                                uint8_t* out_value,
                                                size_t* in_out_value_len,
                                                void* user_data) {
  if (empty(namespace_id) || empty(key) || user_data == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
#if defined(__linux__) && EMOTION_ENABLE_LIBSECRET
  GError* error = nullptr;
  char* stored_secret = secret_password_lookup_sync(
      &emotion_secret_schema, nullptr, &error, "namespace", namespace_id, "key",
      key, nullptr);
  if (error != nullptr) {
    return status_from_error(error);
  }
  if (stored_secret == nullptr) {
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }

  std::vector<uint8_t> decoded;
  const bool decoded_ok = hex_decode(stored_secret, &decoded);
  secret_password_free(stored_secret);
  if (!decoded_ok) {
    return EMOTION_STATUS_CRYPTO_FAILED;
  }
  return copy_value(decoded, out_value, in_out_value_len);
#else
  (void)out_value;
  (void)in_out_value_len;
  return EMOTION_STATUS_UNSUPPORTED;
#endif
}

emotion_status_t LinuxSecretStore::set_callback(const char* namespace_id,
                                                const char* key,
                                                const uint8_t* value,
                                                size_t value_len,
                                                void* user_data) {
  if (empty(namespace_id) || empty(key) || user_data == nullptr ||
      (value == nullptr && value_len > 0u)) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
#if defined(__linux__) && EMOTION_ENABLE_LIBSECRET
  const std::string encoded = hex_encode(value, value_len);
  const std::string label =
      std::string("Emotion Native SDK: ") + namespace_id + "/" + key;
  GError* error = nullptr;
  const gboolean ok = secret_password_store_sync(
      &emotion_secret_schema, SECRET_COLLECTION_DEFAULT, label.c_str(),
      encoded.c_str(), nullptr, &error, "namespace", namespace_id, "key", key,
      nullptr);
  if (!ok) {
    return status_from_error(error);
  }
  return EMOTION_STATUS_OK;
#else
  (void)value;
  (void)value_len;
  return EMOTION_STATUS_UNSUPPORTED;
#endif
}

emotion_status_t LinuxSecretStore::delete_callback(const char* namespace_id,
                                                   const char* key,
                                                   void* user_data) {
  if (empty(namespace_id) || empty(key) || user_data == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
#if defined(__linux__) && EMOTION_ENABLE_LIBSECRET
  GError* error = nullptr;
  const gboolean deleted = secret_password_clear_sync(
      &emotion_secret_schema, nullptr, &error, "namespace", namespace_id, "key",
      key, nullptr);
  if (error != nullptr) {
    return status_from_error(error);
  }
  return deleted ? EMOTION_STATUS_OK : EMOTION_STATUS_MODEL_NOT_FOUND;
#else
  return EMOTION_STATUS_UNSUPPORTED;
#endif
}

}  // namespace native_sdk
}  // namespace emotion
