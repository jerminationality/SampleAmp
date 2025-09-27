abstract class AudioEngine {
  Future<void> init();
  Future<void> dispose();

  Future<void> load(
    String path, {
    Duration start = Duration.zero,
    Duration? end,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);

  Future<void> setVolume(double volume); // 0..1
  Future<void> setSpeed(double speed); // 0.5..2.0
  Future<void> setLooping(bool looping);

  // Optional: Define a clip window within the currently loaded source.
  // Implementations that cannot clip should still accept nulls to clear any window.
  Future<void> setClip({Duration? start, Duration? end});

  Future<Duration> position();
  Future<Duration> duration();

  /// Whether the engine requires a startup volume ramp to avoid pops.
  bool get needsStartupRamp => true;

  // --- Optional DSP support hooks ---
  // Engines that can process raw PCM can override these. Default is no-op.
  bool get supportsDsp => false;
  Future<void> setDspGraph(dynamic graph) async {}
  // Optional offline processing utility (e.g., render with DSP to new file)
  Future<void> processOffline(dynamic graph, String inputPath, String outputPath) async {
    throw UnimplementedError('Offline DSP not supported by this engine');
  }
}
