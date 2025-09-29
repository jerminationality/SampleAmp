import 'engine_types.dart';
import 'soloud_ffi_engine.dart';

AudioEngine createAudioEngine() {
	// Always use SoLoud FFI engine for lowest latency.
	// ignore: avoid_print
	print('[EngineFactory] Using SoLoudFfiEngine');
	return SoLoudFfiEngine();
}
