#include "emotion_preprocessing.h"

#include <algorithm>
#include <cmath>

namespace emotion {
namespace native_sdk {
namespace {

struct CropRect {
  uint32_t x;
  uint32_t y;
  uint32_t width;
  uint32_t height;
};

uint32_t bytes_per_pixel(emotion_pixel_format_t format) {
  switch (format) {
    case EMOTION_PIXEL_FORMAT_RGB_U8:
      return 3u;
    case EMOTION_PIXEL_FORMAT_RGBA_U8:
    case EMOTION_PIXEL_FORMAT_BGRA_U8:
      return 4u;
    default:
      return 0u;
  }
}

CropRect full_image_crop(const emotion_image_t& image) {
  CropRect crop = {0u, 0u, image.width, image.height};
  return crop;
}

CropRect clamp_face_box(const emotion_image_t& image,
                        const emotion_face_box_t* face_box) {
  if (face_box == nullptr || face_box->width <= 0.0f ||
      face_box->height <= 0.0f) {
    return full_image_crop(image);
  }

  const float max_x = static_cast<float>(image.width);
  const float max_y = static_cast<float>(image.height);
  const float left = std::max(0.0f, std::min(face_box->x, max_x));
  const float top = std::max(0.0f, std::min(face_box->y, max_y));
  const float right =
      std::max(left + 1.0f, std::min(face_box->x + face_box->width, max_x));
  const float bottom =
      std::max(top + 1.0f, std::min(face_box->y + face_box->height, max_y));

  CropRect crop;
  crop.x = static_cast<uint32_t>(std::floor(left));
  crop.y = static_cast<uint32_t>(std::floor(top));
  crop.width = std::max(1u, static_cast<uint32_t>(std::ceil(right)) - crop.x);
  crop.height = std::max(1u, static_cast<uint32_t>(std::ceil(bottom)) - crop.y);
  if (crop.x + crop.width > image.width) {
    crop.width = image.width - crop.x;
  }
  if (crop.y + crop.height > image.height) {
    crop.height = image.height - crop.y;
  }
  return crop;
}

bool read_rgb(const emotion_image_t& image,
              uint32_t x,
              uint32_t y,
              uint8_t* red,
              uint8_t* green,
              uint8_t* blue) {
  const emotion_image_plane_t& plane = image.planes[0];
  const uint32_t bpp = bytes_per_pixel(image.pixel_format);
  const size_t offset = static_cast<size_t>(y) * plane.row_stride +
                        static_cast<size_t>(x) * bpp;
  if (bpp == 0u || offset + bpp > plane.data_len) {
    return false;
  }

  switch (image.pixel_format) {
    case EMOTION_PIXEL_FORMAT_RGB_U8:
    case EMOTION_PIXEL_FORMAT_RGBA_U8:
      *red = plane.data[offset];
      *green = plane.data[offset + 1u];
      *blue = plane.data[offset + 2u];
      return true;
    case EMOTION_PIXEL_FORMAT_BGRA_U8:
      *blue = plane.data[offset];
      *green = plane.data[offset + 1u];
      *red = plane.data[offset + 2u];
      return true;
    default:
      return false;
  }
}

size_t tensor_index(const PreprocessOptions& options,
                    uint32_t y,
                    uint32_t x,
                    uint32_t channel) {
  if (options.layout == TensorLayout::kNchw) {
    return static_cast<size_t>(channel) * options.target_height *
               options.target_width +
           static_cast<size_t>(y) * options.target_width + x;
  }
  return (static_cast<size_t>(y) * options.target_width + x) * 3u + channel;
}

float normalize_channel(uint8_t value,
                        uint32_t channel,
                        const PreprocessOptions& options) {
  return (static_cast<float>(value) * options.scale - options.mean[channel]) /
         options.stddev[channel];
}

}  // namespace

PreprocessResult preprocess_image(const emotion_image_t& image,
                                  const emotion_face_box_t* face_box,
                                  const PreprocessOptions& options) {
  PreprocessResult result;
  if (image.abi_version != EMOTION_SDK_ABI_VERSION || image.width == 0u ||
      image.height == 0u || image.plane_count == 0u ||
      image.planes[0].data == nullptr) {
    result.error = "invalid image";
    return result;
  }
  if (image.orientation != EMOTION_IMAGE_ORIENTATION_UP) {
    result.error = "unsupported image orientation";
    return result;
  }
  if (bytes_per_pixel(image.pixel_format) == 0u) {
    result.error = "unsupported pixel format";
    return result;
  }
  if (options.target_width == 0u || options.target_height == 0u) {
    result.error = "invalid target shape";
    return result;
  }

  const CropRect crop = clamp_face_box(image, face_box);
  result.tensor.layout = options.layout;
  if (options.layout == TensorLayout::kNchw) {
    result.tensor.shape = {1, 3, static_cast<int64_t>(options.target_height),
                           static_cast<int64_t>(options.target_width)};
  } else {
    result.tensor.shape = {1, static_cast<int64_t>(options.target_height),
                           static_cast<int64_t>(options.target_width), 3};
  }
  result.tensor.values.assign(
      static_cast<size_t>(options.target_width) * options.target_height * 3u,
      0.0f);

  for (uint32_t y = 0; y < options.target_height; ++y) {
    const uint32_t source_y =
        crop.y + std::min(crop.height - 1u, y * crop.height / options.target_height);
    for (uint32_t x = 0; x < options.target_width; ++x) {
      const uint32_t source_x =
          crop.x + std::min(crop.width - 1u, x * crop.width / options.target_width);
      uint8_t red = 0;
      uint8_t green = 0;
      uint8_t blue = 0;
      if (!read_rgb(image, source_x, source_y, &red, &green, &blue)) {
        result.error = "invalid image buffer";
        result.tensor.values.clear();
        return result;
      }
      const uint8_t channels[3] = {red, green, blue};
      for (uint32_t channel = 0; channel < 3u; ++channel) {
        result.tensor.values[tensor_index(options, y, x, channel)] =
            normalize_channel(channels[channel], channel, options);
      }
    }
  }

  result.ok = true;
  return result;
}

}  // namespace native_sdk
}  // namespace emotion
