cmake_minimum_required(VERSION 3.22.1)
project(soloud_flutter)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Ensure C++ runtime features (exceptions, RTTI) are available for SoLoud
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fexceptions -frtti")

file(GLOB SOLOUD_CORE
  soloud/src/core/soloud*.cpp
)
file(GLOB SOLOUD_WAV
  soloud/src/audiosource/wav/soloud_wav.cpp
  soloud/src/audiosource/wav/soloud_wavstream.cpp
  soloud/src/audiosource/wav/dr_impl.cpp
  soloud/src/audiosource/wav/stb_vorbis.c
)

set(SOLOUD_BACKEND
  soloud/src/backend/miniaudio/soloud_miniaudio.cpp
)

# stb_vorbis already included once via SOLOUD_WAV group; avoid duplicate compilation.
set(SOLOUD_OGG )

# MP3 (if using dr_mp3 via dr_impl or dedicated mp3 source; SoLoud uses dr_mp3 through dr_impl)
# Additional explicit MP3 sources not required beyond dr_impl.cpp for basic decoding.

add_library(soloud STATIC ${SOLOUD_CORE} ${SOLOUD_WAV} ${SOLOUD_BACKEND})
target_include_directories(soloud PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/soloud/include)
target_compile_definitions(soloud PUBLIC WITH_MINIAUDIO)

add_library(soloud_flutter SHARED soloud_bridge.cpp)

find_library(LOG_LIB log)

target_link_libraries(soloud_flutter PRIVATE soloud ${LOG_LIB} c++_shared)
