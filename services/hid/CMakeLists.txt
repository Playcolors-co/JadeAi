cmake_minimum_required(VERSION 3.16)
project(jadeai_hid LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
add_compile_options(-Wall -Wextra -Wpedantic)

find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
find_package(yaml-cpp REQUIRED)

pkg_check_modules(SDBUSCPP REQUIRED IMPORTED_TARGET sdbus-c++)

add_executable(jadeai-hid
    src/main.cpp
    src/hid_config.cpp
    src/bluetooth_hid_server.cpp
    src/hid_reports.cpp
    src/http_api.cpp
)

target_include_directories(jadeai-hid
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/third_party
)

target_link_libraries(jadeai-hid
    PRIVATE
        yaml-cpp
        PkgConfig::SDBUSCPP
        Threads::Threads
)

install(TARGETS jadeai-hid DESTINATION bin)
