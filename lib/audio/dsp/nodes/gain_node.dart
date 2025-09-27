import '../dsp_graph.dart';
import 'dart:typed_data';

class GainNode implements DspNode {
  double gain; // linear 0.. >1
  bool enabled = true;
  GainNode(this.gain);
  @override
  void process(Float32List buffer, int channels) {
    if (!enabled || gain == 1.0) return;
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] *= gain;
    }
  }
  
  @override
  void dispose() {}
}
