cmake_minimum_required(VERSION 3.14)

project(emotion_cmake_package_smoke LANGUAGES C)

find_package(EmotionNativeSDK CONFIG REQUIRED)

add_executable(package_smoke package_smoke.c)
target_link_libraries(package_smoke PRIVATE EmotionNativeSDK::emotion_sdk)

if(WIN32)
  add_custom_command(TARGET package_smoke POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      $<TARGET_FILE:EmotionNativeSDK::emotion_sdk>
      $<TARGET_FILE_DIR:package_smoke>)
endif()

if(DEFINED EMOTION_PACKAGE_LIB_DIR)
  set_target_properties(package_smoke PROPERTIES
    BUILD_RPATH "${EMOTION_PACKAGE_LIB_DIR}")
endif()

enable_testing()
add_test(NAME package_smoke COMMAND package_smoke)
