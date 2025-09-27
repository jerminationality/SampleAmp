import 'dart:math';
import 'dart:typed_data';
import '../dsp_graph.dart';

enum BiquadType { lowpass, highpass, peak, lowshelf, highshelf }

class BiquadNode implements DspNode {
  @override
  bool enabled = true;
  BiquadType type;
  double sampleRate;
  double freq;
  double q;
  double gainDb; // for peak/shelf

  // Coefficients
  double _b0 = 0, _b1 = 0, _b2 = 0, _a1 = 0, _a2 = 0;
  double _z1L = 0, _z2L = 0, _z1R = 0, _z2R = 0;

  BiquadNode({
    required this.type,
    required this.sampleRate,
    required this.freq,
    this.q = 0.707,
    this.gainDb = 0.0,
  }) {
    _recalc();
  }

  void _recalc() {
    final w0 = 2 * pi * freq / sampleRate;
    final sinW0 = sin(w0);
    final cosW0 = cos(w0);
    final alpha = sinW0 / (2 * q);
    final aGain = pow(10, gainDb / 40.0).toDouble();

    double b0, b1, b2, a0, a1, a2;
    switch (type) {
      case BiquadType.lowpass:
        b0 = (1 - cosW0) / 2;
        b1 = 1 - cosW0;
        b2 = (1 - cosW0) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
        break;
      case BiquadType.highpass:
        b0 = (1 + cosW0) / 2;
        b1 = -(1 + cosW0);
        b2 = (1 + cosW0) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
        break;
      case BiquadType.peak:
        b0 = 1 + alpha * aGain;
        b1 = -2 * cosW0;
        b2 = 1 - alpha * aGain;
        a0 = 1 + alpha / aGain;
        a1 = -2 * cosW0;
        a2 = 1 - alpha / aGain;
        break;
      case BiquadType.lowshelf:
        final twoSqrtAG = 2 * sqrt(aGain) * alpha;
        b0 = aGain * ((aGain + 1) - (aGain - 1) * cosW0 + twoSqrtAG);
        b1 = 2 * aGain * ((aGain - 1) - (aGain + 1) * cosW0);
        b2 = aGain * ((aGain + 1) - (aGain - 1) * cosW0 - twoSqrtAG);
        a0 = (aGain + 1) + (aGain - 1) * cosW0 + twoSqrtAG;
        a1 = -2 * ((aGain - 1) + (aGain + 1) * cosW0);
        a2 = (aGain + 1) + (aGain - 1) * cosW0 - twoSqrtAG;
        break;
      case BiquadType.highshelf:
        final twoSqrtAG = 2 * sqrt(aGain) * alpha;
        b0 = aGain * ((aGain + 1) + (aGain - 1) * cosW0 + twoSqrtAG);
        b1 = -2 * aGain * ((aGain - 1) + (aGain + 1) * cosW0);
        b2 = aGain * ((aGain + 1) + (aGain - 1) * cosW0 - twoSqrtAG);
        a0 = (aGain + 1) - (aGain - 1) * cosW0 + twoSqrtAG;
        a1 = 2 * ((aGain - 1) - (aGain + 1) * cosW0);
        a2 = (aGain + 1) - (aGain - 1) * cosW0 - twoSqrtAG;
        break;
    }

    _b0 = b0 / a0;
    _b1 = b1 / a0;
    _b2 = b2 / a0;
    _a1 = a1 / a0;
    _a2 = a2 / a0;
  }

  @override
  void process(Float32List buffer, int channels) {
    if (!enabled) return;
    for (int i = 0; i < buffer.length; i += channels) {
      final xL = buffer[i];
      final yL = _b0 * xL + _z1L;
      _z1L = _b1 * xL + _z2L - _a1 * yL;
      _z2L = _b2 * xL - _a2 * yL;
      buffer[i] = yL;
      if (channels > 1) {
        final xR = buffer[i + 1];
        final yR = _b0 * xR + _z1R;
        _z1R = _b1 * xR + _z2R - _a1 * yR;
        _z2R = _b2 * xR - _a2 * yR;
        buffer[i + 1] = yR;
      }
    }
  }
  @override
  void dispose() {}
}
