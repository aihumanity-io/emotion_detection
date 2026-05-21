#ifndef EMOTION_WINDOWS_SECURE_STORE_H_
#define EMOTION_WINDOWS_SECURE_STORE_H_

#include <string>

#include "emotion_sdk.h"

namespace emotion {
namespace native_sdk {

class WindowsSecureStore {
 public:
  explicit WindowsSecureStore(const std::string& root_dir);

  const emotion_secure_store_adapter_t* adapter() const;
  bool is_supported() const;

 private:
  static emotion_status_t get_callback(const char* namespace_id,
                                       const char* key,
                                       uint8_t* out_value,
                                       size_t* in_out_value_len,
                                       void* user_data);
  static emotion_status_t set_callback(const char* namespace_id,
                                       const char* key,
                                       const uint8_t* value,
                                       size_t value_len,
                                       void* user_data);
  static emotion_status_t delete_callback(const char* namespace_id,
                                          const char* key,
                                          void* user_data);

  std::string path_for(const char* namespace_id, const char* key) const;

  std::string root_dir_;
  emotion_secure_store_adapter_t adapter_;
};

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_WINDOWS_SECURE_STORE_H_
