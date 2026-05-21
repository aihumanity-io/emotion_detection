#ifndef EMOTION_LOGGING_H_
#define EMOTION_LOGGING_H_

#include <string>

#include "emotion_sdk.h"

namespace emotion {
namespace native_sdk {

extern const char kLogStageProvisioning[];
extern const char kLogStageManifest[];
extern const char kLogStageKeyMaterial[];
extern const char kLogStageDecrypt[];
extern const char kLogStageLoad[];

class NativeLogger {
 public:
  NativeLogger(emotion_log_callback_t callback,
               void* user_data,
               bool debug_enabled);
  explicit NativeLogger(const emotion_config_t* config);

  void debug(const std::string& stage,
             const std::string& model_id,
             const std::string& message) const;
  void info(const std::string& stage,
            const std::string& model_id,
            const std::string& message) const;
  void warn(const std::string& stage,
            const std::string& model_id,
            const std::string& message) const;
  void error(const std::string& stage,
             const std::string& model_id,
             const std::string& message) const;

 private:
  void emit(emotion_log_level_t level,
            const std::string& stage,
            const std::string& model_id,
            const std::string& message) const;

  emotion_log_callback_t callback_;
  void* user_data_;
  bool debug_enabled_;
};

std::string sanitize_log_message(const std::string& message);

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_LOGGING_H_
