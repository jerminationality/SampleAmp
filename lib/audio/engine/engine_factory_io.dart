import 'engine_types.dart';
import 'soloud_ffi_engine.dart';

AudioEngine createAudioEngine() {
	// Try FFI engine first for lowest latency; fallback to shim if unavailable
	final engine = SoLoudFfiEngine();
	return engine; // init() will throw if lib missing; provider can catch and fallback later if desired
}
