import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:live_audio_sampler/providers/audio_provider.dart';

class EffectsPanel extends StatelessWidget {
  const EffectsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Column(
        children: [
          // Effects title
          Row(
            children: [
              Icon(
                Icons.tune,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Effects',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              Consumer<AudioProvider>(
                builder: (context, audioProvider, child) {
                  return TextButton(
                    onPressed: audioProvider.resetEffects,
                    child: const Text('Reset'),
                  );
                },
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          // Effects controls
          Expanded(
            child: Consumer<AudioProvider>(
              builder: (context, audioProvider, child) {
                return Row(
                  children: [
                    // Visual latency compensation (ms)
                    Expanded(
                      child: _buildEffectControl(
                        context,
                        icon: Icons.timelapse,
                        label: 'Latency',
                        value: audioProvider.latencyCompensation.inMilliseconds.toDouble(),
                        min: 0.0,
                        max: 200.0,
                        divisions: 40,
                        onChanged: (v) => audioProvider.setLatencyCompensation(
                          Duration(milliseconds: v.round()),
                        ),
                        valueLabel: '${audioProvider.latencyCompensation.inMilliseconds} ms',
                        useStickySnap: true,
                        snapValue: 0.0,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Volume control (sticky center at 1.0)
                    Expanded(
                      child: _buildEffectControl(
                        context,
                        icon: Icons.volume_up,
                        label: 'Volume',
                        value: audioProvider.volume,
                        min: 0.0,
                        max: 2.0,
                        divisions: 40,
                        onChanged: audioProvider.setVolume,
                        valueLabel: '${(audioProvider.volume * 100).round()}%',
                        useStickySnap: true,
                        snapValue: 1.0,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Pitch control (no sticky)
                    Expanded(
                      child: _buildEffectControl(
                        context,
                        icon: Icons.tune,
                        label: 'Pitch',
                        value: audioProvider.pitch,
                        min: 0.5,
                        max: 2.0,
                        divisions: 30,
                        onChanged: audioProvider.setPitch,
                        valueLabel: '${audioProvider.pitch.toStringAsFixed(2)}x',
                        useStickySnap: false,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Reverb control
                    Expanded(
                      child: _buildEffectControl(
                        context,
                        icon: Icons.eco,
                        label: 'Reverb',
                        value: audioProvider.reverb,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        onChanged: audioProvider.setReverb,
                        valueLabel: '${(audioProvider.reverb * 100).round()}%',
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Echo control
                    Expanded(
                      child: _buildEffectControl(
                        context,
                        icon: Icons.repeat,
                        label: 'Echo',
                        value: audioProvider.echo,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        onChanged: audioProvider.setEcho,
                        valueLabel: '${(audioProvider.echo * 100).round()}%',
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEffectControl(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
  bool useStickySnap = false,
  double? snapValue,
  }) {
    return Column(
      children: [
        // Icon and label
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 8),
        
        // Slider
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 12,
                ),
                activeTrackColor: Theme.of(context).colorScheme.primary,
                inactiveTrackColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                thumbColor: Theme.of(context).colorScheme.primary,
                overlayColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              ),
              child: useStickySnap
                  ? _StickySlider(
                      value: value,
                      min: min,
                      max: max,
                      divisions: divisions,
                      onChanged: onChanged,
                      snapValue: snapValue ?? ((min + max) / 2),
                    )
                  : Slider(
                      value: value,
                      min: min,
                      max: max,
                      divisions: divisions,
                      onChanged: onChanged,
                    ),
            ),
          ),
        ),
        
        const SizedBox(height: 8),
        
        // Value display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            valueLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
} 

class _StickySlider extends StatefulWidget {
  const _StickySlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.snapValue,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final double snapValue;

  @override
  State<_StickySlider> createState() => _StickySliderState();
}

class _StickySliderState extends State<_StickySlider> {
  bool _stuckAtSnap = false;

  double get _step => (widget.max - widget.min) / widget.divisions;

  // Enter window: very small (avoid early snap while approaching)
  double get _enterWindow => (_step * 0.05).clamp(0.0005, 0.0025);

  // Exit window: strong resistance (~2.5 steps) so it stays sticky once reached
  double get _exitWindow => _step * 2.5;

  void _handleChanged(double raw) {
    double out = raw;

    // Determine stickiness transitions
    if (_stuckAtSnap) {
      // Stay stuck until outside of exit window
      if ((raw - widget.snapValue).abs() > _exitWindow) {
        _stuckAtSnap = false;
        out = raw;
      } else {
  // While stuck, bias toward exact snap to avoid jitter at tick boundaries
  out = widget.snapValue;
      }
    } else {
      // Only stick if extremely close to exact snap (no early jump)
      if ((raw - widget.snapValue).abs() <= _enterWindow) {
        _stuckAtSnap = true;
        out = widget.snapValue;
      }
    }

    // Forward adjusted value
    if (out != widget.value) {
      widget.onChanged(out);
    } else {
      // still notify on drag to keep provider hot? skip to reduce churn
    }
    setState(() {}); // update local sticky state
  }

  @override
  void didUpdateWidget(covariant _StickySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If external value set to snap, mark stuck; if far, release
    if ((widget.value - widget.snapValue).abs() <= _enterWindow) {
      _stuckAtSnap = true;
    }
    if ((widget.value - widget.snapValue).abs() > _exitWindow) {
      _stuckAtSnap = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: widget.value,
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      onChanged: _handleChanged,
      onChangeStart: (_) {
        _stuckAtSnap = (widget.value - widget.snapValue).abs() <= _enterWindow;
      },
      onChangeEnd: (_) {
        // keep stuck if near, otherwise release
        if ((widget.value - widget.snapValue).abs() > _exitWindow) {
          _stuckAtSnap = false;
        }
        setState(() {});
      },
    );
  }
}