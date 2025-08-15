// Utility functions for the audio sampler app

String formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final minutes = twoDigits(duration.inMinutes.remainder(60));
  final seconds = twoDigits(duration.inSeconds.remainder(60));
  final centiseconds = twoDigits((duration.inMilliseconds ~/ 10) % 100);
  return '$minutes:$seconds:$centiseconds';
} 