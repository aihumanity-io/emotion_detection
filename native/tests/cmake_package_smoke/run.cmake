if(NOT DEFINED EMOTION_NATIVE_BINARY_DIR)
  message(FATAL_ERROR "EMOTION_NATIVE_BINARY_DIR is required")
endif()
if(NOT DEFINED EMOTION_SMOKE_SOURCE_DIR)
  message(FATAL_ERROR "EMOTION_SMOKE_SOURCE_DIR is required")
endif()
if(NOT DEFINED EMOTION_INSTALL_LIBDIR)
  set(EMOTION_INSTALL_LIBDIR "lib")
endif()
if(NOT DEFINED EMOTION_CTEST_COMMAND)
  set(EMOTION_CTEST_COMMAND ctest)
endif()

set(install_dir "${EMOTION_NATIVE_BINARY_DIR}/package-smoke/install")
set(consumer_build_dir "${EMOTION_NATIVE_BINARY_DIR}/package-smoke/build")
file(REMOVE_RECURSE "${install_dir}" "${consumer_build_dir}")

set(install_command
  "${CMAKE_COMMAND}" --install "${EMOTION_NATIVE_BINARY_DIR}" --prefix "${install_dir}")
if(DEFINED EMOTION_BUILD_CONFIG AND NOT "${EMOTION_BUILD_CONFIG}" STREQUAL "")
  list(APPEND install_command --config "${EMOTION_BUILD_CONFIG}")
endif()
execute_process(
  COMMAND ${install_command}
  RESULT_VARIABLE install_result)
if(NOT install_result EQUAL 0)
  message(FATAL_ERROR "install failed: ${install_result}")
endif()

set(configure_command
  "${CMAKE_COMMAND}"
  -S "${EMOTION_SMOKE_SOURCE_DIR}"
  -B "${consumer_build_dir}"
  "-DCMAKE_PREFIX_PATH=${install_dir}"
  "-DEMOTION_PACKAGE_BIN_DIR=${install_dir}/bin"
  "-DEMOTION_PACKAGE_LIB_DIR=${install_dir}/${EMOTION_INSTALL_LIBDIR}")
if(DEFINED CMAKE_BUILD_TYPE AND NOT "${CMAKE_BUILD_TYPE}" STREQUAL "")
  list(APPEND configure_command "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}")
endif()
execute_process(
  COMMAND ${configure_command}
  RESULT_VARIABLE configure_result)
if(NOT configure_result EQUAL 0)
  message(FATAL_ERROR "consumer configure failed: ${configure_result}")
endif()

set(build_command "${CMAKE_COMMAND}" --build "${consumer_build_dir}")
if(DEFINED EMOTION_BUILD_CONFIG AND NOT "${EMOTION_BUILD_CONFIG}" STREQUAL "")
  list(APPEND build_command --config "${EMOTION_BUILD_CONFIG}")
endif()
execute_process(
  COMMAND ${build_command}
  RESULT_VARIABLE build_result)
if(NOT build_result EQUAL 0)
  message(FATAL_ERROR "consumer build failed: ${build_result}")
endif()

set(test_command "${EMOTION_CTEST_COMMAND}" --test-dir "${consumer_build_dir}" --output-on-failure)
if(DEFINED EMOTION_BUILD_CONFIG AND NOT "${EMOTION_BUILD_CONFIG}" STREQUAL "")
  list(APPEND test_command -C "${EMOTION_BUILD_CONFIG}")
endif()
execute_process(
  COMMAND ${test_command}
  RESULT_VARIABLE test_result)
if(NOT test_result EQUAL 0)
  message(FATAL_ERROR "consumer test failed: ${test_result}")
endif()
