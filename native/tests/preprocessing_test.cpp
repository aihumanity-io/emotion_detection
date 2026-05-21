#include "emotion_preprocessing.h"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <vector>

namespace {

using emotion::native_sdk::PreprocessOptions;
using emotion::native_sdk::PreprocessResult;
using emotion::native_sdk::TensorLayout;
using emotion::native_sdk::preprocess_image;

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

emotion_image_t rgb_image(std::vector<uint8_t>* pixels) {
  *pixels = {
      255, 0, 0,    0, 255, 0,
      0,   0, 255,  255, 255, 255,
  };
  emotion_image_t image = {};
  image.abi_version = EMOTION_SDK_ABI_VERSION;
  image.pixel_format = EMOTION_PIXEL_FORMAT_RGB_U8;
  image.width = 2;
  image.height = 2;
  image.orientation = EMOTION_IMAGE_ORIENTATION_UP;
  image.plane_count = 1;
  image.planes[0].data = pixels->data();
  image.planes[0].data_len = pixels->size();
  image.planes[0].row_stride = 6;
  image.planes[0].pixel_stride = 3;
  return image;
}

void rgb_to_nhwc_tensor_matches_golden() {
  std::vector<uint8_t> pixels;
  const emotion_image_t image = rgb_image(&pixels);
  PreprocessOptions options;
  options.target_width = 2;
  options.target_height = 2;

  const PreprocessResult result = preprocess_image(image, nullptr, options);

  expect_true(result.ok, "RGB preprocessing should succeed");
  expect_true(result.tensor.shape == std::vector<int64_t>({1, 2, 2, 3}),
              "NHWC shape should match");
  const std::vector<float> expected = {
      1, 0, 0, 0, 1, 0,
      0, 0, 1, 1, 1, 1,
  };
  expect_true(result.tensor.values.size() == expected.size(),
              "tensor size should match");
  for (size_t i = 0; i < expected.size(); ++i) {
    expect_true(nearly_equal(result.tensor.values[i], expected[i]),
                "NHWC tensor value should match golden");
  }
}

void bgra_to_nchw_tensor_reorders_channels() {
  std::vector<uint8_t> pixels = {
      10, 20, 30, 255,
      40, 50, 60, 255,
  };
  emotion_image_t image = {};
  image.abi_version = EMOTION_SDK_ABI_VERSION;
  image.pixel_format = EMOTION_PIXEL_FORMAT_BGRA_U8;
  image.width = 2;
  image.height = 1;
  image.orientation = EMOTION_IMAGE_ORIENTATION_UP;
  image.plane_count = 1;
  image.planes[0].data = pixels.data();
  image.planes[0].data_len = pixels.size();
  image.planes[0].row_stride = 8;
  image.planes[0].pixel_stride = 4;
  PreprocessOptions options;
  options.target_width = 2;
  options.target_height = 1;
  options.layout = TensorLayout::kNchw;
  options.scale = 1.0f;

  const PreprocessResult result = preprocess_image(image, nullptr, options);

  expect_true(result.ok, "BGRA preprocessing should succeed");
  expect_true(result.tensor.shape == std::vector<int64_t>({1, 3, 1, 2}),
              "NCHW shape should match");
  expect_true(result.tensor.values == std::vector<float>({30, 60, 20, 50, 10, 40}),
              "BGRA should become RGB NCHW");
}

void face_crop_uses_requested_region() {
  std::vector<uint8_t> pixels;
  const emotion_image_t image = rgb_image(&pixels);
  emotion_face_box_t face = {};
  face.x = 1.0f;
  face.y = 1.0f;
  face.width = 1.0f;
  face.height = 1.0f;
  PreprocessOptions options;
  options.target_width = 1;
  options.target_height = 1;

  const PreprocessResult result = preprocess_image(image, &face, options);

  expect_true(result.ok, "crop preprocessing should succeed");
  expect_true(result.tensor.values == std::vector<float>({1, 1, 1}),
              "crop should select bottom-right white pixel");
}

void unsupported_format_fails() {
  std::vector<uint8_t> pixels;
  emotion_image_t image = rgb_image(&pixels);
  image.pixel_format = EMOTION_PIXEL_FORMAT_NV12;
  PreprocessOptions options;
  options.target_width = 1;
  options.target_height = 1;

  const PreprocessResult result = preprocess_image(image, nullptr, options);

  expect_true(!result.ok, "unsupported format should fail");
  expect_true(result.error == "unsupported pixel format",
              "unsupported format error should be reported");
}

}  // namespace

int main() {
  rgb_to_nhwc_tensor_matches_golden();
  bgra_to_nchw_tensor_reorders_channels();
  face_crop_uses_requested_region();
  unsupported_format_fails();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
