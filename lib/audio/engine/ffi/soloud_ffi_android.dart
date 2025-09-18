import 'dart:ffi' as ffi;

// Android specific JNI bridging via DynamicLibrary for placeholder symbols
class SoLoudAndroidBridge {
  static SoLoudAndroidBridge? _instance;
  final ffi.DynamicLibrary _lib;

  SoLoudAndroidBridge._(this._lib);

  static SoLoudAndroidBridge get instance {
    return _instance ??= SoLoudAndroidBridge._(ffi.DynamicLibrary.process());
  }

  late final _nativeCreate = _lib.lookupFunction<ffi.Pointer<ffi.Void> Function(), ffi.Pointer<ffi.Void> Function()>('Java_com_example_live_1audio_1sampler_SoLoudBridge_nativeCreate');
  late final _nativeDestroy = _lib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>), void Function(ffi.Pointer<ffi.Void>)>('Java_com_example_live_1audio_1sampler_SoLoudBridge_nativeDestroy');

  ffi.Pointer<ffi.Void> create() => _nativeCreate();
  void destroy(ffi.Pointer<ffi.Void> ptr) => _nativeDestroy(ptr);
}
