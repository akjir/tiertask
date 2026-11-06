cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

set(GENERATED_VERSION_HEADER "${CMAKE_CURRENT_BINARY_DIR}/generated_version.h")
add_custom_target(generate_version_header ALL
  BYPRODUCTS "${GENERATED_VERSION_HEADER}"
  COMMAND ${CMAKE_COMMAND}
    "-DPROJECT_DIR=${CMAKE_SOURCE_DIR}/.."
    "-DPACKAGE_VERSION=0.1.0"
    "-DOUTPUT_HEADER=${GENERATED_VERSION_HEADER}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/generate_version.cmake"
  VERBATIM
)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)
add_dependencies(${BINARY_NAME} generate_version_header)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}")
