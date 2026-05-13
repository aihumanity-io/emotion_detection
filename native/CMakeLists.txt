cmake_minimum_required(VERSION 3.14)

project(emotion_native_contract VERSION 0.1.0 LANGUAGES C CXX)

option(EMOTION_SDK_BUILD_TESTS "Build native SDK contract tests" ON)
option(EMOTION_SDK_BUILD_INSTALLABLE "Build installable native SDK package target" ON)
option(EMOTION_ENABLE_ONNX_RUNTIME "Link native SDK against ONNX Runtime" OFF)
option(EMOTION_ENABLE_LIBSECRET "Link Linux SDK secure store against libsecret" OFF)
set(ONNXRUNTIME_ROOT "" CACHE PATH "ONNX Runtime package root")

include(CMakePackageConfigHelpers)
include(FetchContent)
include(GNUInstallDirs)
if(EMOTION_ENABLE_LIBSECRET)
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(LIBSECRET REQUIRED IMPORTED_TARGET libsecret-1)
endif()
FetchContent_Declare(
  nlohmann_json
  URL https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz
  SOURCE_SUBDIR json
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(nlohmann_json)
if(NOT TARGET nlohmann_json::nlohmann_json)
  add_library(nlohmann_json_fallback INTERFACE)
  target_include_directories(nlohmann_json_fallback INTERFACE
    "${nlohmann_json_SOURCE_DIR}/include"
    "${nlohmann_json_SOURCE_DIR}/single_include")
  add_library(nlohmann_json::nlohmann_json ALIAS nlohmann_json_fallback)
endif()

set(ENABLE_TESTING OFF CACHE BOOL "Disable mbedTLS tests" FORCE)
set(ENABLE_PROGRAMS OFF CACHE BOOL "Disable mbedTLS programs" FORCE)
FetchContent_Declare(
  mbedtls
  URL https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.5/mbedtls-3.6.5.tar.bz2
  SOURCE_SUBDIR mbedtls-3.6.5
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(mbedtls)
set(EMOTION_MBEDTLS_INCLUDE_DIRS
  "${mbedtls_SOURCE_DIR}/include"
  "${mbedtls_SOURCE_DIR}/mbedtls-3.6.5/include")
if(TARGET MbedTLS::mbedcrypto)
  set(EMOTION_MBEDCRYPTO_TARGET MbedTLS::mbedcrypto)
elseif(TARGET mbedcrypto)
  set(EMOTION_MBEDCRYPTO_TARGET mbedcrypto)
elseif(TARGET mbedcrypto_static)
  set(EMOTION_MBEDCRYPTO_TARGET mbedcrypto_static)
else()
  message(FATAL_ERROR "mbedTLS FetchContent did not expose an mbedcrypto target")
endif()

add_library(emotion_sdk_headers INTERFACE)
target_include_directories(emotion_sdk_headers INTERFACE
  "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
  "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>")

set(EMOTION_NATIVE_CORE_SOURCES
  src/crypto_aes_gcm.cpp
  src/decrypt_pipeline.cpp
  src/file_secure_store.cpp
  src/linux_secret_store.cpp
  src/windows_secure_store.cpp
  src/crypto_sha256.cpp
  src/key_material.cpp
  src/license_state.cpp
  src/logging.cpp
  src/model_manifest.cpp
  src/model_package.cpp
  src/model_registry.cpp
  src/onnx_runtime_adapter.cpp
  src/postprocessing.cpp
  src/preprocessing.cpp
  src/runtime_session.cpp
  src/sdk.cpp
  src/secure_store.cpp)

add_library(emotion_native_core STATIC ${EMOTION_NATIVE_CORE_SOURCES})
target_include_directories(emotion_native_core PUBLIC
  "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
  "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>")
target_include_directories(emotion_native_core PRIVATE
  ${EMOTION_MBEDTLS_INCLUDE_DIRS})
target_link_libraries(emotion_native_core PRIVATE
  ${EMOTION_MBEDCRYPTO_TARGET}
  nlohmann_json::nlohmann_json)
if(EMOTION_ENABLE_LIBSECRET)
  target_compile_definitions(emotion_native_core PUBLIC EMOTION_ENABLE_LIBSECRET=1)
  target_link_libraries(emotion_native_core PRIVATE PkgConfig::LIBSECRET)
else()
  target_compile_definitions(emotion_native_core PUBLIC EMOTION_ENABLE_LIBSECRET=0)
endif()
if(WIN32)
  target_link_libraries(emotion_native_core PRIVATE Crypt32)
endif()
if(EMOTION_ENABLE_ONNX_RUNTIME)
  if(NOT ONNXRUNTIME_ROOT)
    message(FATAL_ERROR "ONNXRUNTIME_ROOT is required when EMOTION_ENABLE_ONNX_RUNTIME=ON")
  endif()
  target_compile_definitions(emotion_native_core PUBLIC EMOTION_ENABLE_ONNX_RUNTIME=1)
  target_include_directories(emotion_native_core PRIVATE
    "${ONNXRUNTIME_ROOT}/include")
  find_library(ONNXRUNTIME_LIBRARY
    NAMES onnxruntime
    PATHS "${ONNXRUNTIME_ROOT}/lib"
    NO_DEFAULT_PATH)
  if(NOT ONNXRUNTIME_LIBRARY)
    message(FATAL_ERROR "onnxruntime library not found under ${ONNXRUNTIME_ROOT}/lib")
  endif()
  target_link_libraries(emotion_native_core PRIVATE "${ONNXRUNTIME_LIBRARY}")
else()
  target_compile_definitions(emotion_native_core PUBLIC EMOTION_ENABLE_ONNX_RUNTIME=0)
endif()
set_target_properties(emotion_native_core PROPERTIES
  CXX_STANDARD 11
  CXX_STANDARD_REQUIRED YES
  CXX_EXTENSIONS NO)

if(EMOTION_SDK_BUILD_INSTALLABLE)
  add_library(emotion_sdk SHARED ${EMOTION_NATIVE_CORE_SOURCES})
  add_library(EmotionNativeSDK::emotion_sdk ALIAS emotion_sdk)
  target_include_directories(emotion_sdk PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
    "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>")
  target_include_directories(emotion_sdk PRIVATE
    ${EMOTION_MBEDTLS_INCLUDE_DIRS})
  target_compile_definitions(emotion_sdk PRIVATE EMOTION_SDK_BUILDING_SHARED)
  target_link_libraries(emotion_sdk PRIVATE
    ${EMOTION_MBEDCRYPTO_TARGET}
    nlohmann_json::nlohmann_json)
  if(EMOTION_ENABLE_LIBSECRET)
    target_compile_definitions(emotion_sdk PUBLIC EMOTION_ENABLE_LIBSECRET=1)
    target_link_libraries(emotion_sdk PRIVATE PkgConfig::LIBSECRET)
  else()
    target_compile_definitions(emotion_sdk PUBLIC EMOTION_ENABLE_LIBSECRET=0)
  endif()
  if(WIN32)
    target_link_libraries(emotion_sdk PRIVATE Crypt32)
  endif()
  if(EMOTION_ENABLE_ONNX_RUNTIME)
    target_compile_definitions(emotion_sdk PUBLIC EMOTION_ENABLE_ONNX_RUNTIME=1)
    target_include_directories(emotion_sdk PRIVATE
      "${ONNXRUNTIME_ROOT}/include")
    target_link_libraries(emotion_sdk PRIVATE "${ONNXRUNTIME_LIBRARY}")
  else()
    target_compile_definitions(emotion_sdk PUBLIC EMOTION_ENABLE_ONNX_RUNTIME=0)
  endif()
  set_target_properties(emotion_sdk PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO
    OUTPUT_NAME emotion_sdk
    VERSION ${PROJECT_VERSION}
    SOVERSION ${PROJECT_VERSION_MAJOR})

  install(TARGETS emotion_sdk
    EXPORT EmotionNativeSDKTargets
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
  install(DIRECTORY include/ DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
  install(EXPORT EmotionNativeSDKTargets
    FILE EmotionNativeSDKTargets.cmake
    NAMESPACE EmotionNativeSDK::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/EmotionNativeSDK)

  configure_package_config_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/EmotionNativeSDKConfig.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/EmotionNativeSDKConfig.cmake"
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/EmotionNativeSDK)
  write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/EmotionNativeSDKConfigVersion.cmake"
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion)
  install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/EmotionNativeSDKConfig.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/EmotionNativeSDKConfigVersion.cmake"
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/EmotionNativeSDK)
endif()

add_executable(emotion_still_image_sample
  samples/still_image_predict.cpp)
target_link_libraries(emotion_still_image_sample PRIVATE emotion_native_core)
set_target_properties(emotion_still_image_sample PROPERTIES
  CXX_STANDARD 11
  CXX_STANDARD_REQUIRED YES
  CXX_EXTENSIONS NO)

add_executable(emotion_benchmark_image
  samples/benchmark_image.cpp)
target_link_libraries(emotion_benchmark_image PRIVATE emotion_native_core)
set_target_properties(emotion_benchmark_image PROPERTIES
  CXX_STANDARD 11
  CXX_STANDARD_REQUIRED YES
  CXX_EXTENSIONS NO)

if(EMOTION_SDK_BUILD_TESTS)
  enable_testing()

  add_executable(emotion_sdk_header_c_test
    tests/header_c_compile.c)
  target_link_libraries(emotion_sdk_header_c_test PRIVATE emotion_sdk_headers)
  add_test(NAME emotion_sdk_header_c_test COMMAND emotion_sdk_header_c_test)

  add_executable(emotion_sdk_header_cpp_test
    tests/header_cpp_compile.cpp)
  target_link_libraries(emotion_sdk_header_cpp_test PRIVATE emotion_sdk_headers)
  set_target_properties(emotion_sdk_header_cpp_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_sdk_header_cpp_test COMMAND emotion_sdk_header_cpp_test)

  add_executable(emotion_model_manifest_test
    tests/model_manifest_test.cpp)
  target_link_libraries(emotion_model_manifest_test PRIVATE emotion_native_core)
  target_compile_definitions(emotion_model_manifest_test PRIVATE
    EMOTION_TEST_MANIFEST_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../test/resources/model_manifests")
  set_target_properties(emotion_model_manifest_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_model_manifest_test COMMAND emotion_model_manifest_test)

  add_executable(emotion_crypto_sha256_test
    tests/crypto_sha256_test.cpp)
  target_link_libraries(emotion_crypto_sha256_test PRIVATE emotion_native_core)
  set_target_properties(emotion_crypto_sha256_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_crypto_sha256_test COMMAND emotion_crypto_sha256_test)

  add_executable(emotion_crypto_hkdf_test
    tests/crypto_hkdf_test.cpp)
  target_link_libraries(emotion_crypto_hkdf_test PRIVATE emotion_native_core)
  set_target_properties(emotion_crypto_hkdf_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_crypto_hkdf_test COMMAND emotion_crypto_hkdf_test)

  add_executable(emotion_crypto_aes_gcm_test
    tests/crypto_aes_gcm_test.cpp)
  target_link_libraries(emotion_crypto_aes_gcm_test PRIVATE emotion_native_core)
  set_target_properties(emotion_crypto_aes_gcm_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_crypto_aes_gcm_test COMMAND emotion_crypto_aes_gcm_test)

  add_executable(emotion_key_material_test
    tests/key_material_test.cpp)
  target_link_libraries(emotion_key_material_test PRIVATE emotion_native_core)
  set_target_properties(emotion_key_material_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_key_material_test COMMAND emotion_key_material_test)

  add_executable(emotion_license_state_test
    tests/license_state_test.cpp)
  target_link_libraries(emotion_license_state_test PRIVATE emotion_native_core)
  set_target_properties(emotion_license_state_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_license_state_test COMMAND emotion_license_state_test)

  add_executable(emotion_secure_store_test
    tests/secure_store_test.cpp)
  target_link_libraries(emotion_secure_store_test PRIVATE emotion_native_core)
  set_target_properties(emotion_secure_store_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_secure_store_test COMMAND emotion_secure_store_test)

  add_executable(emotion_file_secure_store_test
    tests/file_secure_store_test.cpp)
  target_link_libraries(emotion_file_secure_store_test PRIVATE emotion_native_core)
  target_compile_definitions(emotion_file_secure_store_test PRIVATE
    EMOTION_TEST_TMP_DIR="${CMAKE_CURRENT_BINARY_DIR}/file_secure_store_test")
  set_target_properties(emotion_file_secure_store_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_file_secure_store_test COMMAND emotion_file_secure_store_test)

  add_executable(emotion_linux_secret_store_test
    tests/linux_secret_store_test.cpp)
  target_link_libraries(emotion_linux_secret_store_test PRIVATE emotion_native_core)
  set_target_properties(emotion_linux_secret_store_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_linux_secret_store_test COMMAND emotion_linux_secret_store_test)

  add_executable(emotion_windows_secure_store_test
    tests/windows_secure_store_test.cpp)
  target_link_libraries(emotion_windows_secure_store_test PRIVATE emotion_native_core)
  target_compile_definitions(emotion_windows_secure_store_test PRIVATE
    EMOTION_TEST_TMP_DIR="${CMAKE_CURRENT_BINARY_DIR}/windows_secure_store_test")
  set_target_properties(emotion_windows_secure_store_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_windows_secure_store_test COMMAND emotion_windows_secure_store_test)

  add_executable(emotion_logging_test
    tests/logging_test.cpp)
  target_link_libraries(emotion_logging_test PRIVATE emotion_native_core)
  set_target_properties(emotion_logging_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_logging_test COMMAND emotion_logging_test)

  add_executable(emotion_model_package_test
    tests/model_package_test.cpp)
  target_link_libraries(emotion_model_package_test PRIVATE emotion_native_core)
  target_compile_definitions(emotion_model_package_test PRIVATE
    EMOTION_TEST_PACKAGE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/resources")
  set_target_properties(emotion_model_package_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_model_package_test COMMAND emotion_model_package_test)

  add_executable(emotion_decrypt_pipeline_test
    tests/decrypt_pipeline_test.cpp)
  target_link_libraries(emotion_decrypt_pipeline_test PRIVATE emotion_native_core)
  set_target_properties(emotion_decrypt_pipeline_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_decrypt_pipeline_test COMMAND emotion_decrypt_pipeline_test)

  add_executable(emotion_model_registry_test
    tests/model_registry_test.cpp)
  target_link_libraries(emotion_model_registry_test PRIVATE emotion_native_core)
  set_target_properties(emotion_model_registry_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_model_registry_test COMMAND emotion_model_registry_test)

  add_executable(emotion_preprocessing_test
    tests/preprocessing_test.cpp)
  target_link_libraries(emotion_preprocessing_test PRIVATE emotion_native_core)
  set_target_properties(emotion_preprocessing_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_preprocessing_test COMMAND emotion_preprocessing_test)

  add_executable(emotion_postprocessing_test
    tests/postprocessing_test.cpp)
  target_link_libraries(emotion_postprocessing_test PRIVATE emotion_native_core)
  set_target_properties(emotion_postprocessing_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_postprocessing_test COMMAND emotion_postprocessing_test)

  add_executable(emotion_runtime_session_test
    tests/runtime_session_test.cpp)
  target_link_libraries(emotion_runtime_session_test PRIVATE emotion_native_core)
  set_target_properties(emotion_runtime_session_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_runtime_session_test COMMAND emotion_runtime_session_test)

  add_executable(emotion_onnx_runtime_adapter_test
    tests/onnx_runtime_adapter_test.cpp)
  target_link_libraries(emotion_onnx_runtime_adapter_test PRIVATE emotion_native_core)
  set_target_properties(emotion_onnx_runtime_adapter_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_onnx_runtime_adapter_test COMMAND emotion_onnx_runtime_adapter_test)

  add_executable(emotion_sdk_c_api_test
    tests/sdk_c_api_test.cpp)
  target_link_libraries(emotion_sdk_c_api_test PRIVATE emotion_native_core)
  target_compile_definitions(emotion_sdk_c_api_test PRIVATE
    EMOTION_TEST_MANIFEST_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../test/resources/model_manifests")
  set_target_properties(emotion_sdk_c_api_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_sdk_c_api_test COMMAND emotion_sdk_c_api_test)

  add_test(NAME emotion_still_image_sample_test
    COMMAND emotion_still_image_sample
      "${CMAKE_CURRENT_SOURCE_DIR}/../test/resources/model_manifests/valid_fer2025.json"
      "${CMAKE_CURRENT_SOURCE_DIR}/tests/resources/sample_rgb.ppm")
  set_tests_properties(emotion_still_image_sample_test PROPERTIES
    PASS_REGULAR_EXPRESSION "top_label_index=4")

  add_test(NAME emotion_benchmark_image_test
    COMMAND emotion_benchmark_image
      "${CMAKE_CURRENT_SOURCE_DIR}/../test/resources/model_manifests/valid_fer2025.json"
      "${CMAKE_CURRENT_SOURCE_DIR}/tests/resources/sample_rgb.ppm"
      "3")
  set_tests_properties(emotion_benchmark_image_test PROPERTIES
    PASS_REGULAR_EXPRESSION
      "benchmark iterations=3 .*load_time_us=[0-9]+ .*warmup_time_us=[0-9]+ .*predict_avg_us=[0-9]+ .*top_label_index=4 .*scores_count=5")

  if(EMOTION_SDK_BUILD_INSTALLABLE)
    add_test(NAME emotion_cmake_package_smoke
      COMMAND ${CMAKE_COMMAND}
        -DEMOTION_NATIVE_BINARY_DIR=${CMAKE_BINARY_DIR}
        -DEMOTION_SMOKE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/tests/cmake_package_smoke
        -DEMOTION_INSTALL_LIBDIR=${CMAKE_INSTALL_LIBDIR}
        -DEMOTION_BUILD_CONFIG=$<CONFIG>
        -DEMOTION_CTEST_COMMAND=${CMAKE_CTEST_COMMAND}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/cmake_package_smoke/run.cmake)
  endif()

  add_test(NAME emotion_rpi_toolchain_smoke
    COMMAND ${CMAKE_COMMAND}
      -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/rpi_toolchain_smoke/run.cmake)
endif()
