#include "emotion_runtime_session.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

using emotion::native_sdk::FakeRuntimeSession;
using emotion::native_sdk::FloatTensor;
using emotion::native_sdk::PostprocessResult;
using emotion::native_sdk::predict_and_postprocess;

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

FloatTensor input_tensor() {
  FloatTensor tensor;
  tensor.shape = {1, 1, 1, 3};
  tensor.values = {0.1f, 0.2f, 0.3f};
  return tensor;
}

void load_warm_predict_unload_lifecycle() {
  FakeRuntimeSession session({0.0f, 2.0f});

  expect_true(session.load({1u, 2u, 3u}).ok, "load should succeed");
  expect_true(session.loaded(), "runtime should be loaded");
  expect_true(session.warmup().ok, "warmup should succeed");
  expect_true(session.warmed(), "runtime should be warmed");

  const PostprocessResult result =
      predict_and_postprocess(&session, input_tensor(), {"neutral", "happy"});

  expect_true(result.ok, "predict and postprocess should succeed");
  expect_true(result.top_label == "happy", "top label should come from logits");
  expect_true(session.predict_count() == 1u, "predict count should increment");

  session.unload();
  expect_true(!session.loaded(), "runtime should unload");
}

void predict_before_warmup_fails() {
  FakeRuntimeSession session({1.0f});
  session.load({1u});

  const PostprocessResult result =
      predict_and_postprocess(&session, input_tensor(), {"neutral"});

  expect_true(!result.ok, "predict before warmup should fail");
  expect_true(result.error == "runtime not warmed",
              "runtime not warmed error should be reported");
}

void missing_model_bytes_fail_load() {
  FakeRuntimeSession session({1.0f});

  expect_true(!session.load({}).ok, "empty model bytes should fail load");
}

}  // namespace

int main() {
  load_warm_predict_unload_lifecycle();
  predict_before_warmup_fails();
  missing_model_bytes_fail_load();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
