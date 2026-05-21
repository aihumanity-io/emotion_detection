#include "emotion_sdk.h"

#include <chrono>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct PpmImage {
  uint32_t width = 0u;
  uint32_t height = 0u;
  std::vector<uint8_t> rgb;
};

bool read_token(std::istream& input, std::string* token) {
  while (input >> *token) {
    if (!token->empty() && (*token)[0] == '#') {
      input.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
      continue;
    }
    return true;
  }
  return false;
}

bool parse_u32(const std::string& token, uint32_t* value) {
  char* end = nullptr;
  const unsigned long parsed = std::strtoul(token.c_str(), &end, 10);
  if (end == token.c_str() || *end != '\0' ||
      parsed > static_cast<unsigned long>(std::numeric_limits<uint32_t>::max())) {
    return false;
  }
  *value = static_cast<uint32_t>(parsed);
  return true;
}

bool parse_size(const char* value, size_t* parsed_value) {
  char* end = nullptr;
  const unsigned long parsed = std::strtoul(value, &end, 10);
  if (end == value || *end != '\0' || parsed == 0ul) {
    return false;
  }
  *parsed_value = static_cast<size_t>(parsed);
  return true;
}

bool load_ppm_p3(const char* path, PpmImage* image, std::string* error) {
  std::ifstream input(path);
  if (!input) {
    *error = "failed to open image";
    return false;
  }

  std::string token;
  if (!read_token(input, &token) || token != "P3") {
    *error = "expected P3 PPM image";
    return false;
  }
  if (!read_token(input, &token) || !parse_u32(token, &image->width) ||
      !read_token(input, &token) || !parse_u32(token, &image->height)) {
    *error = "invalid PPM dimensions";
    return false;
  }

  uint32_t max_value = 0u;
  if (!read_token(input, &token) || !parse_u32(token, &max_value) ||
      max_value == 0u || max_value > 255u) {
    *error = "invalid PPM max value";
    return false;
  }

  const size_t channel_count =
      static_cast<size_t>(image->width) * static_cast<size_t>(image->height) * 3u;
  image->rgb.clear();
  image->rgb.reserve(channel_count);
  for (size_t i = 0; i < channel_count; ++i) {
    uint32_t channel = 0u;
    if (!read_token(input, &token) || !parse_u32(token, &channel) ||
        channel > max_value) {
      *error = "invalid PPM pixel data";
      return false;
    }
    image->rgb.push_back(static_cast<uint8_t>((channel * 255u) / max_value));
  }
  return true;
}

emotion_image_t emotion_image_for(const PpmImage& image) {
  emotion_image_t emotion_image = {};
  emotion_image.abi_version = EMOTION_SDK_ABI_VERSION;
  emotion_image.pixel_format = EMOTION_PIXEL_FORMAT_RGB_U8;
  emotion_image.width = image.width;
  emotion_image.height = image.height;
  emotion_image.orientation = EMOTION_IMAGE_ORIENTATION_UP;
  emotion_image.plane_count = 1u;
  emotion_image.planes[0].data = image.rgb.data();
  emotion_image.planes[0].data_len = image.rgb.size();
  emotion_image.planes[0].row_stride = image.width * 3u;
  emotion_image.planes[0].pixel_stride = 3u;
  return emotion_image;
}

int64_t elapsed_us(std::chrono::steady_clock::time_point start,
                   std::chrono::steady_clock::time_point end) {
  return std::chrono::duration_cast<std::chrono::microseconds>(end - start)
      .count();
}

void print_usage(const char* program) {
  std::cerr << "usage: " << program
            << " <manifest.json> <image.ppm> [iterations]"
            << " [encrypted_model_path] [model_id]" << std::endl;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) {
    print_usage(argv[0]);
    return EXIT_FAILURE;
  }

  const char* manifest_path = argv[1];
  const char* image_path = argv[2];
  size_t iterations = 10u;
  if (argc >= 4 && !parse_size(argv[3], &iterations)) {
    std::cerr << "iterations must be a positive integer" << std::endl;
    return EXIT_FAILURE;
  }
  const char* encrypted_model_path = argc >= 5 ? argv[4] : manifest_path;
  const char* model_id = argc >= 6 ? argv[5] : "aih_fer2025";

  PpmImage image;
  std::string error;
  if (!load_ppm_p3(image_path, &image, &error)) {
    std::cerr << error << ": " << image_path << std::endl;
    return EXIT_FAILURE;
  }

  emotion_config_t sdk_config = {};
  sdk_config.abi_version = EMOTION_SDK_ABI_VERSION;

  emotion_model_config_t model_config = {};
  model_config.abi_version = EMOTION_SDK_ABI_VERSION;
  model_config.model_id = model_id;
  model_config.manifest_path = manifest_path;
  model_config.encrypted_model_path = encrypted_model_path;
  model_config.runtime_preference = EMOTION_RUNTIME_DEFAULT;
  model_config.accelerator_preference = EMOTION_ACCELERATOR_CPU;

  const std::chrono::steady_clock::time_point load_start =
      std::chrono::steady_clock::now();
  emotion_status_t status = emotion_init(&sdk_config);
  if (status == EMOTION_STATUS_OK) {
    status = emotion_register_model(&model_config);
  }
  const std::chrono::steady_clock::time_point load_end =
      std::chrono::steady_clock::now();
  if (status != EMOTION_STATUS_OK) {
    std::cerr << "load failed: " << status << std::endl;
    emotion_shutdown();
    return EXIT_FAILURE;
  }

  const std::chrono::steady_clock::time_point warmup_start =
      std::chrono::steady_clock::now();
  status = emotion_warmup(model_id);
  const std::chrono::steady_clock::time_point warmup_end =
      std::chrono::steady_clock::now();
  if (status != EMOTION_STATUS_OK) {
    std::cerr << "warmup failed: " << status << std::endl;
    emotion_shutdown();
    return EXIT_FAILURE;
  }

  emotion_class_score_t scores[16] = {};
  emotion_result_t result = {};
  result.scores = scores;
  result.scores_capacity = sizeof(scores) / sizeof(scores[0]);
  const emotion_image_t emotion_image = emotion_image_for(image);

  int64_t predict_total_us = 0;
  for (size_t i = 0; i < iterations; ++i) {
    result = {};
    result.scores = scores;
    result.scores_capacity = sizeof(scores) / sizeof(scores[0]);
    const std::chrono::steady_clock::time_point predict_start =
        std::chrono::steady_clock::now();
    status = emotion_predict_image(model_id, &emotion_image, nullptr, &result);
    const std::chrono::steady_clock::time_point predict_end =
        std::chrono::steady_clock::now();
    if (status != EMOTION_STATUS_OK) {
      std::cerr << "predict failed: " << status
                << " message=" << result.error_message << std::endl;
      emotion_shutdown();
      return EXIT_FAILURE;
    }
    predict_total_us += elapsed_us(predict_start, predict_end);
  }

  const emotion_status_t unload_status = emotion_unload(model_id);
  const emotion_status_t shutdown_status = emotion_shutdown();
  if (unload_status != EMOTION_STATUS_OK || shutdown_status != EMOTION_STATUS_OK) {
    std::cerr << "cleanup failed: unload=" << unload_status
              << " shutdown=" << shutdown_status << std::endl;
    return EXIT_FAILURE;
  }

  const int64_t load_us = elapsed_us(load_start, load_end);
  const int64_t warmup_us = elapsed_us(warmup_start, warmup_end);
  const int64_t predict_avg_us =
      predict_total_us / static_cast<int64_t>(iterations);
  std::cout << "benchmark"
            << " iterations=" << iterations
            << " load_time_us=" << load_us
            << " warmup_time_us=" << warmup_us
            << " predict_avg_us=" << predict_avg_us
            << " top_label_index=" << result.top_label_index
            << " top_probability=" << result.top_probability
            << " scores_count=" << result.scores_count << std::endl;
  return EXIT_SUCCESS;
}
