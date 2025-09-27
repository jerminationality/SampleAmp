import 'dart:typed_data';
import 'dart:math' as math;
import '../dsp_graph.dart';

class LimiterNode implements DspNode {
  @override
  bool enabled = true;
  double threshold; // linear (e.g. 0.95)
  double releaseMs; // release time in ms
  double sampleRate;

  double _env = 0.0;
  late double _releaseCoeff;

  LimiterNode({
    required this.sampleRate,
    this.threshold = 0.95,
    this.releaseMs = 50,
  }) {
    _computeCoefficients();
  }

  void _computeCoefficients() {
  _releaseCoeff = math.exp(-1.0 / ((releaseMs / 1000.0) * sampleRate));
  }

  @override
  void process(Float32List buffer, int channels) {
    if (!enabled) return;
    for (int i = 0; i < buffer.length; i += channels) {
      double sampleL = buffer[i];
      double absSample = sampleL.abs();
      if (channels > 1) {
        double sampleR = buffer[i + 1];
        double absR = sampleR.abs();
        if (absR > absSample) absSample = absR;
      }
      if (absSample > _env) {
        _env = absSample; // attack = instant
      } else {
        _env = _env * _releaseCoeff + (1 - _releaseCoeff) * absSample;
      }
      double gain = 1.0;
      if (_env > threshold && _env > 0) {
        gain = threshold / _env;
      }
      buffer[i] = (buffer[i] * gain).clamp(-1.0, 1.0);
      if (channels > 1) {
        buffer[i + 1] = (buffer[i + 1] * gain).clamp(-1.0, 1.0);
      }
    }
  }
  @override
  void dispose() {}
}
