cmake_minimum_required(VERSION 3.10)
project(writefont_native)

add_library(native_key SHARED native_key.c)

# 链接 Android NDK 内置的 OpenSSL (BoringSSL)
find_package(OpenSSL)
if(OpenSSL_FOUND)
    target_link_libraries(native_key log OpenSSL::Crypto)
else()
    # NDK BoringSSL fallback: 直接链接 libcrypto
    target_link_libraries(native_key log crypto)
endif()
