cmake_minimum_required(VERSION 3.22.1)
project(ixmnnjni CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The MNN runtime is prebuilt (release zip, unpacked into libs/mnn-jni by the
# README steps). We only link against it — nothing of MNN is compiled here.
set(MNN_LIBS "${CMAKE_CURRENT_SOURCE_DIR}/../../../../libs/mnn-jni/${ANDROID_ABI}")

foreach(lib MNN MNN_Express llm)
	add_library(${lib} SHARED IMPORTED)
	set_target_properties(${lib} PROPERTIES IMPORTED_LOCATION "${MNN_LIBS}/lib${lib}.so")
endforeach()

# q6/q6.cpp is pure C++17 with no MNN in it, so the same file compiles into
# tests/native/q6_test.cpp on a desktop and is checked against the GDScript.
add_library(ixmnnjni SHARED ixmnn_jni.cpp q6/q6.cpp)
target_include_directories(ixmnnjni PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(ixmnnjni llm MNN_Express MNN log)
