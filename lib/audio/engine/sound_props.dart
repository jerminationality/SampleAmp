class SoundProps {
  final String path;
  final int handle;
  final Duration? clipStart;
  final Duration? clipEnd;
  final double speed;
  final bool looping;
  final double gainDb;
  final Duration duration;

  const SoundProps({
    required this.path,
    required this.handle,
    this.clipStart,
    this.clipEnd,
    this.speed = 1.0,
    this.looping = false,
    this.gainDb = 0.0,
    this.duration = Duration.zero,
  });

  SoundProps copyWith({
    String? path,
    int? handle,
    Duration? clipStart,
    Duration? clipEnd,
    double? speed,
    bool? looping,
    double? gainDb,
    Duration? duration,
  }) => SoundProps(
        path: path ?? this.path,
        handle: handle ?? this.handle,
        clipStart: clipStart ?? this.clipStart,
        clipEnd: clipEnd ?? this.clipEnd,
        speed: speed ?? this.speed,
        looping: looping ?? this.looping,
        gainDb: gainDb ?? this.gainDb,
        duration: duration ?? this.duration,
      );
}
