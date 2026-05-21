#ifndef EMOTION_SDK_H_
#define EMOTION_SDK_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(EMOTION_SDK_BUILDING_SHARED)
#define EMOTION_SDK_API __declspec(dllexport)
#elif defined(EMOTION_SDK_USING_SHARED)
#define EMOTION_SDK_API __declspec(dllimport)
#else
#define EMOTION_SDK_API
#endif
#else
#if defined(EMOTION_SDK_BUILDING_SHARED)
#define EMOTION_SDK_API __attribute__((visibility("default")))
#else
#define EMOTION_SDK_API
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define EMOTION_SDK_ABI_VERSION 1u
#define EMOTION_SDK_USER_CODE_SIZE 32u
#define EMOTION_SDK_ERROR_MESSAGE_SIZE 160u

typedef enum emotion_status_t {
  EMOTION_STATUS_OK = 0,
  EMOTION_STATUS_INVALID_ARGUMENT = 1,
  EMOTION_STATUS_NOT_INITIALIZED = 2,
  EMOTION_STATUS_MODEL_NOT_FOUND = 3,
  EMOTION_STATUS_MANIFEST_INVALID = 4,
  EMOTION_STATUS_CRYPTO_FAILED = 5,
  EMOTION_STATUS_LICENSE_INVALID = 6,
  EMOTION_STATUS_RUNTIME_FAILED = 7,
  EMOTION_STATUS_BUFFER_TOO_SMALL = 8,
  EMOTION_STATUS_UNSUPPORTED = 9,
  EMOTION_STATUS_INTERNAL = 10
} emotion_status_t;

typedef enum emotion_log_level_t {
  EMOTION_LOG_DEBUG = 0,
  EMOTION_LOG_INFO = 1,
  EMOTION_LOG_WARN = 2,
  EMOTION_LOG_ERROR = 3
} emotion_log_level_t;

typedef enum emotion_runtime_preference_t {
  EMOTION_RUNTIME_DEFAULT = 0,
  EMOTION_RUNTIME_ONNX = 1
} emotion_runtime_preference_t;

typedef enum emotion_accelerator_preference_t {
  EMOTION_ACCELERATOR_DEFAULT = 0,
  EMOTION_ACCELERATOR_CPU = 1,
  EMOTION_ACCELERATOR_COREML = 2,
  EMOTION_ACCELERATOR_NNAPI = 3,
  EMOTION_ACCELERATOR_DIRECTML = 4,
  EMOTION_ACCELERATOR_XNNPACK = 5
} emotion_accelerator_preference_t;

typedef enum emotion_pixel_format_t {
  EMOTION_PIXEL_FORMAT_RGB_U8 = 0,
  EMOTION_PIXEL_FORMAT_RGBA_U8 = 1,
  EMOTION_PIXEL_FORMAT_BGRA_U8 = 2,
  EMOTION_PIXEL_FORMAT_NV12 = 3,
  EMOTION_PIXEL_FORMAT_YUV420 = 4
} emotion_pixel_format_t;

typedef enum emotion_image_orientation_t {
  EMOTION_IMAGE_ORIENTATION_UP = 0,
  EMOTION_IMAGE_ORIENTATION_RIGHT = 1,
  EMOTION_IMAGE_ORIENTATION_DOWN = 2,
  EMOTION_IMAGE_ORIENTATION_LEFT = 3
} emotion_image_orientation_t;

typedef void (*emotion_log_callback_t)(
    emotion_log_level_t level,
    const char *stage,
    const char *model_id,
    const char *message,
    void *user_data);

typedef emotion_status_t (*emotion_secure_store_get_t)(
    const char *namespace_id,
    const char *key,
    uint8_t *out_value,
    size_t *in_out_value_len,
    void *user_data);

typedef emotion_status_t (*emotion_secure_store_set_t)(
    const char *namespace_id,
    const char *key,
    const uint8_t *value,
    size_t value_len,
    void *user_data);

typedef emotion_status_t (*emotion_secure_store_delete_t)(
    const char *namespace_id,
    const char *key,
    void *user_data);

typedef struct emotion_secure_store_adapter_t {
  uint32_t abi_version;
  emotion_secure_store_get_t get;
  emotion_secure_store_set_t set;
  emotion_secure_store_delete_t delete_value;
  void *user_data;
} emotion_secure_store_adapter_t;

typedef struct emotion_config_t {
  uint32_t abi_version;
  const char *cache_dir;
  const emotion_secure_store_adapter_t *secure_store;
  emotion_log_callback_t log_callback;
  void *log_user_data;
  uint8_t enable_debug_logging;
} emotion_config_t;

typedef struct emotion_model_config_t {
  uint32_t abi_version;
  const char *model_id;
  const char *manifest_path;
  const char *encrypted_model_path;
  emotion_runtime_preference_t runtime_preference;
  emotion_accelerator_preference_t accelerator_preference;
} emotion_model_config_t;

typedef struct emotion_image_plane_t {
  const uint8_t *data;
  size_t data_len;
  uint32_t row_stride;
  uint32_t pixel_stride;
} emotion_image_plane_t;

typedef struct emotion_image_t {
  uint32_t abi_version;
  emotion_pixel_format_t pixel_format;
  uint32_t width;
  uint32_t height;
  emotion_image_orientation_t orientation;
  uint8_t mirrored;
  uint32_t plane_count;
  emotion_image_plane_t planes[3];
} emotion_image_t;

typedef struct emotion_face_box_t {
  float x;
  float y;
  float width;
  float height;
  float confidence;
} emotion_face_box_t;

typedef struct emotion_class_score_t {
  uint32_t label_index;
  float probability;
} emotion_class_score_t;

typedef struct emotion_result_t {
  uint32_t abi_version;
  uint32_t top_label_index;
  float top_probability;
  emotion_class_score_t *scores;
  size_t scores_capacity;
  size_t scores_count;
  int64_t preprocess_time_us;
  int64_t inference_time_us;
  int64_t postprocess_time_us;
  emotion_status_t status;
  char error_message[EMOTION_SDK_ERROR_MESSAGE_SIZE];
} emotion_result_t;

EMOTION_SDK_API emotion_status_t emotion_init(
    const emotion_config_t *config);

EMOTION_SDK_API emotion_status_t emotion_register_model(
    const emotion_model_config_t *config);

EMOTION_SDK_API emotion_status_t emotion_set_user_code(
    const char *user_name,
    const char *model_id,
    const uint8_t *code32);

EMOTION_SDK_API emotion_status_t emotion_set_key_shard(
    const char *model_id,
    const uint8_t *shard,
    size_t shard_len,
    int64_t expires_at_ms);

EMOTION_SDK_API emotion_status_t emotion_set_license(
    const char *model_id,
    const char *license_json);

EMOTION_SDK_API emotion_status_t emotion_warmup(
    const char *model_id);

EMOTION_SDK_API emotion_status_t emotion_predict_image(
    const char *model_id,
    const emotion_image_t *image,
    const emotion_face_box_t *face_box,
    emotion_result_t *result);

EMOTION_SDK_API emotion_status_t emotion_unload(
    const char *model_id);

EMOTION_SDK_API emotion_status_t emotion_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif  // EMOTION_SDK_H_
