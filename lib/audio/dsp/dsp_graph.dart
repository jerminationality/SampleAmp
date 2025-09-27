import 'dart:math';
import 'dart:typed_data';
import 'nodes/gain_node.dart';
import 'nodes/biquad_node.dart';
import 'nodes/limiter_node.dart';

/// Basic engine-agnostic DSP graph scaffolding.
/// Processes interleaved float32 buffers in-place (stereo) per block.

abstract class DspNode {
  bool get enabled;
  void process(Float32List buffer, int channels);
  void dispose();
}

class DspGraph {
  final List<DspNode> _nodes = [];

  void add(DspNode node) => _nodes.add(node);
  void remove(DspNode node) => _nodes.remove(node);

  void process(Float32List buffer, int channels) {
    for (final n in _nodes) {
      if (n.enabled) n.process(buffer, channels);
    }
  }

  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    _nodes.clear();
  }

  static DspGraph basic({
    double masterGain = 1.0,
    double? biquadFreq,
    double biquadQ = 0.707,
    double biquadGainDb = 0.0,
    int? biquadTypeIndex,
    bool limiter = true,
    double limiterThreshold = 0.98,
    double sampleRate = 44100,
  }) {
    final g = DspGraph();
    if (masterGain != 1.0) {
      g.add(GainNode(masterGain));
    }
    if (biquadFreq != null && biquadTypeIndex != null) {
      final type = BiquadType.values[biquadTypeIndex.clamp(0, BiquadType.values.length - 1)];
      g.add(BiquadNode(
        type: type,
        sampleRate: sampleRate,
        freq: biquadFreq,
        q: biquadQ,
        gainDb: biquadGainDb,
      ));
    }
    if (limiter) {
      g.add(LimiterNode(sampleRate: sampleRate, threshold: limiterThreshold));
    }
    return g;
  }
}

/// Simple parameter ramp helper (linear) to avoid clicks when changing values.
class ParamRamp {
  double _current;
  double _target;
  int _remaining = 0;
  final int sampleRate;

  ParamRamp(this._current, this.sampleRate) : _target = _current;

  double get value => _current;

  void jump(double v) {
    _current = v;
    _target = v;
    _remaining = 0;
  }

  void rampTo(double v, double timeMs) {
    _target = v;
    _remaining = max(1, (timeMs / 1000.0 * sampleRate).round());
  }

  /// Apply ramp per-sample returning next value.
  double next() {
    if (_remaining <= 0) return _current;
    final step = (_target - _current) / _remaining;
    _current += step;
    _remaining--;
    return _current;
  }
}
