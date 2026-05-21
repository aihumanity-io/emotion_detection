#include "emotion_postprocessing.h"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

using emotion::native_sdk::PostprocessResult;
using emotion::native_sdk::copy_postprocess_to_c_result;
using emotion::native_sdk::postprocess_logits;

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

bool nearly_equal(float left, float right) {
  return std::fabs(left - right) < 0.0001f;
}

void softmax_scores_and_top_label_match() {
  const PostprocessResult result =
      postprocess_logits({1.0f, 2.0f, 0.0f}, {"sad", "happy", "neutral"});

  expect_true(result.ok, "postprocess should succeed");
  expect_true(result.top_label_index == 1u, "top index should match");
  expect_true(result.top_label == "happy", "top label should match");
  expect_true(nearly_equal(result.top_probability, 0.6652409f),
              "top probability should match softmax");
}

void label_count_mismatch_fails() {
  const PostprocessResult result = postprocess_logits({1.0f, 2.0f}, {"happy"});

  expect_true(!result.ok, "label mismatch should fail");
  expect_true(result.error == "label count mismatch",
              "label mismatch error should be reported");
}

void copies_into_c_result() {
  const PostprocessResult result =
      postprocess_logits({0.0f, 1.0f}, {"neutral", "happy"});
  emotion_class_score_t scores[2] = {};
  emotion_result_t c_result = {};
  c_result.scores = scores;
  c_result.scores_capacity = 2;

  const emotion_status_t status =
      copy_postprocess_to_c_result(result, &c_result);

  expect_true(status == EMOTION_STATUS_OK, "copy should succeed");
  expect_true(c_result.top_label_index == 1u, "C top index should match");
  expect_true(c_result.scores_count == 2u, "C score count should match");
  expect_true(c_result.scores[1].label_index == 1u,
              "C score index should match");
}

void c_result_buffer_too_small_fails() {
  const PostprocessResult result =
      postprocess_logits({0.0f, 1.0f}, {"neutral", "happy"});
  emotion_class_score_t scores[1] = {};
  emotion_result_t c_result = {};
  c_result.scores = scores;
  c_result.scores_capacity = 1;

  expect_true(copy_postprocess_to_c_result(result, &c_result) ==
                  EMOTION_STATUS_BUFFER_TOO_SMALL,
              "small result buffer should fail");
}

}  // namespace

int main() {
  softmax_scores_and_top_label_match();
  label_count_mismatch_fails();
  copies_into_c_result();
  c_result_buffer_too_small_fails();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
