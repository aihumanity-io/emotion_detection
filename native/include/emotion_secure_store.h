#ifndef EMOTION_SECURE_STORE_H_
#define EMOTION_SECURE_STORE_H_

#include <string>
#include <vector>

#include "emotion_sdk.h"

namespace emotion {
namespace native_sdk {

struct SecureStoreResult {
  bool ok = false;
  emotion_status_t status = EMOTION_STATUS_INTERNAL;
  std::vector<uint8_t> value;
};

class SecureStore {
 public:
  explicit SecureStore(const emotion_secure_store_adapter_t* adapter);

  bool available() const;

  emotion_status_t set(const std::string& namespace_id,
                       const std::string& key,
                       const std::vector<uint8_t>& value) const;
  SecureStoreResult get(const std::string& namespace_id,
                        const std::string& key) const;
  emotion_status_t delete_value(const std::string& namespace_id,
                                const std::string& key) const;

 private:
  const emotion_secure_store_adapter_t* adapter_;
};

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_SECURE_STORE_H_
