package com.example.live_audio_sampler

object SoLoudBridge {
    init {
        try { System.loadLibrary("soloud_flutter") } catch (_: Throwable) { }
    }

    external fun nativeCreate(): Long
    external fun nativeDestroy(ptr: Long)
}