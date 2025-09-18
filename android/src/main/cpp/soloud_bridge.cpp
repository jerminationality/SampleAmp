// Real SoLoud integration layer (basic subset) - replace/extend as needed.
#include "soloud_bridge.h"
#include "soloud/include/soloud.h"
#include "soloud/include/soloud_wav.h"
#include <unordered_map>
#include <memory>
#if defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "SoLoudFlutter"
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define ALOGI(...)
#define ALOGW(...)
#define ALOGE(...)
#endif

struct VoiceWrap {
	std::unique_ptr<SoLoud::Wav> wav;
	SoLoud::handle handle = 0;
	double clipStart = 0.0;
	double clipEnd = -1.0; // -1 => full length
	bool hasPendingSeek = false;
	double pendingSeekSeconds = 0.0;
	bool shouldLoop = false;
};

struct EngineWrap {
	SoLoud::Soloud soloud;
	int nextId = 1;
	std::unordered_map<int, VoiceWrap> voices; // id -> voice
};

extern "C" {
void* soloud_flutter_create() {
	auto* e = new EngineWrap();
	// Prefer low-latency init params (SoLoud will clamp as needed)
	unsigned int flags = SoLoud::Soloud::CLIP_ROUNDOFF;
	unsigned int samplerate = 48000;
	unsigned int bufferSize = 2048; // stability on emulator; tweak on devices
	unsigned int channels = 2;
	if (e->soloud.init(flags, SoLoud::Soloud::MINIAUDIO, samplerate, bufferSize, channels) != 0) {
		ALOGE("init failed: backend=miniaudio sr=%u buf=%u ch=%u", samplerate, bufferSize, channels);
		delete e;
		return nullptr;
	}
	e->soloud.setGlobalVolume(1.0f);
	ALOGI("init ok: backend=%u '%s' sr=%u buf=%u ch=%u",
		e->soloud.getBackendId(), e->soloud.getBackendString() ? e->soloud.getBackendString() : "",
		e->soloud.getBackendSamplerate(), e->soloud.getBackendBufferSize(), e->soloud.getBackendChannels());
	return e;
}

void soloud_flutter_destroy(void* engine) {
	if (!engine) return;
	auto* e = static_cast<EngineWrap*>(engine);
	e->soloud.deinit();
	delete e;
}

int soloud_flutter_load(void* engine, const char* path) {
	if (!engine || !path) return -1;
	auto* e = static_cast<EngineWrap*>(engine);
	VoiceWrap vw;
	vw.wav = std::make_unique<SoLoud::Wav>();
	if (vw.wav->load(path) != 0) {
		ALOGE("load failed: %s", path);
		return -1;
	}
	vw.wav->setLooping(false);
	vw.wav->setSingleInstance(false);
	int id = e->nextId++;
	e->voices[id] = std::move(vw);
	ALOGI("load ok: id=%d path=%s len=%.3fs", id, path, e->voices[id].wav ? e->voices[id].wav->getLength() : -1.0);
	return id;
}

void soloud_flutter_play(void* engine, int id) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	auto& v = it->second;
	if (v.wav) {
		v.wav->setLooping(v.shouldLoop);
		v.handle = e->soloud.play(*v.wav);
		if (v.shouldLoop) {
			e->soloud.setLooping(v.handle, 1);
		} else {
			e->soloud.setLooping(v.handle, 0);
		}
		// Apply any pending seek immediately after voice creation
		if (v.hasPendingSeek) {
			e->soloud.seek(v.handle, v.pendingSeekSeconds);
			v.hasPendingSeek = false;
		} else if (v.clipStart > 0) {
			e->soloud.seek(v.handle, v.clipStart);
		}
		// Ensure current relative speed (if previously set) is applied
		// Default to 1.0; callers should set speed through the bridge when needed
		ALOGI("play: id=%d handle=%d pos=%.3f clip[%.3f,%.3f]", id, (int)v.handle,
			  e->soloud.getStreamTime(v.handle), v.clipStart, v.clipEnd);
	}
}

void soloud_flutter_pause(void* engine, int id) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	e->soloud.setPause(it->second.handle, 1);
	ALOGI("pause: id=%d handle=%d pos=%.3f", id, (int)it->second.handle, e->soloud.getStreamTime(it->second.handle));
}

void soloud_flutter_stop(void* engine, int id) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	e->soloud.stop(it->second.handle);
	it->second.handle = 0;
	ALOGI("stop: id=%d handle=%d", id, (int)it->second.handle);
}

void soloud_flutter_set_global_volume(void* engine, float volume) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	e->soloud.setGlobalVolume(volume);
}

void soloud_flutter_set_looping(void* engine, int id, int looping) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	auto &v = it->second;
	v.shouldLoop = looping != 0;
	if (v.wav) { v.wav->setLooping(v.shouldLoop); }
	if (e->soloud.isValidVoiceHandle(v.handle)) { e->soloud.setLooping(v.handle, v.shouldLoop ? 1 : 0); }
	ALOGI("loop: id=%d handle=%d looping=%d", id, (int)v.handle, looping);
}

void soloud_flutter_seek(void* engine, int id, double seconds) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	auto& v = it->second;
	if (v.handle == 0 || !e->soloud.isValidVoiceHandle(v.handle)) {
		// Voice not yet created; record pending seek to apply on play
		v.hasPendingSeek = true;
		v.pendingSeekSeconds = seconds;
		ALOGI("seek (pending): id=%d t=%.3f", id, seconds);
	} else {
		e->soloud.seek(v.handle, seconds);
		ALOGI("seek: id=%d handle=%d t=%.3f", id, (int)v.handle, seconds);
	}
}

double soloud_flutter_position(void* engine, int id) {
	if (!engine) return 0; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return 0;
	return e->soloud.getStreamTime(it->second.handle);
}

double soloud_flutter_duration(void* engine, int id) {
	if (!engine) return 0; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end() || !it->second.wav) return 0;
	return it->second.wav->getLength();
}

void soloud_flutter_set_clip(void* engine, int id, double startSec, double endSec) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	it->second.clipStart = startSec < 0 ? 0 : startSec;
	it->second.clipEnd = endSec;
	// Simple enforcement: if currently playing and position is before start or beyond end, seek to start
	if (e->soloud.isValidVoiceHandle(it->second.handle)) {
		double pos = e->soloud.getStreamTime(it->second.handle);
		if (pos < it->second.clipStart || (it->second.clipEnd > 0 && pos > it->second.clipEnd)) {
			e->soloud.seek(it->second.handle, it->second.clipStart);
		}
		ALOGI("clip: id=%d start=%.3f end=%.3f pos=%.3f", id, it->second.clipStart, it->second.clipEnd, pos);
	} else {
		ALOGI("clip (deferred): id=%d start=%.3f end=%.3f pos=0.0", id, it->second.clipStart, it->second.clipEnd);
	}
}

void soloud_flutter_set_speed(void* engine, int id, float speed) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	if (e->soloud.isValidVoiceHandle(it->second.handle)) {
		e->soloud.setRelativePlaySpeed(it->second.handle, speed <= 0.f ? 1.f : speed);
	}
	ALOGI("speed: id=%d handle=%d speed=%.3f", id, (int)it->second.handle, speed);
}
}
