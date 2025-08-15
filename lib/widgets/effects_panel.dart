import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

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
                    // Volume control
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
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // Pitch control
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
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
                inactiveTrackColor: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                thumbColor: Theme.of(context).colorScheme.primary,
                overlayColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              ),
              child: Slider(
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
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
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