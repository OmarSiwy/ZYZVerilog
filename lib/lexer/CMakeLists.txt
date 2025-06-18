cmake_minimum_required(VERSION 3.15)
project(native C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -g -O0")
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O3 -DNDEBUG")

include_directories(inc)
file(GLOB_RECURSE C_SOURCES "src/*.c")
list(FILTER C_SOURCES EXCLUDE REGEX ".*\\.(rs|toml)$")
message(STATUS "Found C sources: ${C_SOURCES}")

# Create Library
add_library(native STATIC ${C_SOURCES})
set_target_properties(native PROPERTIES
    OUTPUT_NAME "native"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
target_include_directories(native PUBLIC inc)
