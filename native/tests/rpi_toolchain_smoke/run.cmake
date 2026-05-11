set(native_source_dir "${CMAKE_CURRENT_LIST_DIR}/../..")
set(presets_file "${native_source_dir}/CMakePresets.json")
set(toolchain_file "${native_source_dir}/cmake/toolchains/raspberry-pi-aarch64.cmake")
set(build_script "${native_source_dir}/scripts/build-rpi-aarch64.sh")

foreach(required_file IN ITEMS "${presets_file}" "${toolchain_file}" "${build_script}")
  if(NOT EXISTS "${required_file}")
    message(FATAL_ERROR "missing required Raspberry Pi build file: ${required_file}")
  endif()
endforeach()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -S "${native_source_dir}" --list-presets
  RESULT_VARIABLE list_result
  OUTPUT_VARIABLE list_output
  ERROR_VARIABLE list_error)
if(NOT list_result EQUAL 0)
  message(FATAL_ERROR "cmake preset listing failed: ${list_error}")
endif()

if(NOT list_output MATCHES "rpi-aarch64-release")
  message(FATAL_ERROR "rpi-aarch64-release preset not listed:\n${list_output}")
endif()

file(READ "${toolchain_file}" toolchain_contents)
foreach(expected IN ITEMS
    "CMAKE_SYSTEM_NAME Linux"
    "CMAKE_SYSTEM_PROCESSOR aarch64"
    "aarch64-linux-gnu-gcc"
    "AARCH64_LINUX_GNU_SYSROOT"
    "CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY")
  if(NOT toolchain_contents MATCHES "${expected}")
    message(FATAL_ERROR "toolchain file missing expected setting: ${expected}")
  endif()
endforeach()

file(READ "${build_script}" build_script_contents)
foreach(expected IN ITEMS
    "aarch64-linux-gnu-gcc"
    "cmake --preset rpi-aarch64-release"
    "cmake --build --preset rpi-aarch64-release")
  if(NOT build_script_contents MATCHES "${expected}")
    message(FATAL_ERROR "build script missing expected command: ${expected}")
  endif()
endforeach()
