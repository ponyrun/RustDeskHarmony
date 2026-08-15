cmake_minimum_required(VERSION 3.5.0)
project(remote_crypto)

set(PROJECT_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../..)
set(SODIUM_ROOT ${PROJECT_ROOT}/native/vendor/libsodium)
set(ZSTD_ROOT ${PROJECT_ROOT}/third_party/zstd)

set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory(${ZSTD_ROOT}/build/cmake ${CMAKE_CURRENT_BINARY_DIR}/zstd EXCLUDE_FROM_ALL)

add_library(remote_crypto SHARED remote_crypto.cpp)
target_compile_features(remote_crypto PRIVATE cxx_std_17)
target_include_directories(remote_crypto PRIVATE ${SODIUM_ROOT}/include)

add_library(sodium STATIC IMPORTED)
set_target_properties(sodium PROPERTIES
    IMPORTED_LOCATION ${SODIUM_ROOT}/${OHOS_ARCH}/libsodium.a)

target_link_libraries(remote_crypto PUBLIC sodium libzstd_static libace_napi.z.so libnative_media_vdec.so
    libnative_media_codecbase.so libnative_media_core.so libnative_window.so)
