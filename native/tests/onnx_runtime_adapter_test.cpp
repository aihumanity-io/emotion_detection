#include "emotion_onnx_runtime_adapter.h"

#include <cstdlib>
#include <iostream>

namespace {

using emotion::native_sdk::OnnxRuntimeSession;
using emotion::native_sdk::onnx_runtime_available;

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

void adapter_fails_closed_until_onnx_runtime_is_linked() {
  OnnxRuntimeSession session;

#if EMOTION_ENABLE_ONNX_RUNTIME
  expect_true(onnx_runtime_available(), "ONNX Runtime should be available");
  expect_true(!session.load({}).ok, "empty model should fail");
  expect_true(session.load({}).error == "missing model bytes",
              "empty model error should be reported");
#else
  expect_true(!onnx_runtime_available(), "ONNX Runtime should be unavailable");
  expect_true(!session.load({1u, 2u, 3u}).ok,
              "load should fail without ONNX Runtime");
  expect_true(session.load({1u}).error == "onnx runtime adapter not linked",
              "unsupported error should be reported");
#endif
}

}  // namespace

int main() {
  adapter_fails_closed_until_onnx_runtime_is_linked();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
