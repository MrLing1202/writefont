cmake_minimum_required(VERSION 3.10)
project(writefont_native)

add_library(native_key SHARED native_key.c)
target_link_libraries(native_key log)
