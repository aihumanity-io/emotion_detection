#include "emotion_logging.h"

#include <algorithm>

namespace emotion {
namespace native_sdk {
namespace {

bool contains_sensitive_token(const std::string& message) {
  std::string lower = message;
  std::transform(lower.begin(), lower.end(), lower.begin(),
                 [](unsigned char value) {
                   return static_cast<char>(std::tolower(value));
                 });
  return lower.find("key") != std::string::npos ||
         lower.find("secret") != std::string::npos ||
         lower.find("shard") != std::string::npos ||
         lower.find("cek") != std::string::npos ||
         lower.find("user_code") != std::string::npos ||
         lower.find("user code") != std::string::npos;
}

}  // namespace

const char kLogStageProvisioning[] = "provisioning";
const char kLogStageManifest[] = "manifest";
const char kLogStageKeyMaterial[] = "key_material";
const char kLogStageDecrypt[] = "decrypt";
const char kLogStageLoad[] = "load";

NativeLogger::NativeLogger(emotion_log_callback_t callback,
                           void* user_data,
                           bool debug_enabled)
    : callback_(callback), user_data_(user_data), debug_enabled_(debug_enabled) {
}

NativeLogger::NativeLogger(const emotion_config_t* config)
    : callback_(config == nullptr ? nullptr : config->log_callback),
      user_data_(config == nullptr ? nullptr : config->log_user_data),
      debug_enabled_(config != nullptr && config->enable_debug_logging != 0u) {}

void NativeLogger::debug(const std::string& stage,
                         const std::string& model_id,
                         const std::string& message) const {
  emit(EMOTION_LOG_DEBUG, stage, model_id, message);
}

void NativeLogger::info(const std::string& stage,
                        const std::string& model_id,
                        const std::string& message) const {
  emit(EMOTION_LOG_INFO, stage, model_id, message);
}

void NativeLogger::warn(const std::string& stage,
                        const std::string& model_id,
                        const std::string& message) const {
  emit(EMOTION_LOG_WARN, stage, model_id, message);
}

void NativeLogger::error(const std::string& stage,
                         const std::string& model_id,
                         const std::string& message) const {
  emit(EMOTION_LOG_ERROR, stage, model_id, message);
}

void NativeLogger::emit(emotion_log_level_t level,
                        const std::string& stage,
                        const std::string& model_id,
                        const std::string& message) const {
  if (callback_ == nullptr) {
    return;
  }
  if (level == EMOTION_LOG_DEBUG && !debug_enabled_) {
    return;
  }
  const std::string safe_message = sanitize_log_message(message);
  callback_(level, stage.c_str(), model_id.c_str(), safe_message.c_str(),
            user_data_);
}

std::string sanitize_log_message(const std::string& message) {
  if (contains_sensitive_token(message)) {
    return "[redacted]";
  }
  return message;
}

}  // namespace native_sdk
}  // namespace emotion
