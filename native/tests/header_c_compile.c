#include "emotion_sdk.h"

#include <stddef.h>
#include <stdint.h>

#define EMOTION_STATIC_ASSERT(name, expression) \
  typedef char emotion_static_assert_##name[(expression) ? 1 : -1]

EMOTION_STATIC_ASSERT(user_code_size, EMOTION_SDK_USER_CODE_SIZE == 32u);
EMOTION_STATIC_ASSERT(status_size, sizeof(emotion_status_t) <= sizeof(int));
EMOTION_STATIC_ASSERT(image_has_three_planes,
                      sizeof(((emotion_image_t *)0)->planes) /
                              sizeof(emotion_image_plane_t) ==
                          3u);

static void test_struct_initializers(void) {
  emotion_config_t config = {0};
  emotion_model_config_t model = {0};
  emotion_image_t image = {0};
  emotion_result_t result = {0};

  config.abi_version = EMOTION_SDK_ABI_VERSION;
  model.abi_version = EMOTION_SDK_ABI_VERSION;
  image.abi_version = EMOTION_SDK_ABI_VERSION;
  result.abi_version = EMOTION_SDK_ABI_VERSION;

  result.status = EMOTION_STATUS_OK;
  result.error_message[0] = '\0';
}

int main(void) {
  test_struct_initializers();
  return 0;
}
