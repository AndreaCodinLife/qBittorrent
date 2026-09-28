cmake_minimum_required(VERSION 3.16 FATAL_ERROR)

project(qBitXThemeExtractor LANGUAGES CXX)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core)

add_executable(qbitx-qbtheme-extractor main.cpp)
target_compile_features(qbitx-qbtheme-extractor PRIVATE cxx_std_20)
target_link_libraries(qbitx-qbtheme-extractor PRIVATE Qt6::Core)
