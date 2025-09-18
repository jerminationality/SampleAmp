// Placeholder SoLoud bridge header. Replace stub implementations with real SoLoud API calls.
#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

// Opaque engine pointer
void* soloud_flutter_create();
void  soloud_flutter_destroy(void* engine);

// Returns a voice/sample handle (int >=0) or negative on error
int   soloud_flutter_load(void* engine, const char* path);
void  soloud_flutter_play(void* engine, int handle);
void  soloud_flutter_pause(void* engine, int handle);
void  soloud_flutter_stop(void* engine, int handle);
void  soloud_flutter_set_global_volume(void* engine, float volume);
void  soloud_flutter_set_looping(void* engine, int handle, int looping);
void  soloud_flutter_seek(void* engine, int handle, double seconds);
double soloud_flutter_position(void* engine, int handle);
double soloud_flutter_duration(void* engine, int handle);
void  soloud_flutter_set_clip(void* engine, int handle, double startSec, double endSec);

// Set relative playback speed for a voice (1.0 = normal)
void  soloud_flutter_set_speed(void* engine, int handle, float speed);

#ifdef __cplusplus
}
#endif