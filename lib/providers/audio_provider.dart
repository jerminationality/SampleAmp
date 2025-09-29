import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:live_audio_sampler/models/audio_sample.dart';
import 'package:just_waveform/just_waveform.dart';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
// (removed) unused imports

import 'package:live_audio_sampler/audio/engine/engine_factory.dart';
import 'package:live_audio_sampler/audio/engine/engine_types.dart';
// import removed: no just_audio shim usage in SoLoud-only path
import 'package:live_audio_sampler/audio/engine/soloud_ffi_engine.dart';
import 'package:live_audio_sampler/audio/dsp/dsp_graph.dart';
import 'package:live_audio_sampler/audio/engine/sound_props.dart';

class AudioProvider with ChangeNotifier {
  // Singleton to avoid multiple engine instances
  static final AudioProvider _singleton = AudioProvider._();
  factory AudioProvider() => _singleton;
  AudioProvider._();

  AudioEngine? _engine; // lazy
  // No direct just_audio usage. Target backend is SoLoud; use engine APIs only.
  // No direct backend-specific player exposure on unified provider.
  dynamic get _ja => null; // placeholder for potential web-only streams later
  // Provide a little digital headroom to avoid intermittent clipping/pops on devices/emulators
  static const double _headroom = 0.8; // -1.94 dB approx
  // Optional DSP graph (software processing before final engine volume)
  DspGraph? _dspGraph;
  int _loadToken = 0; // prevent races between overlapping loads
  Timer? _pollTimer; // for non-just_audio engines
  Timer? _smoothPlayheadTimer; // 60 FPS timer for smooth UI updates
  AudioSample? _currentSample;
  AudioSample? _playingSample; // Track which sample is actually playing
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _lastNotifiedPosition = Duration.zero; // For throttling position updates
  // Deprecated: previously used for throttling; retained variables below
  // Master volume in 0.0..1.0 (we keep headroom for positive sample gain)
  double _volume = 1.0;
  double _pitch = 1.0;
  double _reverb = 0.0;
  double _echo = 0.0;
  // Stream subscriptions (unused with current abstraction)
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<dynamic>? _playerStateSubscription;
  // Baseline clip start/end in absolute file time when current source was loaded
  Duration _clipBaseStartAbs = Duration.zero;
  // Duration _clipBaseEndAbs removed (unused)
  // Visual-only latency compensation so UI playhead can match audible output latency
  Duration _latencyCompensation = Duration.zero;
  bool _sessionActive = false; // track audio focus activation
  bool _audibleStarted = false; // only advance playhead when audio actually started
  // During this window we avoid kicking off heavy I/O (e.g., waveform extraction)
  // right as playback starts to reduce contention on slower devices.
  DateTime _ioQuietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // Smooth playhead prediction: remember last engine tick and base position
  DateTime _lastEngineUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _baseEnginePosition = Duration.zero;
  DateTime _lastNotifyTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Debounce rapid trim changes (to avoid crackles when dragging)
  Timer? _trimDebounce;
  static const Duration _trimDebounceInterval = Duration(milliseconds: 80);
  Duration? _pendingTrimStartAbs;
  Duration? _pendingTrimEndAbs;

  AudioSample? get currentSample => _currentSample;
  AudioSample? get playingSample => _playingSample; // Getter for the sample that's actually playing
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  double get pitch => _pitch;
  double get reverb => _reverb;
  double get echo => _echo;
  Duration get latencyCompensation => _latencyCompensation;
  DspGraph? get dspGraph => _dspGraph;

  // kick off initialization lazily
  void ensureInitialized() {
    if (_engine == null) {
      _initializePlayer();
    }
  }

  /// Adjust visual latency compensation used by UI when rendering positions.
  /// This does not change actual playback timing; only display.
  void setLatencyCompensation(Duration value) {
    _latencyCompensation = value < Duration.zero ? Duration.zero : value;
    notifyListeners();
  }

  // Preload state
  final Map<String, SoundProps> _cachedSounds = <String, SoundProps>{};
  bool _isPreloading = false;
  bool get isPreloading => _isPreloading;

  Future<void> _initializePlayer() async {
    // Configure audio session (important on Android/iOS for playback)
    () async {
      try {
        final session = await AudioSession.instance;
        // Configure for media playback with speaker; stay active briefly when paused to reduce re-acquire
        await session.configure(const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
            flags: AndroidAudioFlags.none,
          ),
          androidWillPauseWhenDucked: false,
        ));
      } catch (e) {
        // Best-effort
      }
    }();
  // Init engine (no-op for JA backend)
  _engine ??= createAudioEngine();
  if (kDebugMode) {
    debugPrint('[AudioProvider] attempting engine init: ${_engine.runtimeType}');
  }
  try {
    await _engine!.init();
  } catch (e, stack) {
    // Hard fail; we only support SoLoud path now
    if (kDebugMode) {
      debugPrint('[AudioProvider] SoLoud engine init failed: ${e.runtimeType}: $e');
      debugPrint('$stack');
    }
    rethrow;
  }
  if (kDebugMode) {
    final engine = _engine;
    if (engine is SoLoudFfiEngine) {
      debugPrint('[AudioProvider] active audio engine=SoLoud backend=${engine.debugBackendName ?? 'unknown'} (id=${engine.debugBackendId ?? -1}) sr=${engine.debugBackendSamplerate ?? 0} buf=${engine.debugBackendBufferSize ?? 0} ch=${engine.debugBackendChannels ?? 0}');
    }
  }
  // Create default DSP graph if supported in future; currently always instantiate
  _dspGraph = DspGraph.basic(masterGain: 1.0, limiter: true);
  if (_engine!.supportsDsp) {
    try { await _engine!.setDspGraph(_dspGraph); } catch (_) {}
  }
  // Debug which engine is active
  // Using audio engine: ${_engine.runtimeType} (USE_SOLOUD=$kUseSoLoud)
    
    // Start smooth 60 FPS playhead timer for UI updates
    _startSmoothPlayheadTimer();
    
    // Poll engine for position/duration (common path for current engines)
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 75), (_) async {
      try {
        if (_engine == null) return;
        final pos = await _engine!.position();
        final dur = await _engine!.duration();
        _updatePosition(pos);
        _updateDuration(dur);
      } catch (_) {}
    });
  }

  // Preload all known non-blank samples to memory for instant playback
  Future<void> preloadAll(List<AudioSample> samples) async {
    if (_engine is! SoLoudFfiEngine) return;
    final ffiEngine = _engine as SoLoudFfiEngine;
    _isPreloading = true;
    notifyListeners();
    try {
      await Future.wait(samples.where((s) => !s.isBlank && s.filePath.isNotEmpty).map((s) async {
        final path = s.filePath;
        if (_cachedSounds.containsKey(path)) return;
        await ffiEngine.load(path); // will use internal cache
        final handle = (ffiEngine.debugCache[path]) ?? (ffiEngine as dynamic)._currentHandle as int?;
        if (handle != null) {
          _cachedSounds[path] = SoundProps(
            path: path,
            handle: handle,
            duration: await _engine!.duration(),
          );
        }
      }));
    } finally {
      _isPreloading = false;
      notifyListeners();
    }
  }

  Future<void> _ensureSessionActive() async {
    try {
      if (!_sessionActive) {
        final session = await AudioSession.instance;
        // Request/activate audio focus before starting playback
        await session.setActive(true);
        _sessionActive = true;
      }
    } catch (_) {
      // Best-effort: if activation fails, continue; backend may still play
    }
  }

  void _startSmoothPlayheadTimer() {
    _smoothPlayheadTimer?.cancel();
    // 60 FPS timer for smooth UI updates (16.67ms interval)
    _smoothPlayheadTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
  if (_audibleStarted) {
        // Predict playhead between engine ticks using wall clock and current pitch
        final now = DateTime.now();
        final elapsedUs = now.difference(_lastEngineUpdateTime).inMicroseconds;
        final predictedUs = _baseEnginePosition.inMicroseconds + (elapsedUs * _pitch).round();
        var predicted = Duration(microseconds: predictedUs);

        // Clamp to known duration
        if (_duration > Duration.zero && predicted > _duration) {
          predicted = _duration;
        }
        // Apply visual-only latency compensation
        if (_latencyCompensation > Duration.zero && predicted > _latencyCompensation) {
          predicted -= _latencyCompensation;
        }

        if (predicted != _position) {
          _position = predicted;
        }
        _notifyIfNeeded();
      }
    });
  }

  void _updatePosition(Duration newPosition) {
    if (_position != newPosition) {
  _position = newPosition;
  _baseEnginePosition = newPosition;
  _lastEngineUpdateTime = DateTime.now();
    }
  }

  void _updateDuration(Duration newDuration) {
    if (_duration != newDuration) {
      _duration = newDuration;
      _notifyIfNeeded();
    }
  }

  void _notifyIfNeeded() {
    final now = DateTime.now();
    final sinceLastNotifyMs = now.difference(_lastNotifyTime).inMilliseconds;
    final positionDiffMs = (_position - _lastNotifiedPosition).inMilliseconds.abs();

    final shouldNotify = positionDiffMs >= 16 || (!_isPlaying && positionDiffMs > 0) || sinceLastNotifyMs >= 33;
    if (shouldNotify) {
      _lastNotifiedPosition = _position;
      _lastNotifyTime = now;
      notifyListeners();
    }
  }

  // Compute normalized gain with +12 dB headroom so positive gain has effect
  double _gainAmplitude(double gainDb) {
    // Map gain dB to linear amplitude with 0 dB => 1.0; positive gains clamp to 1.0 (no extra headroom at engine level)
    final double amplitude = pow(10.0, gainDb / 20.0).toDouble();
    return amplitude.clamp(0.0, 1.0);
  }

  // Easing functions for smooth volume transitions
  double _easeOut(double t) {
    return (1 - pow(1 - t, 3)).toDouble();
  }

  // Enhanced volume ramping with higher resolution and easing curves
  Future<void> _rampVolume(
    double from, 
    double to, {
    int steps = 8, 
    Duration totalDuration = const Duration(milliseconds: 80),
    bool useEasing = true,
  }) async {
    if ((to - from).abs() < 1e-6 || steps <= 0) {
  await _engine?.setVolume(to);
      return;
    }

    final int stepMs = (totalDuration.inMilliseconds ~/ steps).clamp(1, 50);
    final double volumeRange = to - from;
    for (int i = 1; i <= steps; i++) {
      final double progress = i / steps;
      final double eased = useEasing ? _easeOut(progress) : progress;
      final double target = from + (volumeRange * eased);
  await _engine?.setVolume(target);
      if (i < steps) {
        await Future.delayed(Duration(milliseconds: stepMs));
      }
    }
  }

  Future<void> _applyEffectiveVolume() async {
    double gainFactor = 1.0;
    if (_currentSample != null) {
      gainFactor = _gainAmplitude(_currentSample!.gainDb);
    }
    final double effective = (_volume.clamp(0.0, 1.0)) * gainFactor * _headroom;
  // If future engine provides per-sample PCM hook, DSP graph would run there.
  // For now we only adjust engine volume factoring headroom.
  await _engine?.setVolume(effective);
  }

  Future<void> loadSample(AudioSample sample) async {
    try {
      final int token = ++_loadToken;
  // If waveform is still analyzing, proceed with audio load
      _isLoading = true;
      notifyListeners();

  //

  // Ensure audio focus is active as early as possible for reliable first playback
  await _ensureSessionActive();

      // If currently playing, ramp down and pause to avoid pops when swapping source
  if (_isPlaying && _engine != null) {
        final double targetVol = (_volume.clamp(0.0, 1.0)) * (_currentSample != null ? _gainAmplitude(_currentSample!.gainDb) : 1.0) * _headroom;
        await _rampVolume(targetVol, 0.0, totalDuration: const Duration(milliseconds: 50), steps: 8);
  await _engine?.pause();
        _isPlaying = false;
      }

      // Generate waveform data if missing, but delay slightly and skip if currently playing
      // or within the I/O quiet window to avoid interference at playback start.
  if (!sample.isWaveformLoading && (sample.waveformData == null || sample.waveformData!.isEmpty)) {
        // ignore: unawaited_futures
        Future.delayed(const Duration(milliseconds: 400), () async {
          if (token != _loadToken) return; // another load started
          if (_isPlaying) return; // avoid running heavy extraction while user starts playback
          if (DateTime.now().isBefore(_ioQuietUntil)) return; // respect quiet window
          if (_currentSample?.id != sample.id) return; // sample changed
          final waveformData = await generateWaveformData(sample.filePath);
          if (waveformData != null && waveformData.isNotEmpty) {
            // Upstream can refresh model elsewhere if desired
          }
        });
      }

  // Always replace current sample to ensure correct source per tap
  // debug
  // print('loadSample: id=${sample.id} path=${sample.filePath} start=${sample.startTime.inMilliseconds} end=${sample.endTime.inMilliseconds}');
  _currentSample = sample;
      _playingSample = sample; // Set the playing sample when loading
      // SoLoud-first behavior: load full file, apply clip via engine.setClip
  await _engine!.load(sample.filePath, start: Duration.zero, end: null);
  if (token != _loadToken) return; // a newer load started; abort
      // Query engine-reported duration as soon as we load; some samples may have unknown duration in model
      try {
        final d = await _engine!.duration();
        if (d > Duration.zero) {
          _updateDuration(d);
          // If trim markers exist, apply them against the engine duration
          final bool hasTrim = sample.startTime > Duration.zero ||
              (sample.endTime > Duration.zero && sample.endTime < d);
          if (hasTrim) {
            final effectiveEnd = (sample.endTime > Duration.zero && sample.endTime < d)
                ? sample.endTime
                : d;
            await _engine!.setClip(start: sample.startTime, end: effectiveEnd);
          } else {
            await _engine!.setClip(start: null, end: null);
          }
        } else {
          // Duration unknown; keep any existing clip intent off for now
          await _engine!.setClip(start: null, end: null);
        }
      } catch (_) {
        // Best-effort; keep clip cleared on failure
        try { await _engine!.setClip(start: null, end: null); } catch (_) {}
      }
  if (token != _loadToken) return;
  // Engine loaded source

      // Track baseline absolute clip window for in-place trim updates
  // Baseline is full file in SoLoud flow
  _clipBaseStartAbs = Duration.zero;
  // _clipBaseEndAbs was unused; removed

  // Apply combined master volume and sample gain (0 dB => 1.0; positive gains clamp at 1.0)
  await _applyEffectiveVolume();
  // Applied sample gain: ${sample.gainDb} dB

      // Always start at the beginning for a fresh load to avoid end-of-clip no-audio on first tap
  // Seek to intended start; if trimmed and we know engine duration, start at clip start (0 relative)
  final Duration engineDur = _duration;
  final bool isTrimmedNow = sample.startTime > Duration.zero ||
      (sample.endTime > Duration.zero && (engineDur == Duration.zero ? false : sample.endTime < engineDur));
  if (isTrimmedNow) {
        // Clip-relative: start from 0 within the clip window
  const Duration relStart = Duration.zero;
  await _engine!.seek(relStart);
        _position = relStart;
      } else {
        // Absolute timeline: start from the sample's startTime
        final Duration absStart = sample.startTime;
  await _engine!.seek(absStart);
        _position = absStart;
      }
  // Query final position for potential future use
  await _engine!.position();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
  // Error loading sample: $e
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> play() async {
    if (_currentSample != null) {
  // Enter a short I/O quiet window around playback to reduce startup races
  _ioQuietUntil = DateTime.now().add(const Duration(milliseconds: 600));
  // Make sure the platform audio session is active (fixes first-tap no-audio)
  await _ensureSessionActive();
      // Compute effective target volume before starting (master * normalized gain)
  double effectiveTargetVolume() => (_volume.clamp(0.0, 1.0)) * _gainAmplitude(_currentSample!.gainDb) * _headroom;

    final start = _currentSample!.startTime;
    // Prefer engine-reported duration if available
    final Duration modelDur = _currentSample!.duration;
    final Duration effectiveDur = (_duration > Duration.zero) ? _duration : modelDur;
    final end = (_currentSample!.endTime > Duration.zero && _currentSample!.endTime < effectiveDur)
      ? _currentSample!.endTime
      : effectiveDur;
  // debug
  // print('play(): pos=${_position.inMilliseconds} start=${start.inMilliseconds} end=${end.inMilliseconds}');
      if (start >= end) {
        if (kDebugMode) {
          debugPrint('[AudioProvider] play guard: start>=end (start=${start.inMilliseconds}ms, end=${end.inMilliseconds}ms, engineDur=${_duration.inMilliseconds}ms, modelDur=${modelDur.inMilliseconds}ms)');
        }
        // Attempt to reset clip and try a best-effort play from 0
        try { await _engine!.setClip(start: null, end: null); } catch (_) {}
        await _engine!.seek(Duration.zero);
        // Continue to play with ramp below
      }
      
      // Always clamp and seek before play to ensure backend starts reliably
      // Determine the intended playback start (for warm-up fallback)
      Duration playStartPos;
      if (_currentSample!.isTrimmed) {
        // Clipped playback: Duration.zero is clip start
        final clipEnd = end - start;
        Duration clamped = _position;
        if (clamped >= clipEnd) {
          // If we're at end, restart at clip start to guarantee audible output
          clamped = Duration.zero;
        } else if (clamped < Duration.zero) {
          clamped = Duration.zero;
        }
  await _engine?.seek(clamped);
        _position = clamped;
        playStartPos = clamped;
      } else {
        // Full-track playback: clamp to [start, end) and restart at start if at end
        Duration clamped = _position;
        if (clamped >= end) {
          clamped = start;
        } else if (clamped < start) {
          clamped = start;
        }
  await _engine?.seek(clamped);
        _position = clamped;
        playStartPos = clamped;
      }
  // Anti-pop and optional warm-up: only warm up once on Android; otherwise do a normal ramp
  final targetVol = effectiveTargetVolume();
  final bool engineNeedsRamp = _engine?.needsStartupRamp ?? true;
  if (!engineNeedsRamp) {
    // Enforce single-instance per sample: stop any currently active voice
    try { await _engine!.stop(); } catch (_) {}
    await _engine!.setVolume(targetVol);
    _isPlaying = true;
    await _engine!.play();
    _audibleStarted = true;
    return;
  }
  // Warm-up on Android when the engine requires it to avoid intermittent pipeline silence
  final bool shouldWarmUp = !kIsWeb && defaultTargetPlatform == TargetPlatform.android && engineNeedsRamp;
  if (shouldWarmUp) {
    // Tiny epsilon to prime the pipeline
    final double eps = (() {
      final v = targetVol * 0.01; // 1% of target
      if (v.isNaN || v.isInfinite) return 0.01;
      return v.clamp(0.005, 0.05);
    })();
    try { await _engine!.stop(); } catch (_) {}
  await _engine!.setVolume(eps);
    _isPlaying = true;
  await _engine?.play();
    // Wait briefly for position to advance
    bool advanced = false;
  try {
  final Duration startPos = _position;
      const int maxWaitMs = 300;
      const int stepMs = 10;
      int waited = 0;
      while (waited < maxWaitMs) {
  final p = await _engine!.position();
        if (p > startPos) {
          _updatePosition(p);
          advanced = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: stepMs));
        waited += stepMs;
      }
    } catch (_) {}
    if (!advanced) {
      // Warm-up fallback: quick pause/re-seek/play
      try {
  await _engine!.pause();
        await Future.delayed(const Duration(milliseconds: 10));
  await _engine!.seek(playStartPos);
  await _engine!.play();
      } catch (_) {}
    }
    await Future.delayed(const Duration(milliseconds: 20));
  await _rampVolume(eps, targetVol, totalDuration: const Duration(milliseconds: 60), steps: 8);
  _audibleStarted = true;
  } else {
    try { await _engine!.stop(); } catch (_) {}
  await _engine!.setVolume(0.0);
    _isPlaying = true;
  await _engine!.play();
    await Future.delayed(const Duration(milliseconds: 10));
  await _rampVolume(0.0, targetVol, totalDuration: const Duration(milliseconds: 60), steps: 8);
  _audibleStarted = true;
  }
    }
  }

  Future<void> pause() async {
    // Anti-pop: ramp down quickly before pausing, then restore target level while paused
  double targetVol = (_volume.clamp(0.0, 1.0)) * (_currentSample != null ? _gainAmplitude(_currentSample!.gainDb) : 1.0) * _headroom;

  await _rampVolume(targetVol, 0.0, totalDuration: const Duration(milliseconds: 80), steps: 8);
    await _engine!.pause();
  _isPlaying = false;
  await _engine!.setVolume(targetVol);
  _audibleStarted = false;
  }

  Future<void> stop() async {
    if (!_isPlaying && !_audibleStarted) {
      _position = Duration.zero;
      _playingSample = null;
      notifyListeners();
      return;
    }
    // Anti-pop: ramp down quickly before stopping, then restore target level
  double targetVol = (_volume.clamp(0.0, 1.0)) * (_currentSample != null ? _gainAmplitude(_currentSample!.gainDb) : 1.0) * _headroom;

  await _rampVolume(targetVol, 0.0, totalDuration: const Duration(milliseconds: 80), steps: 8);
    await _engine!.stop();
  _isPlaying = false;
  await _engine!.setVolume(targetVol);
    _position = Duration.zero;
    _playingSample = null; // Clear the playing sample when stopped
  _audibleStarted = false;
    // Release audio focus when fully stopped
    try {
      if (_sessionActive) {
        final session = await AudioSession.instance;
        await session.setActive(false);
        _sessionActive = false;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    if (_currentSample != null) {
      // Helper: quick anti-pop ramp around seeks when currently playing and performing a significant jump
  Future<void> rampForSeek(Future<void> Function() doSeek) async {
        if (_isPlaying) {
          final targetVol = (_volume.clamp(0.0, 1.0)) * _gainAmplitude(_currentSample!.gainDb) * _headroom;
          // Ramp down, perform seek, then ramp back up using enhanced ramping
          await _rampVolume(targetVol, 0.0, totalDuration: const Duration(milliseconds: 50), steps: 8);
          await doSeek();
          await _rampVolume(0.0, targetVol, totalDuration: const Duration(milliseconds: 50), steps: 8);
        } else {
          await doSeek();
        }
      }

      final start = _currentSample!.startTime;
      final end = (_currentSample!.endTime > Duration.zero && _currentSample!.endTime < _currentSample!.duration)
          ? _currentSample!.endTime
          : _currentSample!.duration;
      
      Duration clamped;
      if (_currentSample!.isTrimmed) {
        // ClippingAudioSource: clamp relative to the clip
        final clipEnd = end - start; // Duration of the clip
        clamped = position < Duration.zero ? Duration.zero : (position > clipEnd ? clipEnd : position);
  // seek() called (clipped). Requested: $position, clamped: $clamped, clipEnd: $clipEnd
      } else {
        // Regular AudioSource: clamp relative to original file
        clamped = position < start ? start : (position > end ? end : position);
  // seek() called (regular). Requested: $position, clamped: $clamped, start: $start, end: $end
      }
      
  await rampForSeek(() async {
    await _engine!.seek(clamped);
      });
      _position = clamped;
      notifyListeners();
    } else {
  await _engine!.seek(position);
    }
  }

  Future<void> setVolume(double volume) async {
    // Keep master volume within 0..1; headroom is handled by per-sample gain normalization
    _volume = volume.clamp(0.0, 1.0);
    await _applyEffectiveVolume();
    notifyListeners();
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
  await _engine!.setSpeed(_pitch);
    notifyListeners();
  }

  Future<void> setReverb(double reverb) async {
    _reverb = reverb.clamp(0.0, 1.0);
    // Note: Just Audio doesn't have built-in reverb
    // This would need to be implemented with audio processing plugins
    notifyListeners();
  }

  Future<void> setEcho(double echo) async {
    _echo = echo.clamp(0.0, 1.0);
    // Note: Just Audio doesn't have built-in echo
    // This would need to be implemented with audio processing plugins
    notifyListeners();
  }

  Future<void> playSample(AudioSample sample) async {
    await loadSample(sample);
    _playingSample = sample; // Set the playing sample
    await play();
  }

  Future<void> playSampleWithEffects(AudioSample sample, {
    double? volume,
    double? pitch,
    double? reverb,
    double? echo,
  }) async {
    await loadSample(sample);

    if (volume != null) await setVolume(volume);
    if (pitch != null) await setPitch(pitch);
    if (reverb != null) await setReverb(reverb);
    if (echo != null) await setEcho(echo);

    await play();
  }

  Future<void> loopSample(AudioSample sample) async {
    await loadSample(sample);
  await _engine?.setLooping(true);
  await _ensureSessionActive();
    await play();
  }

  Future<void> stopLoop() async {
  await _engine?.setLooping(false);
    await stop();
  }

  Future<void> fadeIn(Duration duration) async {
  await _engine!.setVolume(0.0);
  await _ensureSessionActive();
    await play();

    const steps = 50;
    final stepDuration = duration.inMilliseconds ~/ steps;
    final volumeStep = _volume / steps;

    for (int i = 1; i <= steps; i++) {
  await Future.delayed(Duration(milliseconds: stepDuration));
  await _engine!.setVolume(volumeStep * i);
    }
  }

  

  Future<void> fadeOut(Duration duration) async {
    const steps = 50;
    final stepDuration = duration.inMilliseconds ~/ steps;
    final volumeStep = _volume / steps;

    for (int i = steps; i > 0; i--) {
  await Future.delayed(Duration(milliseconds: stepDuration));
  await _engine!.setVolume(volumeStep * i);
    }

    await stop();
  }

  Future<void> applyTrim(Duration startTime, Duration endTime) async {
    if (_currentSample != null) {
  // applyTrim() requested: start=$startTime end=$endTime
  // BEFORE setClip
      if (_ja != null) {
      await _ja!.setClip(start: startTime, end: endTime);
      }
  // AFTER setClip
    }
  }

  /// Adjust clip during playback using absolute times (relative to original file timeline).
  Future<void> applyTrimRelativeForCurrent({
    Duration? newStartAbs,
    Duration? newEndAbs,
  }) async {
    if (_currentSample == null) return;
    final Duration fullDuration = _currentSample!.duration;
    final Duration effectiveStartAbs = newStartAbs ?? _currentSample!.startTime;
    final Duration effectiveEndAbs = (newEndAbs != null && newEndAbs > Duration.zero && newEndAbs < fullDuration)
        ? newEndAbs
        : fullDuration;

    // Debounce rapid changes to avoid crackles
    _pendingTrimStartAbs = effectiveStartAbs;
    _pendingTrimEndAbs = effectiveEndAbs;
    _trimDebounce?.cancel();
  _trimDebounce = Timer(_trimDebounceInterval + const Duration(milliseconds: 40), () async {
      if (_currentSample == null) return;
      final Duration startAbs = _pendingTrimStartAbs ?? _currentSample!.startTime;
      final Duration endAbs = _pendingTrimEndAbs ??
          ((_currentSample!.endTime > Duration.zero && _currentSample!.endTime < fullDuration)
              ? _currentSample!.endTime
              : fullDuration);

      Duration relStart = startAbs - _clipBaseStartAbs;
      if (relStart.isNegative) relStart = Duration.zero;
      Duration relEnd = endAbs - _clipBaseStartAbs;
      if (relEnd < Duration.zero) relEnd = Duration.zero;

  // Quick ramp to reduce pops around engine.setClip
  final double targetVol = (_volume.clamp(0.0, 1.0)) * (_currentSample != null ? _gainAmplitude(_currentSample!.gainDb) : 1.0) * _headroom;
  final bool wasPlaying = _isPlaying;
  await _rampVolume(targetVol, 0.0, totalDuration: const Duration(milliseconds: 60), steps: 8);
  if (wasPlaying && _audibleStarted) {
  await _engine!.pause();
  }
  await _engine!.setClip(start: relStart, end: relEnd);
  // Ensure the playhead is within the new clip while volume is down
  final currentPos = await _engine!.position();
  final clipLen = relEnd - relStart;
  Duration clamped = currentPos;
  if (clamped < Duration.zero) clamped = Duration.zero;
  if (clipLen > Duration.zero && clamped > clipLen) clamped = clipLen;
  await _engine!.seek(clamped);
  if (wasPlaying && _audibleStarted) {
  await _engine!.play();
  }
  await _rampVolume(0.0, targetVol, totalDuration: const Duration(milliseconds: 60), steps: 8);

      _currentSample = _currentSample!.copyWith(startTime: startAbs, endTime: endAbs);
      // No pause here; keep state as-is since we've already clamped while volume was down
      _notifyIfNeeded();
    });
  }

  Future<void> resetEffects() async {
    _volume = 1.0;
    _pitch = 1.0;
    _reverb = 0.0;
    _echo = 0.0;
  await _applyEffectiveVolume();
    // Reset DSP graph parameters (recreate for simplicity)
    _dspGraph?.dispose();
    _dspGraph = DspGraph.basic(masterGain: 1.0, limiter: true);
    if (_engine?.supportsDsp == true) {
      try { await _engine!.setDspGraph(_dspGraph); } catch (_) {}
    }
  }

  void setCurrentSample(AudioSample sample) {
    _currentSample = sample;
    // Reset baseline window so the next trim operations are relative to this sample
    _clipBaseStartAbs = sample.startTime;
  // _clipBaseEndAbs removed (unused)
  _baseEnginePosition = _position;
  _lastEngineUpdateTime = DateTime.now();
    notifyListeners();
  }

  /// Update the gain for the currently loaded sample
  Future<void> updateSampleGain(AudioSample sample) async {
    if (_currentSample?.id == sample.id) {
      // Keep provider's current sample in sync
      _currentSample = sample;
      await _applyEffectiveVolume();
  // Updated sample gain: ${sample.gainDb} dB
      
      notifyListeners();
    }
  }


  /// Get actual duration of an audio file
  Future<Duration> getAudioDuration(String filePath) async {
  // Not implemented without direct just_audio dependency; return zero (caller can ignore or compute when loading sample).
  return Duration.zero;
  }

  /// Generate waveform data for an audio file using just_waveform
  Future<List<double>?> generateWaveformData(String filePath) async {
    try {
      final waveFile = File('$filePath.waveform');
      final progressStream = JustWaveform.extract(
        audioInFile: File(filePath),
        waveOutFile: waveFile,
      );
      await for (final progress in progressStream) {
        if (progress.waveform != null) {
          final waveform = progress.waveform!;
          // Generate proper mirrored waveform data
          final int pixelCount = waveform.length;
          final bool is16bit = waveform.flags == 0;
          final double maxAbs = is16bit ? 32768.0 : 128.0;
          // Use peak magnitude per pixel and normalize to [0,1] so renderers can mirror evenly
          final samples = List<double>.generate(pixelCount, (i) {
            final double minV = waveform.getPixelMin(i).toDouble();
            final double maxV = waveform.getPixelMax(i).toDouble();
            final double peak = (minV.abs() > maxV.abs()) ? minV.abs() : maxV.abs();
            final double amplitude = (peak / maxAbs).clamp(0.0, 1.0);
            return amplitude;
          });
          
          // Debug the generated waveform data
          debugWaveformData(samples);
          return samples;
        }
      }
      final fallbackData = _generateUniqueWaveform(filePath);
      debugWaveformData(fallbackData);
      return fallbackData;
    } catch (e) {
      final fallback = _generateUniqueWaveform(filePath);
      debugWaveformData(fallback);
      return fallback;
    }
  }

  /// Regenerate waveform data for an existing sample to fix mirroring issues
  Future<List<double>?> regenerateWaveformData(AudioSample sample) async {
    return generateWaveformData(sample.filePath);
  }

  /// Debug method to print waveform data statistics
  void debugWaveformData(List<double> waveformData) {
    if (waveformData.isEmpty) {
  // Waveform debug: empty data
      return;
    }
  // Waveform debug suppressed
  }

  /// Generate a unique waveform pattern based on audio file properties
  List<double> _generateUniqueWaveform(String filePath) {
    final List<double> waveformData = [];
    const int dataPoints = 100;

    // Use file name hash to create unique patterns
    final fileName = filePath.split('/').last;
    final fileNameHash = fileName.hashCode;

    for (int i = 0; i < dataPoints; i++) {
      final progress = i / dataPoints.toDouble();

      // Create unique patterns based on file properties
      final baseAmplitude = 0.3 + 0.4 * (progress * 2 - 1).abs();

      // Add variation based on file name hash
      final hashVariation = (fileNameHash % 1000) / 1000.0;

      // Combine multiple wave patterns for uniqueness
      final wave1 = (progress * 3 + hashVariation) % 1.0;
      final wave2 = (progress * 5 + (fileNameHash % 100) / 100.0) % 1.0;
      final wave3 = (progress * 7 + (fileNameHash % 50) / 50.0) % 1.0;

      final amplitude = baseAmplitude + 0.2 * wave1 + 0.15 * wave2 + 0.1 * wave3;
      
      // Convert to [-1, 1] range for proper mirrored display
      final mirroredAmplitude = (amplitude.clamp(0.0, 1.0) * 2 - 1);
      waveformData.add(mirroredAmplitude);
    }

    return waveformData;
  }

  // Fallback helper removed; use _generateUniqueWaveform for all synthetic cases

  double get playbackProgress {
    if (_duration.inMilliseconds == 0) return 0.0;
    return _position.inMilliseconds / _duration.inMilliseconds;
  }

  @override
  void dispose() {
    // Cancel subscriptions to avoid leaks and satisfy lints
    try {
      _positionSubscription?.cancel();
    } catch (_) {}
    try {
      _durationSubscription?.cancel();
    } catch (_) {}
    try {
      _playerStateSubscription?.cancel();
    } catch (_) {}
    _positionSubscription = null;
    _durationSubscription = null;
    _playerStateSubscription = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _smoothPlayheadTimer?.cancel();
    _smoothPlayheadTimer = null;
  _trimDebounce?.cancel();
  _trimDebounce = null;
    // Deactivate audio session if we had activated it
    () async {
      try {
        if (_sessionActive) {
          final session = await AudioSession.instance;
          await session.setActive(false);
          _sessionActive = false;
        }
      } catch (_) {}
    }();
  _engine?.dispose();
  _dspGraph?.dispose();
    super.dispose();
  }
} 






