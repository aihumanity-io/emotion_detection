#include "emotion_secure_store.h"

namespace emotion {
namespace native_sdk {

SecureStore::SecureStore(const emotion_secure_store_adapter_t* adapter)
    : adapter_(adapter) {}

bool SecureStore::available() const {
  return adapter_ != nullptr && adapter_->abi_version == EMOTION_SDK_ABI_VERSION &&
         adapter_->get != nullptr && adapter_->set != nullptr &&
         adapter_->delete_value != nullptr;
}

emotion_status_t SecureStore::set(const std::string& namespace_id,
                                  const std::string& key,
                                  const std::vector<uint8_t>& value) const {
  if (!available()) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  return adapter_->set(namespace_id.c_str(), key.c_str(), value.data(),
                       value.size(), adapter_->user_data);
}

SecureStoreResult SecureStore::get(const std::string& namespace_id,
                                   const std::string& key) const {
  SecureStoreResult result;
  if (!available()) {
    result.status = EMOTION_STATUS_INVALID_ARGUMENT;
    return result;
  }

  size_t value_len = 0;
  emotion_status_t status =
      adapter_->get(namespace_id.c_str(), key.c_str(), nullptr, &value_len,
                    adapter_->user_data);
  if (status != EMOTION_STATUS_BUFFER_TOO_SMALL || value_len == 0u) {
    result.status = status;
    return result;
  }

  result.value.resize(value_len);
  status = adapter_->get(namespace_id.c_str(), key.c_str(), result.value.data(),
                         &value_len, adapter_->user_data);
  if (status != EMOTION_STATUS_OK) {
    result.value.clear();
    result.status = status;
    return result;
  }

  result.value.resize(value_len);
  result.ok = true;
  result.status = EMOTION_STATUS_OK;
  return result;
}

emotion_status_t SecureStore::delete_value(const std::string& namespace_id,
                                           const std::string& key) const {
  if (!available()) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  return adapter_->delete_value(namespace_id.c_str(), key.c_str(),
                                adapter_->user_data);
}

}  // namespace native_sdk
}  // namespace emotion
