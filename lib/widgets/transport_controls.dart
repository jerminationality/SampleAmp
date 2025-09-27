import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:live_audio_sampler/providers/audio_provider.dart';
import 'package:live_audio_sampler/utils.dart';

class TransportControls extends StatelessWidget {
  const TransportControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Consumer<AudioProvider>(
        builder: (context, audioProvider, child) {
          return Column(
            children: [
              // Progress bar
              _buildProgressBar(context, audioProvider),
              
              const SizedBox(height: 16),
              
              // Transport buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Previous button
                  IconButton(
                    onPressed: audioProvider.currentSample != null
                        ? () => _previousSample(context)
                        : null,
                    icon: const Icon(Icons.skip_previous),
                    tooltip: 'Previous Sample',
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Play/Pause button
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: audioProvider.currentSample != null
                          ? () => _togglePlayback(audioProvider)
                          : null,
                      icon: Icon(
                        audioProvider.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      tooltip: audioProvider.isPlaying ? 'Pause' : 'Play',
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Stop button
                  IconButton(
                    onPressed: audioProvider.currentSample != null
                        ? () => audioProvider.stop()
                        : null,
                    icon: const Icon(Icons.stop),
                    tooltip: 'Stop',
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Next button
                  IconButton(
                    onPressed: audioProvider.currentSample != null
                        ? () => _nextSample(context)
                        : null,
                    icon: const Icon(Icons.skip_next),
                    tooltip: 'Next Sample',
                  ),
                  
                  const SizedBox(width: 32),
                  
                  // Loop button
                  IconButton(
                    onPressed: audioProvider.currentSample != null
                        ? () => _toggleLoop(audioProvider)
                        : null,
                    icon: Icon(
                      Icons.loop,
                      color: audioProvider.currentSample != null
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    tooltip: 'Loop',
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Fade in button
                  IconButton(
                    onPressed: audioProvider.currentSample != null
                        ? () => _fadeIn(audioProvider)
                        : null,
                    icon: const Icon(Icons.volume_up),
                    tooltip: 'Fade In',
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Fade out button
                  IconButton(
                    onPressed: audioProvider.currentSample != null
                        ? () => _fadeOut(audioProvider)
                        : null,
                    icon: const Icon(Icons.volume_down),
                    tooltip: 'Fade Out',
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Time display
              _buildTimeDisplay(context, audioProvider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, AudioProvider audioProvider) {
    return Column(
      children: [
        // Progress slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 8,
            ),
            overlayShape: const RoundSliderOverlayShape(
              overlayRadius: 16,
            ),
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            thumbColor: Theme.of(context).colorScheme.primary,
            overlayColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: audioProvider.playbackProgress.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            onChanged: (value) {
              final current = audioProvider.currentSample;
              if (current == null) return;
              final full = audioProvider.duration.inMilliseconds;
              final absoluteMs = (value * full).round();
              final absolute = Duration(milliseconds: absoluteMs);
              audioProvider.seek(absolute);
            },
          ),
        ),
        
        // Progress indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatDuration(audioProvider.position),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              formatDuration(audioProvider.duration),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeDisplay(BuildContext context, AudioProvider audioProvider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.access_time,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        Text(
          '${formatDuration(audioProvider.position)} / ${formatDuration(audioProvider.duration)}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _togglePlayback(AudioProvider audioProvider) {
    if (audioProvider.isPlaying) {
      audioProvider.pause();
    } else {
      audioProvider.play();
    }
  }

  void _toggleLoop(AudioProvider audioProvider) {
    // TODO: Implement loop functionality
    // This would toggle between loop modes (off, one, all)
  }

  void _fadeIn(AudioProvider audioProvider) {
    audioProvider.fadeIn(const Duration(seconds: 2));
  }

  void _fadeOut(AudioProvider audioProvider) {
    audioProvider.fadeOut(const Duration(seconds: 2));
  }

  void _previousSample(BuildContext context) {
    // TODO: Implement previous sample functionality
    // This would require a playlist or sample queue
  }

  void _nextSample(BuildContext context) {
    // TODO: Implement next sample functionality
    // This would require a playlist or sample queue
  }
} 