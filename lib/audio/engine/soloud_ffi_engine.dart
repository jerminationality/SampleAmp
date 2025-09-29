import 'dart:ffi' as ffi;

import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:live_audio_sampler/audio/engine/engine_types.dart';

import 'ffi/soloud_ffi_bindings.dart';

/// Experimental SoLoud FFI engine aiming for lowest latency + DSP hook.
/// Currently a scaffold; real native library symbols must exist for functionality.
class SoLoudFfiEngine implements AudioEngine {
  bool _initialized = false;
  ffi.Pointer<ffi.Void>? _soloud;
  int? _currentHandle;
  // Simple in-memory cache of loaded sounds (handles) per absolute path
  final Map<String, int> _cache = <String, int>{};
  Map<String, int> get debugCache => Map.unmodifiable(_cache);
  bool _playing = false;
  Duration _position = Duration.zero; // Placeholder until native time query added
  Duration _duration = Duration.zero; // Updated after load (TODO query)
  bool _looping = false;
  double _speed = 1.0;
  double _volume = 1.0;
  dynamic _dspGraph; // Dart-side reference

  bool get debugPlaying => _playing;
  bool get debugLooping => _looping;
  double get debugSpeed => _speed;
  double get debugVolume => _volume;
  dynamic get debugGraph => _dspGraph;
  int? _backendId;
  String? _backendName;
  int? _backendSamplerate;
  int? _backendBufferSize;
  int? _backendChannels;

  int? get debugBackendId => _backendId;
  String? get debugBackendName => _backendName;
  int? get debugBackendSamplerate => _backendSamplerate;
  int? get debugBackendBufferSize => _backendBufferSize;
  int? get debugBackendChannels => _backendChannels;

  @override
  bool get supportsDsp => true; // Native mixer will allow future DSP integration

  @override
  bool get needsStartupRamp => false;

  ffi.Pointer<ffi.Void> _requireEngine() {
    final ptr = _soloud;
    if (!_initialized || ptr == null || ptr == ffi.nullptr) {
      throw StateError('SoLoud engine not initialized');
    }
    return ptr;
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    try {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SoLoudFfiEngine] attempting native init');
      }
      final ptr = SoLoudFfi.instance.create();
      if (ptr == ffi.nullptr) {
        throw StateError('SoLoud native create returned null');
      }
      _soloud = ptr;
      _backendId = SoLoudFfi.instance.backendId(ptr);
      final backendPtr = SoLoudFfi.instance.backendString(ptr);
      _backendName = backendPtr == ffi.nullptr ? null : backendPtr.cast<Utf8>().toDartString();
      _backendSamplerate = SoLoudFfi.instance.backendSamplerate(ptr);
      _backendBufferSize = SoLoudFfi.instance.backendBufferSize(ptr);
      _backendChannels = SoLoudFfi.instance.backendChannels(ptr);
      _initialized = true;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SoLoudFfiEngine] init ok backend=${_backendName ?? 'unknown'} (id=${_backendId ?? -1}) sr=${_backendSamplerate ?? 0} buf=${_backendBufferSize ?? 0} ch=${_backendChannels ?? 0}');
      }
    } catch (e, stack) {
      _soloud = null;
      _backendId = null;
      _backendName = null;
      _backendSamplerate = null;
      _backendBufferSize = null;
      _backendChannels = null;
      _initialized = false;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SoLoudFfiEngine] init failed: $e');
        // ignore: avoid_print
        print(stack);
      }
      throw StateError('SoLoud FFI init failed: $e');
    }

  }
  @override
  Future<void> dispose() async {
    try {
      // No explicit free-sound API available in current bindings; if added, iterate _cache here
      _cache.clear();
      if (_soloud != null) {
        SoLoudFfi.instance.destroy(_soloud!);
      }
    } finally {
      _soloud = null;
      _currentHandle = null;
      _initialized = false;
      _playing = false;
      _backendId = null;
      _backendName = null;
      _backendSamplerate = null;
      _backendBufferSize = null;
      _backendChannels = null;
    }
  }

  @override
  Future<void> load(String path, {Duration start = Duration.zero, Duration? end}) async {
    if (!_initialized) throw StateError('Engine not initialized');
    final engine = _requireEngine();
    final cPath = path.toNativeUtf8();
    try {
      int h;
      if (_cache.containsKey(path)) {
        h = _cache[path]!;
      } else {
        h = SoLoudFfi.instance.load(engine, cPath.cast());
        if (h >= 0) _cache[path] = h;
      }
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SoLoudFfiEngine] load request: $path');
      }
      if (h < 0) throw StateError('Native load failed');
      _currentHandle = h;
      _position = start;
      _duration = const Duration(minutes: 5); // Until native duration implemented
      // Apply current speed to the newly loaded voice
      if (_currentHandle != null) {
        try {
          SoLoudFfi.instance.setSpeed(engine, _currentHandle!, _speed);
        } catch (_) {}
      }
    } finally {
      malloc.free(cPath);
    }
  }

  // Helper to release a single cached sound if we expose such API in future
  void releaseCached(String path) {
    _cache.remove(path);
  }

  // Public helper to ensure a path is preloaded and return its handle.
  Future<int> preload(String path) async {
    if (!_initialized) await init();
    if (_cache.containsKey(path)) return _cache[path]!;
    await load(path);
    return _cache[path] ?? _currentHandle ?? -1;
  }

  // Public helper to play a specific cached handle without changing clip/seek.
  Future<void> playHandle(int handle) async {
    final engine = _requireEngine();
    SoLoudFfi.instance.play(engine, handle);
    _playing = true;
  }

  // Convenience: ensure cached by path and trigger.
  Future<void> playCached(String path) async {
    final h = await preload(path);
    if (h >= 0) await playHandle(h);
  }

  @override
  Future<void> play() async {
    if (_currentHandle != null) {
      final engine = _requireEngine();
      // Ensure only one instance of this sound is active: stop any existing voices for this handle
      try {
        SoLoudFfi.instance.stop(engine, _currentHandle!);
      } catch (_) {}
      SoLoudFfi.instance.play(engine, _currentHandle!);
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SoLoudFfiEngine] play handle=${_currentHandle!}');
      }
      _playing = true;
    }
  }

  @override
  Future<void> pause() async {
    if (_currentHandle != null) {
      final engine = _requireEngine();
      SoLoudFfi.instance.pause(engine, _currentHandle!);
      _playing = false;
    }
  }

  @override
  Future<void> stop() async {
    if (_currentHandle != null && _playing) {
      final engine = _requireEngine();
      SoLoudFfi.instance.stop(engine, _currentHandle!);
    }
    _playing = false;
    _position = Duration.zero;
  }

  @override
  Future<void> seek(Duration position) async {
    if (_currentHandle != null) {
      final engine = _requireEngine();
      SoLoudFfi.instance.seek(engine, _currentHandle!, position.inMilliseconds / 1000.0);
      _position = position;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    if (!_initialized || _soloud == null) return;
    final engine = _requireEngine();
    final v = volume.isNaN || volume.isInfinite ? 1.0 : volume.clamp(0.0, 1.0);
    SoLoudFfi.instance.setGlobalVolume(engine, v.toDouble());
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (_currentHandle != null) {
      final engine = _requireEngine();
      SoLoudFfi.instance.setSpeed(engine, _currentHandle!, _speed);
    }
  }

  @override
  Future<void> setLooping(bool looping) async {
    _looping = looping;
    if (_currentHandle != null) {
      final engine = _requireEngine();
      SoLoudFfi.instance.setLooping(engine, _currentHandle!, looping ? 1 : 0);
    }
  }

  @override
  Future<void> setClip({Duration? start, Duration? end}) async {
    if (_currentHandle != null) {
      final engine = _requireEngine();
      final startSec = start?.inMilliseconds.toDouble() ?? 0.0;
      final endSec = end?.inMilliseconds.toDouble() ?? -1.0;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SoLoudFfiEngine] setClip start=$startSec, end=$endSec');
      }
      SoLoudFfi.instance.setClip(
        engine,
        _currentHandle!,
        startSec / 1000.0,
        endSec < 0 ? -1.0 : endSec / 1000.0,
      );
    }
  }

  @override
  Future<Duration> position() async {
    if (!_initialized || _soloud == null) return _position;
    if (_currentHandle != null) {
      final engine = _requireEngine();
      final sec = SoLoudFfi.instance.position(engine, _currentHandle!);
      _position = Duration(milliseconds: (sec * 1000).round());
    }
    return _position;
  }

  @override
  Future<Duration> duration() async {
    if (!_initialized || _soloud == null) return _duration;
    if (_currentHandle != null) {
      final engine = _requireEngine();
      final sec = SoLoudFfi.instance.duration(engine, _currentHandle!);
      _duration = Duration(milliseconds: (sec * 1000).round());
    }
    return _duration;
  }

  @override
  Future<void> setDspGraph(dynamic graph) async {
    _dspGraph = graph;
    // TODO: translate Dart graph params to native filters
  }

  @override
  Future<void> processOffline(dynamic graph, String inputPath, String outputPath) async {
    // TODO: Implement offline render with native engine
    throw UnimplementedError('Offline processing not yet implemented for SoLoudFfiEngine');
  }
}







