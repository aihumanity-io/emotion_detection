#include "emotion_sdk.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

emotion_config_t sdk_config() {
  emotion_config_t config = {};
  config.abi_version = EMOTION_SDK_ABI_VERSION;
  return config;
}

emotion_model_config_t model_config() {
  static const std::string manifest_path =
      std::string(EMOTION_TEST_MANIFEST_DIR) + "/valid_fer2025.json";
  emotion_model_config_t config = {};
  config.abi_version = EMOTION_SDK_ABI_VERSION;
  config.model_id = "aih_fer2025";
  config.manifest_path = manifest_path.c_str();
  config.encrypted_model_path = "/models/model.enc";
  config.runtime_preference = EMOTION_RUNTIME_DEFAULT;
  config.accelerator_preference = EMOTION_ACCELERATOR_CPU;
  return config;
}

emotion_model_config_t invalid_manifest_config() {
  emotion_model_config_t config = model_config();
  config.manifest_path = "/missing/manifest.json";
  return config;
}

emotion_image_t rgb_image(std::vector<uint8_t>* pixels) {
  *pixels = {255u, 0u, 0u};
  emotion_image_t image = {};
  image.abi_version = EMOTION_SDK_ABI_VERSION;
  image.pixel_format = EMOTION_PIXEL_FORMAT_RGB_U8;
  image.width = 1u;
  image.height = 1u;
  image.orientation = EMOTION_IMAGE_ORIENTATION_UP;
  image.plane_count = 1u;
  image.planes[0].data = pixels->data();
  image.planes[0].data_len = pixels->size();
  image.planes[0].row_stride = 3u;
  image.planes[0].pixel_stride = 3u;
  return image;
}

void predict_before_init_fails() {
  emotion_shutdown();
  std::vector<uint8_t> pixels;
  const emotion_image_t image = rgb_image(&pixels);
  emotion_result_t result = {};

  expect_true(emotion_predict_image("aih_fer2025", &image, nullptr, &result) ==
                  EMOTION_STATUS_NOT_INITIALIZED,
              "predict before init should fail");
  expect_true(result.status == EMOTION_STATUS_NOT_INITIALIZED,
              "result should carry not initialized status");
}

void init_register_warm_predict_unload_shutdown() {
  const emotion_config_t sdk = sdk_config();
  const emotion_model_config_t model = model_config();

  expect_true(emotion_init(&sdk) == EMOTION_STATUS_OK, "init should succeed");
  expect_true(emotion_register_model(&model) == EMOTION_STATUS_OK,
              "register should succeed");
  expect_true(emotion_warmup("aih_fer2025") == EMOTION_STATUS_OK,
              "warmup should succeed");

  std::vector<uint8_t> pixels;
  const emotion_image_t image = rgb_image(&pixels);
  emotion_class_score_t scores[5] = {};
  emotion_result_t result = {};
  result.scores = scores;
  result.scores_capacity = 5u;

  expect_true(emotion_predict_image("aih_fer2025", &image, nullptr, &result) ==
                  EMOTION_STATUS_OK,
              "predict should succeed");
  expect_true(result.status == EMOTION_STATUS_OK,
              "result status should be OK");
  expect_true(result.scores_count == 5u, "all manifest labels should be scored");
  expect_true(result.top_label_index == 4u, "fake runtime top index should win");

  expect_true(emotion_unload("aih_fer2025") == EMOTION_STATUS_OK,
              "unload should succeed");
  expect_true(emotion_shutdown() == EMOTION_STATUS_OK,
              "shutdown should succeed");
}

void result_buffer_too_small_is_reported() {
  const emotion_config_t sdk = sdk_config();
  const emotion_model_config_t model = model_config();

  expect_true(emotion_init(&sdk) == EMOTION_STATUS_OK, "init should succeed");
  expect_true(emotion_register_model(&model) == EMOTION_STATUS_OK,
              "register should succeed");
  expect_true(emotion_warmup("aih_fer2025") == EMOTION_STATUS_OK,
              "warmup should succeed");

  std::vector<uint8_t> pixels;
  const emotion_image_t image = rgb_image(&pixels);
  emotion_class_score_t scores[1] = {};
  emotion_result_t result = {};
  result.scores = scores;
  result.scores_capacity = 1u;

  expect_true(emotion_predict_image("aih_fer2025", &image, nullptr, &result) ==
                  EMOTION_STATUS_BUFFER_TOO_SMALL,
              "small result buffer should fail");
  expect_true(result.scores_count == 5u,
              "required score count should be reported");
  emotion_shutdown();
}

void provisioning_entrypoints_validate_model() {
  const emotion_config_t sdk = sdk_config();
  const emotion_model_config_t model = model_config();

  expect_true(emotion_init(&sdk) == EMOTION_STATUS_OK, "init should succeed");
  uint8_t user_code[EMOTION_SDK_USER_CODE_SIZE] = {};
  uint8_t shard[4] = {1u, 2u, 3u, 4u};

  expect_true(emotion_set_user_code("david", "missing", user_code) ==
                  EMOTION_STATUS_MODEL_NOT_FOUND,
              "missing user-code model should fail");
  expect_true(emotion_register_model(&model) == EMOTION_STATUS_OK,
              "register should succeed");
  expect_true(emotion_set_user_code("david", "aih_fer2025", user_code) ==
                  EMOTION_STATUS_OK,
              "set user code should succeed");
  expect_true(emotion_set_key_shard("aih_fer2025", shard, sizeof(shard), 0) ==
                  EMOTION_STATUS_OK,
              "set key shard should succeed");
  expect_true(emotion_set_license("aih_fer2025",
                                  "{\"model_id\":\"aih_fer2025\"}") ==
                  EMOTION_STATUS_OK,
              "set license should succeed");
  expect_true(emotion_set_license("aih_fer2025", "{\"model_id\":\"other\"}") ==
                  EMOTION_STATUS_LICENSE_INVALID,
              "mismatched license should fail");
  emotion_shutdown();
}

void failed_manifest_register_does_not_block_retry() {
  const emotion_config_t sdk = sdk_config();
  const emotion_model_config_t invalid_model = invalid_manifest_config();
  const emotion_model_config_t valid_model = model_config();

  expect_true(emotion_init(&sdk) == EMOTION_STATUS_OK, "init should succeed");
  expect_true(emotion_register_model(&invalid_model) ==
                  EMOTION_STATUS_MANIFEST_INVALID,
              "invalid manifest should fail");
  expect_true(emotion_register_model(&valid_model) == EMOTION_STATUS_OK,
              "retry with valid manifest should succeed");
  expect_true(emotion_shutdown() == EMOTION_STATUS_OK,
              "shutdown should succeed");
}

void repeated_lifecycle_cleanup_smoke() {
  for (int iteration = 0; iteration < 25; ++iteration) {
    const emotion_config_t sdk = sdk_config();
    const emotion_model_config_t model = model_config();

    expect_true(emotion_init(&sdk) == EMOTION_STATUS_OK, "init should succeed");
    expect_true(emotion_register_model(&model) == EMOTION_STATUS_OK,
                "register should succeed");
    expect_true(emotion_warmup("aih_fer2025") == EMOTION_STATUS_OK,
                "warmup should succeed");

    std::vector<uint8_t> pixels;
    const emotion_image_t image = rgb_image(&pixels);
    emotion_class_score_t scores[5] = {};
    emotion_result_t result = {};
    result.scores = scores;
    result.scores_capacity = 5u;

    expect_true(emotion_predict_image("aih_fer2025", &image, nullptr, &result) ==
                    EMOTION_STATUS_OK,
                "predict should succeed");
    expect_true(emotion_unload("aih_fer2025") == EMOTION_STATUS_OK,
                "unload should succeed");
    expect_true(emotion_shutdown() == EMOTION_STATUS_OK,
                "shutdown should succeed");
  }
}

}  // namespace

int main() {
  predict_before_init_fails();
  init_register_warm_predict_unload_shutdown();
  result_buffer_too_small_is_reported();
  provisioning_entrypoints_validate_model();
  failed_manifest_register_does_not_block_retry();
  repeated_lifecycle_cleanup_smoke();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
