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

namespace {
constexpr float kFadeInSeconds = 0.012f;
constexpr float kFadeOutSeconds = 0.012f;
constexpr float kTargetVoiceVolume = 1.0f;

inline void fadeInVoice(SoLoud::Soloud& soloud, SoLoud::handle handle) {
	if (!soloud.isValidVoiceHandle(handle)) return;
	soloud.setVolume(handle, 0.0f);
	soloud.fadeVolume(handle, kTargetVoiceVolume, kFadeInSeconds);
}

inline void fadeOutVoiceAndStop(SoLoud::Soloud& soloud, SoLoud::handle handle) {
	if (!soloud.isValidVoiceHandle(handle)) return;
	soloud.fadeVolume(handle, 0.0f, kFadeOutSeconds);
	soloud.scheduleStop(handle, kFadeOutSeconds);
}

inline void fadeOutVoiceAndPause(SoLoud::Soloud& soloud, SoLoud::handle handle) {
	if (!soloud.isValidVoiceHandle(handle)) return;
	soloud.fadeVolume(handle, 0.0f, kFadeOutSeconds);
	soloud.schedulePause(handle, kFadeOutSeconds);
}

inline void smoothSeek(SoLoud::Soloud& soloud, SoLoud::handle handle, double seconds) {
	if (!soloud.isValidVoiceHandle(handle)) return;
	soloud.setPause(handle, 1);
	soloud.setVolume(handle, 0.0f);
	soloud.seek(handle, seconds);
	soloud.setPause(handle, 0);
	soloud.fadeVolume(handle, kTargetVoiceVolume, kFadeInSeconds);
}
} // namespace
struct VoiceWrap {
	std::unique_ptr<SoLoud::Wav> wav;
	SoLoud::handle handle = 0;
	double clipStart = 0.0;
	double clipEnd = -1.0; // -1 => full length
	bool hasPendingSeek = false;
	double pendingSeekSeconds = 0.0;
	bool shouldLoop = false;
	bool endFadeScheduled = false;
};

struct EngineWrap {
	SoLoud::Soloud soloud;
	int nextId = 1;
	std::unordered_map<int, VoiceWrap> voices; // id -> voice
};

extern "C" {
void* soloud_flutter_create() {
	auto* e = new EngineWrap();
	unsigned int flags = SoLoud::Soloud::CLIP_ROUNDOFF;
	unsigned int samplerate = SoLoud::Soloud::AUTO;
	unsigned int bufferSize = SoLoud::Soloud::AUTO;
	unsigned int channels = 2;
	unsigned int backend = SoLoud::Soloud::MINIAUDIO;
	int result = e->soloud.init(flags, backend, samplerate, bufferSize, channels);
	if (result != 0) {
		ALOGW("init failed with requested MiniAudio backend (%d); retrying auto", result);
		backend = SoLoud::Soloud::AUTO;
		result = e->soloud.init(flags, backend, samplerate, bufferSize, channels);
		if (result != 0) {
			ALOGE("init failed even with auto backend (%d)", result);
			delete e;
			return nullptr;
		}
	}
	e->soloud.setGlobalVolume(1.0f);
	ALOGI("init ok: backend=%u '%s' sr=%u buf=%u ch=%u",
		e->soloud.getBackendId(),
		e->soloud.getBackendString() ? e->soloud.getBackendString() : "",
		e->soloud.getBackendSamplerate(),
		e->soloud.getBackendBufferSize(),
		e->soloud.getBackendChannels());
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
	vw.wav->setLooping(false);
	vw.wav->setSingleInstance(false);
	if (vw.wav->load(path) != 0) {
		ALOGE("load failed: %s", path);
		return -1;
	}
	int id = e->nextId++;
	e->voices[id] = std::move(vw);
	e->voices[id].endFadeScheduled = false;
	ALOGI("load ok: id=%d path=%s len=%.3fs", id, path, e->voices[id].wav ? e->voices[id].wav->getLength() : -1.0);
	return id;
}

void soloud_flutter_play(void* engine, int id) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	auto& v = it->second;
	if (v.wav) {
		v.endFadeScheduled = false;
		v.handle = e->soloud.play(*v.wav);
		v.wav->setLooping(v.shouldLoop);
		e->soloud.setLooping(v.handle, v.shouldLoop ? 1 : 0);
		if (v.hasPendingSeek) {
			smoothSeek(e->soloud, v.handle, v.pendingSeekSeconds);
			v.hasPendingSeek = false;
		} else if (v.clipStart > 0.0) {
			smoothSeek(e->soloud, v.handle, v.clipStart);
		} else {
			fadeInVoice(e->soloud, v.handle);
		}
		ALOGI("play: id=%d handle=%d pos=%.3f clip[%.3f,%.3f]", id, (int)v.handle,
			  e->soloud.getStreamTime(v.handle), v.clipStart, v.clipEnd);
	}
}

void soloud_flutter_pause(void* engine, int id) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	auto& v = it->second;
	if (e->soloud.isValidVoiceHandle(v.handle)) {
		fadeOutVoiceAndPause(e->soloud, v.handle);
	} else {
		e->soloud.setPause(v.handle, 1);
	}
	v.endFadeScheduled = false;
	ALOGI("pause: id=%d handle=%d pos=%.3f", id, (int)v.handle, e->soloud.getStreamTime(v.handle));
}

void soloud_flutter_stop(void* engine, int id) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	auto& v = it->second;
	const auto handle = v.handle;
	if (e->soloud.isValidVoiceHandle(handle)) {
		fadeOutVoiceAndStop(e->soloud, handle);
	} else {
		e->soloud.stop(handle);
	}
	v.endFadeScheduled = false;
	v.handle = 0;
	ALOGI("stop: id=%d handle=%d", id, (int)handle);
}

void soloud_flutter_set_global_volume(void* engine, float volume) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	e->soloud.setGlobalVolume(volume);
}

void soloud_flutter_set_looping(void* engine, int id, int looping) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	auto& v = it->second;
	v.shouldLoop = looping != 0;
	if (v.wav) {
		v.wav->setLooping(v.shouldLoop);
	}
	if (e->soloud.isValidVoiceHandle(v.handle)) {
		e->soloud.setLooping(v.handle, v.shouldLoop ? 1 : 0);
	}
	ALOGI("loop: id=%d handle=%d looping=%d", id, (int)v.handle, looping);
}
void soloud_flutter_seek(void* engine, int id, double seconds) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	auto& v = it->second;
	if (v.handle == 0 || !e->soloud.isValidVoiceHandle(v.handle)) {
		v.hasPendingSeek = true;
		v.pendingSeekSeconds = seconds;
		ALOGI("seek (pending): id=%d t=%.3f", id, seconds);
	} else {
		v.endFadeScheduled = false;
		smoothSeek(e->soloud, v.handle, seconds);
		ALOGI("seek: id=%d handle=%d t=%.3f", id, (int)v.handle, seconds);
	}
}

double soloud_flutter_position(void* engine, int id) {
	if (!engine) return 0; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return 0;
	auto& v = it->second;
	double pos = e->soloud.getStreamTime(v.handle);
	if (v.clipEnd > 0 && pos >= v.clipEnd) {
		if (!v.endFadeScheduled && e->soloud.isValidVoiceHandle(v.handle)) {
			const auto handle = v.handle;
			fadeOutVoiceAndStop(e->soloud, handle);
			v.endFadeScheduled = true;
			v.handle = 0;
		}
		return v.clipEnd;
	}
	return pos;
}

double soloud_flutter_duration(void* engine, int id) {
	if (!engine) return 0; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end() || !it->second.wav) return 0;
	return it->second.wav->getLength();
}

void soloud_flutter_set_clip(void* engine, int id, double startSec, double endSec) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	auto& v = it->second;
	v.clipStart = startSec < 0 ? 0 : startSec;
	v.clipEnd = endSec;
	v.endFadeScheduled = false;
	double pos = 0.0;
	if (e->soloud.isValidVoiceHandle(v.handle)) {
		pos = e->soloud.getStreamTime(v.handle);
		if (pos < v.clipStart || (v.clipEnd > 0 && pos > v.clipEnd)) {
			smoothSeek(e->soloud, v.handle, v.clipStart);
		}
	}
	ALOGI("clip: id=%d start=%.3f end=%.3f pos=%.3f", id, v.clipStart, v.clipEnd, pos);
}
void soloud_flutter_set_speed(void* engine, int id, float speed) {
	if (!engine) return; auto* e = static_cast<EngineWrap*>(engine);
	auto it = e->voices.find(id); if (it == e->voices.end()) return;
	if (e->soloud.isValidVoiceHandle(it->second.handle)) {
		e->soloud.setRelativePlaySpeed(it->second.handle, speed <= 0.f ? 1.f : speed);
	}
	ALOGI("speed: id=%d handle=%d speed=%.3f", id, (int)it->second.handle, speed);
}

unsigned int soloud_flutter_backend_id(void* engine) {
	if (!engine) return 0;
	auto* e = static_cast<EngineWrap*>(engine);
	return e->soloud.getBackendId();
}

const char* soloud_flutter_backend_string(void* engine) {
	if (!engine) return "";
	auto* e = static_cast<EngineWrap*>(engine);
	const char* backend = e->soloud.getBackendString();
	return backend ? backend : "";
}

unsigned int soloud_flutter_backend_samplerate(void* engine) {
	if (!engine) return 0;
	auto* e = static_cast<EngineWrap*>(engine);
	return e->soloud.getBackendSamplerate();
}

unsigned int soloud_flutter_backend_buffer_size(void* engine) {
	if (!engine) return 0;
	auto* e = static_cast<EngineWrap*>(engine);
	return e->soloud.getBackendBufferSize();
}

unsigned int soloud_flutter_backend_channels(void* engine) {
	if (!engine) return 0;
	auto* e = static_cast<EngineWrap*>(engine);
	return e->soloud.getBackendChannels();
}
}











