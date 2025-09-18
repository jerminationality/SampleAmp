// Minimal placeholder FFI bindings for future SoLoud integration.
// This file defines the symbols we intend to bind. Real native library not yet present.

import 'dart:ffi' as ffi;
import 'dart:io';

ffi.DynamicLibrary _openLib() {
  if (Platform.isAndroid) return ffi.DynamicLibrary.open('libsoloud_flutter.so');
  if (Platform.isIOS) return ffi.DynamicLibrary.process(); // iOS static linking
  if (Platform.isMacOS) return ffi.DynamicLibrary.open('libsoloud.dylib');
  if (Platform.isWindows) return ffi.DynamicLibrary.open('soloud.dll');
  if (Platform.isLinux) return ffi.DynamicLibrary.open('libsoloud.so');
  return ffi.DynamicLibrary.process();
}

// Native signatures
typedef _create_native = ffi.Pointer<ffi.Void> Function();
typedef _destroy_native = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _load_native = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int8>);
typedef _play_native = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _pause_native = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _stop_native = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _set_volume_native = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Float);
typedef _set_loop_native = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32);
typedef _seek_native = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Double);
typedef _pos_native = ffi.Double Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _clip_native = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Double, ffi.Double);
typedef _set_speed_native = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);

// Dart types
typedef _destroy = void Function(ffi.Pointer<ffi.Void>);
typedef _load = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int8>);
typedef _play = void Function(ffi.Pointer<ffi.Void>, int);
typedef _pause = void Function(ffi.Pointer<ffi.Void>, int);
typedef _stop = void Function(ffi.Pointer<ffi.Void>, int);
typedef _set_volume = void Function(ffi.Pointer<ffi.Void>, double);
typedef _set_loop = void Function(ffi.Pointer<ffi.Void>, int, int);
typedef _seek = void Function(ffi.Pointer<ffi.Void>, int, double);
typedef _pos = double Function(ffi.Pointer<ffi.Void>, int);
typedef _clip = void Function(ffi.Pointer<ffi.Void>, int, double, double);
typedef _set_speed = void Function(ffi.Pointer<ffi.Void>, int, double);

class SoLoudFfi {
  SoLoudFfi._() {
    try {
      final lib = _openLib();
      _lib = lib;
      _createNative = lib.lookupFunction<_create_native, _create_native>('soloud_flutter_create');
      _destroyNative = lib.lookupFunction<_destroy_native, _destroy>('soloud_flutter_destroy');
      _loadNative = lib.lookupFunction<_load_native, _load>('soloud_flutter_load');
      _playNative = lib.lookupFunction<_play_native, _play>('soloud_flutter_play');
      _pauseNative = lib.lookupFunction<_pause_native, _pause>('soloud_flutter_pause');
      _stopNative = lib.lookupFunction<_stop_native, _stop>('soloud_flutter_stop');
      _setGlobalVolumeNative = lib.lookupFunction<_set_volume_native, _set_volume>('soloud_flutter_set_global_volume');
      _setLoopingNative = lib.lookupFunction<_set_loop_native, _set_loop>('soloud_flutter_set_looping');
      _seekNative = lib.lookupFunction<_seek_native, _seek>('soloud_flutter_seek');
      _positionNative = lib.lookupFunction<_pos_native, _pos>('soloud_flutter_position');
      _durationNative = lib.lookupFunction<_pos_native, _pos>('soloud_flutter_duration');
      _setClipNative = lib.lookupFunction<_clip_native, _clip>('soloud_flutter_set_clip');
      _setSpeedNative = lib.lookupFunction<_set_speed_native, _set_speed>('soloud_flutter_set_speed');
    } catch (error, _) {
      _loadError = error;
      _lib = null;
    }
  }

  static final SoLoudFfi instance = SoLoudFfi._();

  ffi.DynamicLibrary? _lib;
  Object? _loadError;

  late final _create_native _createNative;
  late final _destroy _destroyNative;
  late final _load _loadNative;
  late final _play _playNative;
  late final _pause _pauseNative;
  late final _stop _stopNative;
  late final _set_volume _setGlobalVolumeNative;
  late final _set_loop _setLoopingNative;
  late final _seek _seekNative;
  late final _pos _positionNative;
  late final _pos _durationNative;
  late final _clip _setClipNative;
  late final _set_speed _setSpeedNative;

  bool get isLoaded => _lib != null;
  Object? get loadError => _loadError;

  void _ensureLoaded() {
    if (_lib == null) {
      final details = _loadError == null ? '' : ' (${_loadError})';
      throw StateError('SoLoud native library unavailable$details');
    }
  }

  ffi.Pointer<ffi.Void> create() {
    _ensureLoaded();
    return _createNative();
  }

  void destroy(ffi.Pointer<ffi.Void> engine) {
    if (engine == ffi.nullptr) {
      return;
    }
    _ensureLoaded();
    _destroyNative(engine);
  }

  int load(ffi.Pointer<ffi.Void> engine, ffi.Pointer<ffi.Int8> path) {
    _ensureLoaded();
    return _loadNative(engine, path);
  }

  void play(ffi.Pointer<ffi.Void> engine, int handle) {
    _ensureLoaded();
    _playNative(engine, handle);
  }

  void pause(ffi.Pointer<ffi.Void> engine, int handle) {
    _ensureLoaded();
    _pauseNative(engine, handle);
  }

  void stop(ffi.Pointer<ffi.Void> engine, int handle) {
    _ensureLoaded();
    _stopNative(engine, handle);
  }

  void setGlobalVolume(ffi.Pointer<ffi.Void> engine, double volume) {
    _ensureLoaded();
    _setGlobalVolumeNative(engine, volume);
  }

  void setLooping(ffi.Pointer<ffi.Void> engine, int handle, int looping) {
    _ensureLoaded();
    _setLoopingNative(engine, handle, looping);
  }

  void seek(ffi.Pointer<ffi.Void> engine, int handle, double seconds) {
    _ensureLoaded();
    _seekNative(engine, handle, seconds);
  }

  double position(ffi.Pointer<ffi.Void> engine, int handle) {
    _ensureLoaded();
    return _positionNative(engine, handle);
  }

  double duration(ffi.Pointer<ffi.Void> engine, int handle) {
    _ensureLoaded();
    return _durationNative(engine, handle);
  }

  void setClip(ffi.Pointer<ffi.Void> engine, int handle, double start, double end) {
    _ensureLoaded();
    _setClipNative(engine, handle, start, end);
  }

  void setSpeed(ffi.Pointer<ffi.Void> engine, int handle, double speed) {
    _ensureLoaded();
    _setSpeedNative(engine, handle, speed);
  }
}
