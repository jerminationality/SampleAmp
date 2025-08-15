import 'dart:io';
import 'dart:math';

class AudioSample {
  final String id;
  final String name;
  final String filePath;
  final Duration duration;
  final Duration startTime;
  final Duration endTime;
  final double volume;
  final double pitch;
  final double reverb;
  final double echo;
  final String category;
  final DateTime createdAt;
  final DateTime lastModified;
  final bool isFavorite;
  final String? notes;
  final bool isBlank;
  final int? customColor;
  final List<double>? waveformData;
  final double gainDb;

  AudioSample({
    required this.id,
    required this.name,
    required this.filePath,
    required this.duration,
    this.startTime = Duration.zero,
    this.endTime = Duration.zero,
    this.volume = 1.0,
    this.pitch = 1.0,
    this.reverb = 0.0,
    this.echo = 0.0,
    this.category = 'General',
    required this.createdAt,
    required this.lastModified,
    this.isFavorite = false,
    this.notes,
    this.isBlank = false,
    this.customColor,
    this.waveformData,
    this.gainDb = 0.0,
  });

  AudioSample copyWith({
    String? id,
    String? name,
    String? filePath,
    Duration? duration,
    Duration? startTime,
    Duration? endTime,
    double? volume,
    double? pitch,
    double? reverb,
    double? echo,
    String? category,
    DateTime? createdAt,
    DateTime? lastModified,
    bool? isFavorite,
    String? notes,
    bool? isBlank,
    int? customColor,
    List<double>? waveformData,
    double? gainDb,
  }) {
    return AudioSample(
      id: id ?? this.id,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      duration: duration ?? this.duration,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      volume: volume ?? this.volume,
      pitch: pitch ?? this.pitch,
      reverb: reverb ?? this.reverb,
      echo: echo ?? this.echo,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
      isFavorite: isFavorite ?? this.isFavorite,
      notes: notes ?? this.notes,
      isBlank: isBlank ?? this.isBlank,
      customColor: customColor ?? this.customColor,
      waveformData: waveformData ?? this.waveformData,
      gainDb: gainDb ?? this.gainDb,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'filePath': filePath,
      'duration': duration.inMilliseconds,
      'startTime': startTime.inMilliseconds,
      'endTime': endTime.inMilliseconds,
      'volume': volume,
      'pitch': pitch,
      'reverb': reverb,
      'echo': echo,
      'category': category,
      'createdAt': createdAt.toIso8601String(),
      'lastModified': lastModified.toIso8601String(),
      'isFavorite': isFavorite,
      'notes': notes,
      'isBlank': isBlank,
      'customColor': customColor,
      'waveformData': waveformData,
      'gainDb': gainDb,
    };
  }

  factory AudioSample.fromJson(Map<String, dynamic> json) {
    return AudioSample(
      id: json['id'],
      name: json['name'],
      filePath: json['filePath'],
      duration: Duration(milliseconds: json['duration']),
      startTime: Duration(milliseconds: json['startTime']),
      endTime: Duration(milliseconds: json['endTime']),
      volume: json['volume']?.toDouble() ?? 1.0,
      pitch: json['pitch']?.toDouble() ?? 1.0,
      reverb: json['reverb']?.toDouble() ?? 0.0,
      echo: json['echo']?.toDouble() ?? 0.0,
      category: json['category'] ?? 'General',
      createdAt: DateTime.parse(json['createdAt']),
      lastModified: DateTime.parse(json['lastModified']),
      isFavorite: json['isFavorite'] ?? false,
      notes: json['notes'],
      isBlank: json['isBlank'] ?? false,
      customColor: json['customColor'],
      waveformData: json['waveformData'] != null 
          ? List<double>.from(json['waveformData'])
          : null,
      gainDb: json['gainDb']?.toDouble() ?? 0.0,
    );
  }

  Duration get trimmedDuration {
    if (endTime > Duration.zero && endTime < duration) {
      return endTime - startTime;
    }
    return duration - startTime;
  }

  bool get isTrimmed => startTime > Duration.zero || (endTime > Duration.zero && endTime < duration);

  double get amplitude => pow(10.0, gainDb / 20.0).toDouble();
  
  /// Debug method to print gain information
  void debugGain() {
    final amp = amplitude;
    print('[AudioSample] Gain: ${gainDb.toStringAsFixed(1)} dB → Amplitude: ${amp.toStringAsFixed(6)}');
  }
} 