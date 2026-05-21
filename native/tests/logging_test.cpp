#include "emotion_logging.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

using emotion::native_sdk::NativeLogger;
using emotion::native_sdk::kLogStageDecrypt;
using emotion::native_sdk::kLogStageLoad;
using emotion::native_sdk::kLogStageProvisioning;
using emotion::native_sdk::sanitize_log_message;

struct LogEvent {
  emotion_log_level_t level;
  std::string stage;
  std::string model_id;
  std::string message;
};

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

void collect_log(emotion_log_level_t level,
                 const char* stage,
                 const char* model_id,
                 const char* message,
                 void* user_data) {
  std::vector<LogEvent>* events = static_cast<std::vector<LogEvent>*>(user_data);
  events->push_back({level, stage, model_id, message});
}

void emits_stage_model_and_message() {
  std::vector<LogEvent> events;
  const NativeLogger logger(collect_log, &events, true);

  logger.error(kLogStageDecrypt, "aih_fer2025", "authentication tag mismatch");

  expect_true(events.size() == 1u, "one log should be emitted");
  expect_true(events[0].level == EMOTION_LOG_ERROR, "level should be error");
  expect_true(events[0].stage == kLogStageDecrypt, "stage should be preserved");
  expect_true(events[0].model_id == "aih_fer2025", "model id should be preserved");
  expect_true(events[0].message == "authentication tag mismatch",
              "message should be preserved");
}

void debug_logs_require_debug_flag() {
  std::vector<LogEvent> events;
  const NativeLogger disabled(collect_log, &events, false);
  const NativeLogger enabled(collect_log, &events, true);

  disabled.debug(kLogStageProvisioning, "aih_fer2025", "request started");
  enabled.debug(kLogStageProvisioning, "aih_fer2025", "request started");

  expect_true(events.size() == 1u, "debug disabled should suppress event");
  expect_true(events[0].level == EMOTION_LOG_DEBUG,
              "debug enabled should emit debug event");
}

void missing_callback_is_noop() {
  const NativeLogger logger(nullptr, nullptr, true);

  logger.error(kLogStageLoad, "aih_fer2025", "runtime failed");
  expect_true(true, "missing callback should not crash");
}

void sensitive_material_is_redacted() {
  expect_true(sanitize_log_message("key shard decode failed") == "[redacted]",
              "key shard messages should be redacted");
  expect_true(sanitize_log_message("CEK unwrap failed") == "[redacted]",
              "CEK messages should be redacted");
  expect_true(sanitize_log_message("manifest hash mismatch") ==
                  "manifest hash mismatch",
              "safe message should remain visible");
}

void config_constructor_reads_callback_and_flag() {
  std::vector<LogEvent> events;
  emotion_config_t config = {};
  config.abi_version = EMOTION_SDK_ABI_VERSION;
  config.log_callback = collect_log;
  config.log_user_data = &events;
  config.enable_debug_logging = 1u;

  const NativeLogger logger(&config);
  logger.debug(kLogStageProvisioning, "aih_fer2025", "started");

  expect_true(events.size() == 1u, "config callback should receive log event");
}

}  // namespace

int main() {
  emits_stage_model_and_message();
  debug_logs_require_debug_flag();
  missing_callback_is_noop();
  sensitive_material_is_redacted();
  config_constructor_reads_callback_and_flag();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
