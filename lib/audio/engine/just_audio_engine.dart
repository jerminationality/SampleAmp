import 'package:just_audio/just_audio.dart' as ja;
import 'package:just_audio/just_audio.dart' show AudioSource, ClippingAudioSource;
import 'package:live_audio_sampler/audio/engine/engine_types.dart';

class JustAudioEngine implements AudioEngine {
  final ja.AudioPlayer _player = ja.AudioPlayer();
  dynamic _dspGraph; // placeholder reference
  // Expose for debugging (avoid unused warning)
  dynamic get debugDspGraph => _dspGraph;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {
    await _player.dispose();
  }

  Uri _toUri(String path) {
    final lower = path.toLowerCase();
    if (lower.startsWith('content://') || lower.startsWith('file://') || lower.startsWith('http://') || lower.startsWith('https://')) {
      return Uri.parse(path);
    }
    return Uri.file(path);
  }

  @override
  Future<void> load(String path, {Duration start = Duration.zero, Duration? end}) async {
    AudioSource src;
    if (start > Duration.zero || (end != null && end > Duration.zero)) {
      src = ClippingAudioSource(child: AudioSource.uri(_toUri(path)), start: start, end: end);
    } else {
      src = AudioSource.uri(_toUri(path));
    }
    await _player.setAudioSource(src);
  // Note: for JA backend, clip start is encoded in the source; nothing else to track.
  }

  @override
  Future<void> play() async => _player.play();

  @override
  Future<void> pause() async => _player.pause();

  @override
  Future<void> stop() async => _player.stop();

  @override
  Future<void> seek(Duration position) async => _player.seek(position);

  @override
  Future<void> setLooping(bool looping) async => _player.setLoopMode(looping ? ja.LoopMode.one : ja.LoopMode.off);

  @override
  Future<void> setSpeed(double speed) async => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) async => _player.setVolume(volume);

  @override
  Future<Duration> position() async => _player.position;

  @override
  Future<Duration> duration() async => _player.duration ?? Duration.zero;

  // Extra: expose player for advanced operations if needed via provider cast.
  ja.AudioPlayer get rawPlayer => _player;

  @override
  Future<void> setClip({Duration? start, Duration? end}) async {
    await _player.setClip(start: start, end: end);
  }

  @override
  bool get supportsDsp => false; // just_audio path has no raw PCM tap here

  @override
  Future<void> setDspGraph(dynamic graph) async {
    _dspGraph = graph; // stored for potential future custom source integration
  }

  @override
  Future<void> processOffline(dynamic graph, String inputPath, String outputPath) async {
    // Not supported in just_audio shim.
    throw UnimplementedError('Offline DSP not supported for JustAudioEngine');
  }
}
