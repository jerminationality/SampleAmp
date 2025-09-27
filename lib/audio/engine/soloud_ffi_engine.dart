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
      final h = SoLoudFfi.instance.load(engine, cPath.cast());
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

  @override
  Future<void> play() async {
    if (_currentHandle != null) {
      final engine = _requireEngine();
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
    final engine = _requireEngine();
    SoLoudFfi.instance.setGlobalVolume(engine, volume.toDouble());
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
    if (_currentHandle != null) {
      final engine = _requireEngine();
      final sec = SoLoudFfi.instance.position(engine, _currentHandle!);
      _position = Duration(milliseconds: (sec * 1000).round());
    }
    return _position;
  }

  @override
  Future<Duration> duration() async {
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







