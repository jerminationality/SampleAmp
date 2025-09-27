import 'package:just_audio/just_audio.dart' as ja;
import 'package:live_audio_sampler/audio/engine/engine_types.dart';

/// Minimal SoLoud FFI scaffold. Functions are placeholders until native libs are added.
class SoLoudEngine implements AudioEngine {
  @override
  bool get needsStartupRamp => true;
  // Placeholder for future FFI lib; not required while delegating to just_audio
  bool _initialized = false;
  final ja.AudioPlayer _player = ja.AudioPlayer();
  dynamic _dspGraph; // placeholder until real SoLoud FFI added
  dynamic get debugDspGraph => _dspGraph; // avoid unused warning

  @override
  Future<void> init() async {
    if (_initialized) return;
  _initialized = true; // allow JA delegate path
  }

  @override
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } finally {
      _initialized = false;
    }
  }

  @override
  Future<void> load(String path, {Duration start = Duration.zero, Duration? end}) async {
    final lower = path.toLowerCase();
    Uri uri;
    if (lower.startsWith('content://') || lower.startsWith('file://') || lower.startsWith('http://') || lower.startsWith('https://')) {
      uri = Uri.parse(path);
    } else {
      uri = Uri.file(path);
    }
    ja.AudioSource src;
    if (start > Duration.zero || (end != null && end > Duration.zero)) {
      src = ja.ClippingAudioSource(child: ja.AudioSource.uri(uri), start: start, end: end);
    } else {
      src = ja.AudioSource.uri(uri);
    }
    await _player.setAudioSource(src);
  }

  @override
  Future<void> play() async { await _player.play(); }

  @override
  Future<void> pause() async { await _player.pause(); }

  @override
  Future<void> stop() async { await _player.stop(); }

  @override
  Future<void> seek(Duration position) async { await _player.seek(position); }

  @override
  Future<void> setLooping(bool looping) async {
    await _player.setLoopMode(looping ? ja.LoopMode.one : ja.LoopMode.off);
  }

  @override
  Future<void> setSpeed(double speed) async { await _player.setSpeed(speed); }

  @override
  Future<void> setVolume(double volume) async { await _player.setVolume(volume); }

  @override
  Future<Duration> position() async => _player.position;

  @override
  Future<Duration> duration() async => _player.duration ?? Duration.zero;

  // Native lib loading will be added when integrating real SoLoud FFI.

  // Expose underlying JA player for advanced operations (e.g., setClip)
  ja.AudioPlayer get rawPlayer => _player;

  @override
  Future<void> setClip({Duration? start, Duration? end}) async {
    await _player.setClip(start: start, end: end);
  }

  @override
  bool get supportsDsp => false; // will be true once native buffer hook exists

  @override
  Future<void> setDspGraph(dynamic graph) async {
    _dspGraph = graph; // stored; not processed yet
  }

  @override
  Future<void> processOffline(dynamic graph, String inputPath, String outputPath) async {
    throw UnimplementedError('Offline DSP not supported yet for SoLoudEngine placeholder');
  }
}
