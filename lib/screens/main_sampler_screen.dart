import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_audio_waveforms/flutter_audio_waveforms.dart';
import 'package:flutter_oknob/flutter_oldschool_knob.dart';
import 'package:flutter_oknob/widgets/flutter_widget_painter.dart';
import '../providers/audio_provider.dart';
import '../providers/sample_provider.dart';
import '../models/audio_sample.dart';
import '../widgets/sample_grid.dart';
import '../widgets/effects_panel.dart';
import '../widgets/transport_controls.dart';
import '../widgets/sample_button.dart';
import '../utils.dart';


class MainSamplerScreen extends StatefulWidget {
  const MainSamplerScreen({super.key});

  @override
  State<MainSamplerScreen> createState() => _MainSamplerScreenState();
}

class _MainSamplerScreenState extends State<MainSamplerScreen> {
  AudioSample? _selectedSample;
  // Trim handle drag state
  bool _isDraggingStart = false;
  bool _isDraggingEnd = false;
  double? _draggingTrimStart;
  double? _draggingTrimEnd;
  Offset? _dragTooltipPosition;
  String? _dragTooltipText;
  static const double _minTrimFraction = 0.02;
  double? _playheadPosition; // 0.0-1.0 relative to waveform
  bool _playheadLockedToStart = true;
  Duration? _draggingTrimStartTime;
  Duration? _draggingTrimEndTime;

  @override
  void initState() {
    super.initState();
    // Add listener to check if selected sample still exists
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
      sampleProvider.addListener(_checkSelectedSampleExists);
    });
    // Listen to AudioProvider's playback state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final audioProvider = Provider.of<AudioProvider>(context, listen: false);
      audioProvider.addListener(_handleAudioProviderUpdate);
    });
  }

  @override
  void dispose() {
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
    audioProvider.removeListener(_handleAudioProviderUpdate);
    final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
    sampleProvider.removeListener(_checkSelectedSampleExists);
    super.dispose();
  }

  void _checkSelectedSampleExists() {
    if (_selectedSample != null) {
      final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
      final sampleStillExists = sampleProvider.getSampleById(_selectedSample!.id) != null;
      
      if (!sampleStillExists) {
        setState(() {
          _selectedSample = null;
        });
      }
    }
  }

  void _handleAudioProviderUpdate() {
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
    final sample = _selectedSample;
    if (sample == null) return;
    
    if (audioProvider.isPlaying) {
      // Unlock playhead to follow playback
      if (_playheadLockedToStart) {
        setState(() {
          _playheadLockedToStart = false;
        });
      }
    } else {
      // If playback stopped, lock playhead to start trim
      if (!_playheadLockedToStart) {
        setState(() {
          _playheadLockedToStart = true;
        });
      }
    }
    
    // Trigger rebuild to update playhead position
    setState(() {});
  }

  // Compute the gain fader slider position (0.0 - 1.0) using the same mapping as _GainFader
  double _gainSliderPositionForSample(AudioSample sample) {
    const double minDb = _GainFader.minDb;
    const double maxDb = _GainFader.maxDb;
    const double centerDb = _GainFader.centerDb;
    if (sample.gainDb <= centerDb) {
      return (0.5 * ((sample.gainDb - minDb) / (centerDb - minDb))).clamp(0.0, 1.0);
    } else {
      return (0.5 + 0.5 * ((sample.gainDb - centerDb) / (maxDb - centerDb))).clamp(0.0, 1.0);
    }
  }

  // Scale waveform samples for visual display based on gain slider position.
  // - At sliderPos == 0.0 → scale to 0 (flat line)
  // - At sliderPos == 0.5 (0 dB) → original samples (no change)
  // - Above 0.5 → scale up using amplitude factor from dB and clamp to [-1, 1]
  List<double> _scaledWaveformSamplesForDisplay(AudioSample sample) {
    final data = sample.waveformData;
    if (data == null || data.isEmpty) return const [];
    final sliderPos = _gainSliderPositionForSample(sample);
    if (sliderPos <= 0.0) {
      return List<double>.filled(data.length, 0.0);
    }
    if (sliderPos < 0.5) {
      final scaleDown = (2.0 * sliderPos).clamp(0.0, 1.0);
      return data.map((v) => (v * scaleDown)).toList(growable: false);
    }
    // sliderPos >= 0.5 → positive or zero gain
    if (sample.gainDb <= 0.0) {
      // Exactly 0 dB case or slight negatives rounded: keep original
      return List<double>.from(data, growable: false);
    }
    // Compute amplitude factor from dB boost
    final double amplitude = pow(10.0, sample.gainDb / 20.0).toDouble();
    // Soft saturation to avoid hard flat-tops while staying within [-1, 1]
    const double knee = 1.5; // larger = softer knee
    double _softClip(double x) => x / (1.0 + knee * x.abs());
    return data
        .map((v) => _softClip(v * amplitude))
        .toList(growable: false);
  }

  Future<void> _promptSetGainDb(BuildContext context) async {
    if (_selectedSample == null) return;
    final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
    final TextEditingController controller = TextEditingController(
      text: _selectedSample!.gainDb.toStringAsFixed(1),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Set Gain (dB)'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
            decoration: const InputDecoration(
              hintText: 'e.g. -6.0 or 3.0',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.trim());
                if (parsed == null) {
                  Navigator.of(ctx).pop();
                  return;
                }
                // Clamp to fader bounds
                const double minDb = _GainFader.minDb;
                const double maxDb = _GainFader.maxDb;
                final double clamped = parsed.clamp(minDb, maxDb);
                Navigator.of(ctx).pop(clamped);
              },
              child: const Text('Set'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      final updated = _selectedSample!.copyWith(gainDb: result);
      sampleProvider.updateSample(updated);
      await audioProvider.updateSampleGain(updated);
      setState(() => _selectedSample = updated);
    }
  }

  Future<void> _promptSetPitchSemitones(BuildContext context) async {
    if (_selectedSample == null) return;
    final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);

    double _pitchToSemitones(double pitch) => 12.0 * log(pitch) / log(2.0);
    double _semitonesToPitch(double semitones) => pow(2.0, semitones / 12.0).toDouble();

    final currentSemitones = _pitchToSemitones(_selectedSample!.pitch);
    final TextEditingController controller = TextEditingController(
      text: currentSemitones.toStringAsFixed(1),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Set Pitch (semitones)'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
            decoration: const InputDecoration(
              hintText: 'e.g. -3.0 to 3.0',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.trim());
                if (parsed == null) {
                  Navigator.of(ctx).pop();
                  return;
                }
                const double minSt = _PitchFader.minSemitones;
                const double maxSt = _PitchFader.maxSemitones;
                final double clamped = parsed.clamp(minSt, maxSt);
                Navigator.of(ctx).pop(clamped);
              },
              child: const Text('Set'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      final newPitch = _semitonesToPitch(result);
      final updated = _selectedSample!.copyWith(pitch: newPitch);
      sampleProvider.updateSample(updated);
      await audioProvider.setPitch(newPitch);
      setState(() => _selectedSample = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSelectedSample = _selectedSample != null;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16), // Extra top margin for status bar
        child: Column(
          children: [
            // Move bottom panel to the top
            _buildBottomPanel(),
            const SizedBox(height: 4),
            // Main Content Area
            Expanded(
              child: Row(
                children: [
                  // Left Panel - Sample Grid (6x4)
                  Expanded(
                    flex: 2,
                    child: _buildLeftPanel(),
                  ),
                  // Space between left and right panels
                  const SizedBox(width: 4),
                  // Right Panel - Sample Details
                  Expanded(
                    flex: 1,
                    child: _buildRightPanel(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // Sample grid container with background
            Expanded(
              child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(2),
          ),
                child: _buildSampleGrid(),
              ),
            ),
            // Tab buttons at the very bottom (separate from grid background)
            Container(
              padding: const EdgeInsets.only(top: 4, left: 8, right: 16, bottom: 0),
                child: Consumer<SampleProvider>(
                  builder: (context, sampleProvider, child) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        // Render existing page tabs
                        ...sampleProvider.availablePages.map((pageLetter) => 
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _buildPageTab(pageLetter, sampleProvider.isCurrentPage(pageLetter)),
                          ),
                        ),
                        // Add button for new pages
                        _buildPageTab('+', false),
                      ],
                    );
                  },
                ),
              ),
            ],
        );
      },
    );
  }

  String _getGridPosition(int index) {
    final pageLetter = Provider.of<SampleProvider>(context, listen: false).getCurrentPageLetter();
    // Return page letter + sequential numbering (A1, A2, A3, A4, A5, A6, A7, A8, etc.)
    return '$pageLetter${index + 1}';
  }

  String _getDisplayTextForSample(AudioSample sample, int index) {
    if (sample.isBlank) {
      return 'Add Audio';
    } else if (sample.name.isEmpty || sample.name.trim().isEmpty) {
      return _getGridPosition(index);
    } else {
      return sample.name.length > 12 
          ? '${sample.name.substring(0, 12)}...'
          : sample.name;
    }
  }

  Widget _buildSampleGrid() {
    // 6 columns x 4 rows = 24 slots
    const int totalSlots = 24;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate button size to fit grid in panel
        final double spacing = 6;
        final double gridWidth = constraints.maxWidth - 2 * 12; // padding
        final double gridHeight = constraints.maxHeight - 2 * 12; // padding
        final double buttonWidth = (gridWidth - (6 - 1) * spacing) / 6;
        final double buttonHeight = ((gridHeight - (4 - 1) * spacing) / 4) - 6;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Consumer<SampleProvider>(
            builder: (context, sampleProvider, child) {
              final samples = sampleProvider.currentPageSamples;
              return GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: buttonWidth / buttonHeight,
                ),
                itemCount: totalSlots,
                itemBuilder: (context, index) {
                  if (index < samples.length) {
                    final sample = samples[index];
                    return DragTarget<AudioSample>(
                      onWillAccept: (data) => data != null && data.id != sample.id,
                      onAccept: (data) {
                        final draggedIndex = samples.indexWhere((s) => s.id == data.id);
                        if (draggedIndex != -1 && draggedIndex != index) {
                          sampleProvider.reorderSamples(draggedIndex, index);
                        }
                      },
                      builder: (context, candidateData, rejectedData) {
                        return Draggable<AudioSample>(
                          data: sample,
                          onDragEnd: (details) {
                            _handleDragEnd(details, sample, sampleProvider);
                          },
                          feedback: Material(
                            elevation: 8,
                            child: SizedBox(
                              width: buttonWidth,
                              height: buttonHeight,
                              child: SampleButton(
                                sample: sample,
                                gridPosition: _getGridPosition(index),
                                selectedSampleId: _selectedSample?.id,
                                onAddAudio: sample.isBlank ? () => _showAddSampleDialog(context, sampleId: sample.id) : null,
                                onSelect: () {
                                  _selectSample(sample);
                                },
                              ),
                            ),
                          ),
                          childWhenDragging: Container(
                            width: buttonWidth,
                            height: buttonHeight,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.grey.withOpacity(0.5),
                                width: 1,
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: const Icon(
                              Icons.drag_indicator,
                              color: Colors.grey,
                              size: 24,
                            ),
                          ),
                          child: SizedBox(
                            width: buttonWidth,
                            height: buttonHeight,
                            child: SampleButton(
                              sample: sample,
                            gridPosition: _getGridPosition(index),
                              selectedSampleId: _selectedSample?.id,
                              onAddAudio: sample.isBlank ? () => _showAddSampleDialog(context, sampleId: sample.id) : null,
                            onSelect: () {
                              _selectSample(sample);
                            },
                            ),
                          ),
                        );
                      },
                    );
                  } else if (index == samples.length) {
                    // + button in the next available slot
                    return _buildAddButton(width: buttonWidth, height: buttonHeight);
                  } else {
                    // Empty slot: invisible
                    return const SizedBox.shrink();
                  }
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSampleButton(AudioSample sample, bool isSelected, double width, double height, String gridPosition, {bool includeGestures = true}) {
    return SizedBox(
      width: width,
      height: height,
      child: SampleButton(
        sample: sample,
        gridPosition: gridPosition,
        selectedSampleId: _selectedSample?.id,
        onAddAudio: sample.isBlank ? () => _showAddSampleDialog(context, sampleId: sample.id) : null,
        onSelect: () {
            setState(() {
              _selectedSample = sample;
            });
          },
      ),
        );
  }

  Widget _buildDraggableSampleButton(AudioSample sample, bool isSelected, double width, double height, int index) {
    // All samples (including blank ones) are draggable, tap, and long-press
    Color feedbackColor;
    if (sample.customColor != null) {
      feedbackColor = Color(sample.customColor!);
    } else if (sample.isBlank) {
      feedbackColor = Colors.grey[600]!;
    } else {
      switch (sample.category.toLowerCase()) {
        case 'applause':
        case 'crowd':
          feedbackColor = Colors.red;
          break;
        case 'music':
        case 'background':
          feedbackColor = Colors.green;
          break;
        default:
          feedbackColor = Colors.white;
      }
    }
    
    return Draggable<AudioSample>(
      data: sample,
      onDragStarted: () {
      },
      onDragEnd: (details) {
      },
      feedback: Material(
        elevation: 8,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: feedbackColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.yellow,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                sample.isBlank ? Icons.add : Icons.graphic_eq,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                _getDisplayTextForSample(sample, index),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.grey.withOpacity(0.5),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: const Icon(
          Icons.drag_indicator,
          color: Colors.grey,
          size: 24,
        ),
      ),
      child: GestureDetector(
        onTap: () {
          if (sample.isBlank) {
            _showAddSampleDialog(context, sampleId: sample.id);
          } else {
            _selectSample(sample);
          }
        },
        child: _buildSampleButton(sample, isSelected, width, height, _getGridPosition(index), includeGestures: false),
      ),
    );
  }

  Widget _buildAddButton({double? width, double? height}) {
    return GestureDetector(
      onTap: () {
        // Show the Add Audio dialog immediately
        _showAddSampleDialog(context);
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey[800]?.withOpacity(0.25),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(
          Icons.add,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        children: [
          // Sample title
          Container(
            padding: const EdgeInsets.all(16),
            child: Consumer<SampleProvider>(
              builder: (context, sampleProvider, child) {
                final selectedSample = _selectedSample;
                if (selectedSample != null) {
                  // Replace the sample name Text with an editable TextField
                  return _EditableSampleName(
                    sample: selectedSample,
                    onColorPicker: _showGridColorPicker,
                  );
                }
                // Show disabled label/color picker row when no sample is selected
                final panelColor = Theme.of(context).colorScheme.surface;
                final disabledBgColor = Colors.grey[900];
                return Row(
                  children: [
                    // Disabled label text field
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: ''),
                        readOnly: true,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          filled: true,
                          fillColor: disabledBgColor,
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(6),
                              bottomLeft: Radius.circular(6),
                              topRight: Radius.circular(0),
                              bottomRight: Radius.circular(0),
                            ),
                            borderSide: BorderSide.none,
                          ),
                          hintText: 'Sample Label',
                          hintStyle: TextStyle(color: Colors.grey[700]),
                        ),
                        enabled: false,
                      ),
                    ),
                    const SizedBox(width: 2),
                    // Disabled color picker button
                    SizedBox(
                      width: 48,
                      height: 36,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(0),
                              bottomLeft: Radius.circular(0),
                              topRight: Radius.circular(6),
                              bottomRight: Radius.circular(6),
                            ),
                          ),
                          padding: EdgeInsets.zero,
                          backgroundColor: disabledBgColor,
                          foregroundColor: Colors.grey[700],
                          elevation: 0,
                        ),
                        onPressed: null,
                        child: const Icon(Icons.palette, size: 20),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          
          // Playback controls
          Container(
            padding: const EdgeInsets.only(left: 16, right: 0),
            child: Builder(
              builder: (context) {
                final hasSelectedSample = _selectedSample != null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _buildRectControlButton(
                      Icons.first_page,
                      'Rewind',
                      onPressed: hasSelectedSample
                          ? () {
                              final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                              audioProvider.seek(Duration.zero);
                                  // Lock playhead to start
                                  if (_selectedSample != null) {
                                    final durationMs = _selectedSample!.duration.inMilliseconds > 0 ? _selectedSample!.duration.inMilliseconds : 1;
                                    final startFrac = (_selectedSample!.startTime.inMilliseconds / durationMs).clamp(0.0, 1.0);
                                    setState(() {
                                      _playheadLockedToStart = true;
                                      _playheadPosition = startFrac;
                                    });
                                  }
                            }
                          : null,
                      enabled: hasSelectedSample,
                    ),
                    const SizedBox(width: 2),
                    _buildRectControlButton(
                      Icons.play_arrow,
                      'Play',
                      onPressed: hasSelectedSample
                          ? () {
                              final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                              audioProvider.play();
                                  // Unlock playhead to follow playback
                                  setState(() {
                                    _playheadLockedToStart = false;
                                  });
                            }
                          : null,
                      enabled: hasSelectedSample,
                    ),
                    const SizedBox(width: 2),
                    _buildRectControlButton(
                      Icons.pause,
                      'Pause',
                      onPressed: hasSelectedSample
                          ? () {
                              final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                              audioProvider.pause();
                            }
                          : null,
                      enabled: hasSelectedSample,
                    ),
                    const SizedBox(width: 2),
                    _buildRectControlButton(
                      Icons.stop,
                      'Stop',
                      onPressed: hasSelectedSample
                          ? () {
                              final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                              audioProvider.stop();
                                  // Lock playhead to start
                                  if (_selectedSample != null) {
                                    final durationMs = _selectedSample!.duration.inMilliseconds > 0 ? _selectedSample!.duration.inMilliseconds : 1;
                                    final startFrac = (_selectedSample!.startTime.inMilliseconds / durationMs).clamp(0.0, 1.0);
                                    setState(() {
                                      _playheadLockedToStart = true;
                                      _playheadPosition = startFrac;
                                    });
                                  }
                            }
                          : null,
                      enabled: hasSelectedSample,
                    ),
                  ],
                    ),
                    const SizedBox(height: 8),
                    // Playback time display
                    Consumer<AudioProvider>(
                      builder: (context, audioProvider, _) {
                        final sample = _selectedSample;
                        if (sample == null) {
                          return Text(
                            '00:00:00 / 00:00:00',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          );
                        }
                        
                        // Only show playback time if this sample is actually playing
                        final isPlayingThis = audioProvider.isPlaying && audioProvider.playingSample?.id == sample.id;
                        
                        final start = sample.startTime;
                        final end = (sample.endTime > Duration.zero && sample.endTime < sample.duration)
                            ? sample.endTime
                            : sample.duration;
                        
                        if (isPlayingThis) {
                          // Show actual playback position when this sample is playing
                          final position = audioProvider.position + start;
                          return Text(
                            '${formatDuration(position)} / ${formatDuration(end)}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          );
                        } else {
                          // Show static time display when not playing
                          return Text(
                            '${formatDuration(start)} / ${formatDuration(end)}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          );
                        }
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          
          // Fader controls
          if (_selectedSample != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Gain Fader
                  Column(
                    children: [
                      Text(
                        'Gain',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _GainFader(
                        sample: _selectedSample!,
                        onValueTap: () => _promptSetGainDb(context),
                        onChanged: (newDb) {
                          final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
                          final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                          final updatedSample = _selectedSample!.copyWith(gainDb: newDb);
                          
                          sampleProvider.updateSample(updatedSample);
                          audioProvider.updateSampleGain(updatedSample);
                          setState(() {
                            _selectedSample = updatedSample;
                          });
                        },
                      ),
                    ],
                  ),
                  // Pitch Fader
                  Column(
                    children: [
                      Text(
                        'Pitch',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _PitchFader(
                        sample: _selectedSample!,
                        onValueTap: () => _promptSetPitchSemitones(context),
                        onChanged: (newPitch) {
                          final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
                          final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                          final updatedSample = _selectedSample!.copyWith(pitch: newPitch);
                          
                          sampleProvider.updateSample(updatedSample);
                          // Apply pitch change to currently playing audio
                          audioProvider.setPitch(newPitch);
                          setState(() {
                            _selectedSample = updatedSample;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, String tooltip) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey[700],
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: () {
          // TODO: Implement playback controls
        },
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildBottomPanel() {
    final hasSelectedSample = _selectedSample != null;
    // Temporary: get the first sample with waveformData
    final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
    AudioSample? debugSample;
    try {
      debugSample = sampleProvider.samples.firstWhere(
        (s) => s.waveformData != null && s.waveformData!.isNotEmpty,
      );
    } catch (e) {
      debugSample = null;
    }
    return Stack(
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Replace the time label Row with a CustomPaint for grid lines, labels, and playhead
                      SizedBox(
                        height: 20,
                        child: Consumer<AudioProvider>(
                          builder: (context, audioProvider, _) {
                            final sample = _selectedSample;
                            final duration = sample?.duration ?? Duration.zero;
                            final durationMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
                            final startFrac = (_selectedSample?.startTime.inMilliseconds ?? 0) / durationMs;
                            final endFrac = (_selectedSample?.endTime.inMilliseconds ?? 0) > 0 
                                ? (_selectedSample!.endTime.inMilliseconds / durationMs).clamp(0.0, 1.0)
                                : 1.0;
                            return GestureDetector(
                              onTapDown: (details) {
                                // Calculate position from tap
                                final RenderBox renderBox = context.findRenderObject() as RenderBox;
                                final localPosition = renderBox.globalToLocal(details.globalPosition);
                                final tapFrac = (localPosition.dx / renderBox.size.width).clamp(0.0, 1.0);
                                final clampedFrac = tapFrac.clamp(startFrac, endFrac);
                                
                                // Set playhead position
                                setState(() {
                                  _playheadPosition = clampedFrac;
                                  _playheadLockedToStart = false;
                                });
                                
                                // Seek to position
                                final seekPosition = Duration(milliseconds: (clampedFrac * durationMs).round());
                                audioProvider.seek(seekPosition);
                              },
                              child: SizedBox(
                                width: double.infinity,
                                height: 32,
                                child: CustomPaint(
                                  painter: _TimeGridPainter(
                                    duration: duration,
                                    position: _calculatePlayheadPosition(sample, audioProvider),
                                    trimStart: sample?.startTime,
                                    trimEnd: (sample != null && sample.endTime > Duration.zero) ? sample.endTime : null,
                                    labelStyle: TextStyle(
                                      color: hasSelectedSample ? Colors.grey : Colors.grey.withOpacity(0.3),
                                      fontSize: 10,
                                    ),
                                    formatDuration: formatDuration,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 1),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: hasSelectedSample
                                ? Colors.black.withOpacity(0.3)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Stack(
                            children: [
                              if (hasSelectedSample && _selectedSample!.waveformData != null && _selectedSample!.waveformData!.isNotEmpty)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 0),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final sliderPos = _gainSliderPositionForSample(_selectedSample!); // 0.0 - 1.0
                                        final double baseHeight = constraints.maxHeight;
                                        final double baseWidth = constraints.maxWidth;
                                        // Headroom-aware visual: keep full height at 0 dB (slider = 0.5),
                                        // increase density by scaling samples, not container height.
                                        final samples = _scaledWaveformSamplesForDisplay(_selectedSample!);
                                        // Height scales 0..baseHeight for visual feedback below 0 dB
                                        final double scaledHeight = sliderPos < 0.5 ? baseHeight * (2.0 * sliderPos) : baseHeight;
                                        return PolygonWaveform(
                                          samples: samples.isEmpty ? _selectedSample!.waveformData! : samples,
                                          height: scaledHeight,
                                          width: baseWidth,
                                          inactiveColor: Colors.white.withOpacity(0.4),
                                          activeColor: Colors.white,
                                          showActiveWaveform: false,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              if (hasSelectedSample)
                                _buildTrimHandles(context, _selectedSample!, hasSelectedSample),
                              if (_dragTooltipPosition != null && _dragTooltipText != null)
                                Positioned(
                                  left: _dragTooltipPosition!.dx,
                                  top: _dragTooltipPosition!.dy,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.8),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(_dragTooltipText!, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                    ),
                                  ),
                                ),
                              if (!hasSelectedSample)
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.graphic_eq,
                                        size: 48,
                                        color: Colors.grey.withOpacity(0.5),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Select a sample',
                                        style: TextStyle(
                                          color: Colors.grey.withOpacity(0.7),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageTab(String label, bool isActive) {
    return Consumer<SampleProvider>(
      builder: (context, sampleProvider, child) {
        final isCurrentPage = label == '+' ? false : sampleProvider.isCurrentPage(label);
        final canDelete = label != '+' && sampleProvider.canDeletePage(label);
        final customLabel = label == '+' ? '' : sampleProvider.getLabelForPage(label);
        
        return GestureDetector(
          onTap: () {
            if (label == '+') {
              // Add a new page dynamically
              sampleProvider.addNewPage();
            } else {
              // Switch to the selected page by letter
              sampleProvider.setPageByLetter(label);
            }
          },
          onLongPress: canDelete ? () {
            // Get the tap position for menu placement
            final RenderBox renderBox = context.findRenderObject() as RenderBox;
            final position = renderBox.localToGlobal(Offset.zero);
            _showPageContextMenu(context, label, sampleProvider, position, customLabel);
          } : null,
          child: Container(
            width: 32,
            height: 24,
            decoration: BoxDecoration(
              color: label == '+'
                  ? Colors.grey[700]?.withOpacity(0.25)
                  : (isCurrentPage ? Colors.yellow : Colors.grey[700]),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: label == '+'
                  ? const Icon(Icons.add, color: Colors.white, size: 18)
                  : (customLabel.isNotEmpty
                      ? Text(
                          customLabel,
                          style: TextStyle(
                            color: isCurrentPage ? Colors.black : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        )
                      : const SizedBox.shrink()),
            ),
          ),
        );
      },
    );
  }

  void _showSampleContextMenu(BuildContext context, AudioSample sample) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final position = button.localToGlobal(Offset.zero);
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy - 50,
        position.dx + 120,
        position.dy + 80,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'change_color',
          child: Row(
            children: [
              Icon(Icons.palette, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              const Text('Change Color'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.copy, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              const Text('Duplicate'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              const Text('Delete'),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == 'change_color') {
        await _showGridColorPicker(context, sample);
      } else if (value == 'duplicate') {
        final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
        sampleProvider.duplicateSample(sample.id);
      } else if (value == 'delete') {
        final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
        sampleProvider.deleteSample(sample.id);
      }
    });
  }

  Future<void> _showGridColorPicker(BuildContext context, AudioSample sample) async {
    final List<Color> colors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.indigo,
      Colors.purple,
      Colors.pink,
      Colors.teal,
      Colors.cyan,
      Colors.lime,
      Colors.amber,
      Colors.deepOrange,
      Colors.deepPurple,
      Colors.lightBlue,
      Colors.lightGreen,
    ];

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Color'),
        content: SizedBox(
          width: 300,
          height: 200,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: colors.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
                  sampleProvider.updateSampleColor(sample.id, colors[index].value);
                  Navigator.of(context).pop();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: colors[index],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showPageContextMenu(BuildContext context, String pageLetter, SampleProvider sampleProvider, Offset position, String currentLabel) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy - 50,
        position.dx + 32,
        position.dy + 24,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'set_label',
          child: Row(
            children: [
              Icon(Icons.edit, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              const Text('Set Label'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Text('Delete Page'),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == 'delete') {
        sampleProvider.deletePage(pageLetter);
      } else if (value == 'set_label') {
        final newLabel = await _showSetLabelDialog(context, currentLabel);
        if (newLabel != null) {
          sampleProvider.setLabelForPage(pageLetter, newLabel);
        }
      }
    });
  }

  Future<String?> _showSetLabelDialog(BuildContext context, String currentLabel) async {
    final controller = TextEditingController(text: currentLabel);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Page Label'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter label'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddSampleDialog(BuildContext context, {String? sampleId}) {
    // Go straight to file picker instead of showing dialog first
    _pickAudioFileAndCreateSample(context, sampleId: sampleId);
  }

  Future<void> _pickAudioFileAndCreateSample(BuildContext context, {String? sampleId}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final filePath = file.path;
        
        if (filePath != null) {
          // Create sample directly with default values
          await _createSampleFromFile(filePath, sampleId: sampleId);
        }
      }
    } catch (e) {
      // Handle error - could show a snackbar or dialog
    }
  }

  Future<void> _createSampleFromFile(String filePath, {String? sampleId}) async {
    final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
    
    // Get filename without extension for default name
    final fileName = filePath.split('/').last.split('.').first;

    // Generate waveform data and get actual duration
    final waveformData = await audioProvider.generateWaveformData(filePath);
    final actualDuration = await audioProvider.getAudioDuration(filePath);
    
    if (sampleId != null) {
      // Update existing blank sample
      await sampleProvider.updateBlankSample(
        sampleId,
        filePath,
        fileName,
        actualDuration,
        waveformData: waveformData,
      );
      // Auto-select only if nothing is currently playing
      final updatedSample = sampleProvider.getSampleById(sampleId);
      final audioProviderNow = Provider.of<AudioProvider>(context, listen: false);
      if (updatedSample != null && !audioProviderNow.isPlaying) {
        _selectSample(updatedSample);
      }
    } else {
      // Create new sample with default values
      final newSample = AudioSample(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: fileName,
        filePath: filePath,
        duration: actualDuration,
        category: 'General',
        notes: null,
        isBlank: false,
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        waveformData: waveformData,
      );
      await sampleProvider.addSample(newSample);
      // Auto-select only if nothing is currently playing
      final audioProviderNow = Provider.of<AudioProvider>(context, listen: false);
      if (!audioProviderNow.isPlaying) {
        _selectSample(newSample);
      }
    }
  }

  void _handleDragEnd(DraggableDetails details, AudioSample sample, SampleProvider sampleProvider) {
    // Get the screen size
    final screenSize = MediaQuery.of(context).size;
    final edgeThreshold = 20.0; // Distance from edge to trigger delete
    
    // Check if dragged to any edge of the screen
    final isNearLeftEdge = details.offset.dx < edgeThreshold;
    final isNearRightEdge = details.offset.dx > screenSize.width - edgeThreshold;
    final isNearTopEdge = details.offset.dy < edgeThreshold;
    final isNearBottomEdge = details.offset.dy > screenSize.height - edgeThreshold;
    
    if (isNearLeftEdge || isNearRightEdge || isNearTopEdge || isNearBottomEdge) {
      if (_showDeleteConfirmation) {
        _showDeleteConfirmationDialog(sample, sampleProvider);
      } else {
        // Delete directly without confirmation
        _deleteSample(sample, sampleProvider, false);
  }
    }
  }

  void _showDeleteConfirmationDialog(AudioSample sample, SampleProvider sampleProvider) {
    bool dontAskAgain = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Delete Sample'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to delete "${sample.name}"?'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: dontAskAgain,
                    onChanged: (value) {
                      setState(() {
                        dontAskAgain = value ?? false;
                      });
                    },
                  ),
                  const Expanded(
                    child: Text(
                      'Don\'t ask again',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteSample(sample, sampleProvider, dontAskAgain);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteSample(AudioSample sample, SampleProvider sampleProvider, bool dontAskAgain) {
    // Save the preference if user chose not to ask again
    if (dontAskAgain) {
      _saveDeleteConfirmationPreference(false);
    }
    
    // Clear selected sample if it's the one being deleted
    if (_selectedSample?.id == sample.id) {
      setState(() {
        _selectedSample = null;
      });
    }
    
    // Delete the sample
    sampleProvider.deleteSample(sample.id);
  }

  void _saveDeleteConfirmationPreference(bool showConfirmation) {
    // TODO: Implement preference saving
    // This would typically use SharedPreferences or similar
    // For now, we'll just store it in memory
    _showDeleteConfirmation = showConfirmation;
}

  bool _showDeleteConfirmation = true; // Default to showing confirmation

  Color _getSampleButtonColor(AudioSample sample) {
    if (sample.customColor != null) {
      return Color(sample.customColor!);
    }
    return Theme.of(context).colorScheme.outline.withOpacity(0.3);
  }

  Widget _buildTrimHandles(BuildContext context, AudioSample sample, bool hasSelectedSample) {
    final duration = sample.duration.inMilliseconds > 0 ? sample.duration : const Duration(seconds: 1);
    final durationMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
    final startFrac = _isDraggingStart && _draggingTrimStart != null
        ? _draggingTrimStart!
        : (sample.startTime.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final endFrac = _isDraggingEnd && _draggingTrimEnd != null
        ? _draggingTrimEnd!
        : (sample.endTime.inMilliseconds > 0
            ? (sample.endTime.inMilliseconds / durationMs).clamp(0.0, 1.0)
            : 1.0);
    
    // Calculate playhead position
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
    final bool isPlayingThis = audioProvider.isPlaying && audioProvider.playingSample?.id == sample.id;
    double playheadFrac;
    if (_playheadLockedToStart && !isPlayingThis) {
      playheadFrac = startFrac;
    } else {
      // Use actual playback position from AudioProvider
      final playbackPosition = audioProvider.position;
      final effectiveStart = (isPlayingThis && audioProvider.playingSample != null)
          ? audioProvider.playingSample!.startTime
          : sample.startTime;
      final absolutePosition = playbackPosition + effectiveStart;
      playheadFrac = (absolutePosition.inMilliseconds / durationMs);
    }
    // Only clamp to trim region when not playing; during playback, keep visual synced to audio
    if (!isPlayingThis) {
      playheadFrac = playheadFrac.clamp(startFrac, endFrac);
    } else {
      playheadFrac = playheadFrac.clamp(0.0, 1.0);
    }
    
    final panel = context.findRenderObject() as RenderBox?;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Set handleWidth to 2.0 (visible), but tappable area to 48.0
        final handleWidth = 2.0;
        final handleTapWidth = 48.0;
        final minFrac = _minTrimFraction;
        final minDistPx = minFrac * width;
        // Remove duplicate duration definition - use the one from outer scope
        // Remove duplicate startFrac and endFrac definitions - use the ones from outer scope
        final startPx = startFrac * width;
        final endPx = endFrac * width;
        return Stack(
          children: [
            // Trim overlay (exclude handle areas)
            Positioned(
              left: startPx + handleWidth,
              width: (endPx - handleWidth) - (startPx + handleWidth),
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.yellow.withOpacity(0.05),
                  border: Border.all(color: Colors.yellow, width: 1),
                ),
              ),
            ),
            // Playhead (visible when within container bounds)
            if (playheadFrac >= 0.0 && playheadFrac <= 1.0)
              Positioned(
                left: (playheadFrac * width) - 1.0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2.0,
                  color: Colors.blue,
                ),
              ),
            // Start handle
            Positioned(
              left: startPx.clamp(0.0, width - handleWidth),
              top: 0,
              bottom: 0,
              child: Container(
                width: handleTapWidth,
                color: Colors.transparent,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) {
                  // If playing this sample and the handle overlaps the playhead, stop playback
                  final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                  final playingThis = audioProvider.isPlaying && audioProvider.playingSample?.id == sample.id;
                  if (playingThis) {
                    final playheadX = (playheadFrac * width);
                    final handleLeft = startPx.clamp(0.0, width - handleWidth);
                    final handleRight = (handleLeft + handleTapWidth).clamp(0.0, width);
                    if (playheadX >= handleLeft && playheadX <= handleRight) {
                      audioProvider.stop();
                    }
                  }
                },
                onHorizontalDragStart: (details) {
                  setState(() {
                    _isDraggingStart = true;
                      _draggingTrimStartTime = Duration(milliseconds: (startFrac * durationMs).round());
                  });
                },
                onHorizontalDragUpdate: (details) {
                  final localX = (startPx + details.delta.dx).clamp(0.0, endPx - minDistPx);
                  final newFrac = (localX / width).clamp(0.0, endFrac - minFrac);
                  setState(() {
                    _draggingTrimStart = newFrac;
                      _draggingTrimStartTime = Duration(milliseconds: (newFrac * durationMs).round());
                    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                    final isPlayingThis = audioProvider.isPlaying && audioProvider.playingSample?.id == sample.id;
                    if (!isPlayingThis && _playheadLockedToStart) {
                      _playheadPosition = newFrac;
                    }
                  });
                },
                onHorizontalDragEnd: (details) async {
                  final newStartFrac = _draggingTrimStart ?? startFrac;
                  final newStart = Duration(milliseconds: (newStartFrac * durationMs).round());
                  final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
                  final updatedSample = sample.copyWith(startTime: newStart);
                  sampleProvider.updateSample(updatedSample);
                  // If playing this sample, adjust clip in-place to avoid reloading and audio glitches
                  final audioProviderTrim = Provider.of<AudioProvider>(context, listen: false);
                  final wasPlayingThis = audioProviderTrim.isPlaying && audioProviderTrim.playingSample?.id == sample.id;
                  if (wasPlayingThis) {
                    await audioProviderTrim.applyTrimRelativeForCurrent(
                      newStartAbs: newStart,
                      newEndAbs: sample.endTime > Duration.zero ? sample.endTime : duration,
                    );
                  }
                  setState(() {
                    _isDraggingStart = false;
                    _draggingTrimStart = null;
                    _dragTooltipPosition = null;
                    _dragTooltipText = null;
                      _draggingTrimStartTime = null;
                    _selectedSample = sampleProvider.getSampleById(sample.id);
                    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                    final isPlayingThis = audioProvider.isPlaying && audioProvider.playingSample?.id == sample.id;
                    if (!isPlayingThis) {
                      // If playhead is locked to start, follow new start trim
                      if (_playheadLockedToStart) {
                        _playheadPosition = newStartFrac;
                      }
                      // Clamp playhead to trim region
                      if (_playheadPosition != null && _playheadPosition! < newStartFrac) {
                        _playheadPosition = newStartFrac;
                      }
                      if (_playheadPosition != null && _playheadPosition! > endFrac) {
                        _playheadPosition = endFrac;
                      }
                    }
                  });
                  // If currently playing this sample and start moved beyond current absolute playhead, stop playback to avoid desync
                  final audioProviderAfter = Provider.of<AudioProvider>(context, listen: false);
                  final isPlayingThisAfter = audioProviderAfter.isPlaying && audioProviderAfter.playingSample?.id == sample.id;
                  if (isPlayingThisAfter) {
                    final playbackPositionMs = audioProviderAfter.position.inMilliseconds;
                    final currentAbsMs = playbackPositionMs + sample.startTime.inMilliseconds;
                    final newStartAbsMs = newStart.inMilliseconds + 0; // relative to 0
                    if (newStartAbsMs > currentAbsMs) {
                      audioProviderAfter.stop();
                    }
                  }
                  },
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Image.asset(
                        'assets/images/trim_handle_start.png',
                        width: handleWidth,
                        height: constraints.maxHeight,
                        fit: BoxFit.fitHeight,
                      ),
                      if (_isDraggingStart && _draggingTrimStartTime != null)
                        Positioned(
                          top: -32,
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                formatDuration(_draggingTrimStartTime!),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // End handle
            Positioned(
              left: endPx.clamp(0.0, width - handleWidth),
              top: 0,
              bottom: 0,
              child: Container(
                width: handleTapWidth,
                color: Colors.transparent,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) {
                  // If playing this sample and the handle overlaps the playhead, stop playback
                  final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                  final playingThis = audioProvider.isPlaying && audioProvider.playingSample?.id == sample.id;
                  if (playingThis) {
                    final playheadX = (playheadFrac * width);
                    final handleLeft = endPx.clamp(0.0, width - handleWidth);
                    final handleRight = (handleLeft + handleTapWidth).clamp(0.0, width);
                    if (playheadX >= handleLeft && playheadX <= handleRight) {
                      audioProvider.stop();
                    }
                  }
                },
                onHorizontalDragStart: (details) {
                  setState(() {
                    _isDraggingEnd = true;
                      _draggingTrimEndTime = Duration(milliseconds: (endFrac * durationMs).round());
                  });
                },
                onHorizontalDragUpdate: (details) {
                  final localX = (endPx + details.delta.dx).clamp(startPx + minDistPx, width);
                  final newFrac = (localX / width).clamp(startFrac + minFrac, 1.0);
                  setState(() {
                    _draggingTrimEnd = newFrac;
                      _draggingTrimEndTime = Duration(milliseconds: (newFrac * durationMs).round());
                    _dragTooltipPosition = Offset(localX, 0);
                      _dragTooltipText = formatDuration(Duration(milliseconds: (newFrac * durationMs).round()));
                    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                    final isPlayingThis = audioProvider.isPlaying && audioProvider.playingSample?.id == sample.id;
                    if (!isPlayingThis) {
                      // Clamp playhead to trim region
                      if (_playheadPosition != null && _playheadPosition! < startFrac) {
                        _playheadPosition = startFrac;
                      }
                      if (_playheadPosition != null && _playheadPosition! > newFrac) {
                        _playheadPosition = newFrac;
                      }
                    } else {
                      // Apply end trim live during playback to ensure immediate effect
                      final newEndAbs = Duration(milliseconds: (newFrac * durationMs).round());
                      // Only update end; keep current start as maintained by provider
                      audioProvider.applyTrimRelativeForCurrent(
                        newEndAbs: newEndAbs,
                      );
                    }
                  });
                },
                onHorizontalDragEnd: (details) async {
                  final newEndFrac = _draggingTrimEnd ?? endFrac;
                  // If the handle is at the far right, set endTime to duration exactly
                  final newEnd = (newEndFrac >= 0.999) ? duration : Duration(milliseconds: (newEndFrac * durationMs).round());
                  final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
                  final updatedSample = sample.copyWith(endTime: newEnd);
                  sampleProvider.updateSample(updatedSample);
                  // If playing this sample, adjust clip in-place to avoid reloading and audio glitches
                  final audioProviderTrim = Provider.of<AudioProvider>(context, listen: false);
                  final wasPlayingThis = audioProviderTrim.isPlaying && audioProviderTrim.playingSample?.id == sample.id;
                  if (wasPlayingThis) {
                    await audioProviderTrim.applyTrimRelativeForCurrent(
                      newEndAbs: newEnd,
                    );
                  }
                  setState(() {
                    _isDraggingEnd = false;
                    _draggingTrimEnd = null;
                    _dragTooltipPosition = null;
                    _dragTooltipText = null;
                    _draggingTrimEndTime = null;
                    _selectedSample = sampleProvider.getSampleById(sample.id);
                    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                    final isPlayingThis = audioProvider.isPlaying && audioProvider.playingSample?.id == sample.id;
                    if (!isPlayingThis) {
                      // Clamp playhead to trim region
                      if (_playheadPosition != null && _playheadPosition! < startFrac) {
                        _playheadPosition = startFrac;
                      }
                      if (_playheadPosition != null && _playheadPosition! > newEndFrac) {
                        _playheadPosition = newEndFrac;
                      }
                    }
                  });
                  // If currently playing this sample and end moved before current absolute playhead, stop playback to avoid desync
                  final audioProviderAfter = Provider.of<AudioProvider>(context, listen: false);
                  final isPlayingThisAfter = audioProviderAfter.isPlaying && audioProviderAfter.playingSample?.id == sample.id;
                  if (isPlayingThisAfter) {
                    final playbackPositionMs = audioProviderAfter.position.inMilliseconds;
                    final currentAbsMs = playbackPositionMs + sample.startTime.inMilliseconds;
                    final newEndAbsMs = newEnd.inMilliseconds + sample.startTime.inMilliseconds;
                    if (newEndAbsMs < currentAbsMs) {
                      audioProviderAfter.stop();
                    }
                  }
                },
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Image.asset(
                        'assets/images/trim_handle_end.png',
                        width: handleWidth,
                        height: constraints.maxHeight,
                        fit: BoxFit.fitHeight,
                      ),
                      if (_isDraggingEnd && _draggingTrimEndTime != null)
                        Positioned(
                          top: -32,
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                formatDuration(_draggingTrimEndTime!),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _selectSample(AudioSample sample) {
    setState(() {
      _selectedSample = sample;
      // Reset any in-progress trim drag state so handles reflect the new sample's trim
      _isDraggingStart = false;
      _isDraggingEnd = false;
      _draggingTrimStart = null;
      _draggingTrimEnd = null;
      _draggingTrimStartTime = null;
      _draggingTrimEndTime = null;
      _dragTooltipPosition = null;
      _dragTooltipText = null;
      if (_selectedSample != null) {
        // Initialize playhead to start of trim region
        final durationMs = _selectedSample!.duration.inMilliseconds;
        final startFrac = (_selectedSample!.startTime.inMilliseconds / (durationMs > 0 ? durationMs : 1)).clamp(0.0, 1.0);
        _playheadPosition = startFrac;
        _playheadLockedToStart = true;
      }
    });
    // Update AudioProvider current sample to reset baseline trim tracking
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
    audioProvider.setCurrentSample(sample);
  }

  Duration _calculatePlayheadPosition(AudioSample? sample, AudioProvider audioProvider) {
    if (sample == null) {
      return Duration.zero;
    }
    
    // Only show playhead if this sample is actually playing
    final bool isPlayingThis = audioProvider.isPlaying && audioProvider.playingSample?.id == sample.id;
    if (!isPlayingThis) {
      // Return a position that's outside the valid range to hide the playhead
      return Duration(milliseconds: -1);
    }
    
    final durationMs = sample.duration.inMilliseconds > 0 ? sample.duration.inMilliseconds : 1;
    
    // Use dragging values if currently dragging, otherwise use sample values
    final startFrac = _isDraggingStart && _draggingTrimStart != null
        ? _draggingTrimStart!
        : (sample.startTime.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final endFrac = _isDraggingEnd && _draggingTrimEnd != null
        ? _draggingTrimEnd!
        : (sample.endTime.inMilliseconds > 0
            ? (sample.endTime.inMilliseconds / durationMs).clamp(0.0, 1.0)
            : 1.0);
    
    // Calculate playhead position using same logic as waveform
    double playheadFrac;
    if (_playheadLockedToStart) {
      playheadFrac = startFrac;
    } else {
      // Use actual playback position; when playing, base on playingSample.startTime
      final playbackPosition = audioProvider.position;
      final effectiveStart = audioProvider.playingSample!.startTime;
      final absolutePosition = playbackPosition + effectiveStart;
      playheadFrac = (absolutePosition.inMilliseconds / durationMs);
    }
    // Allow free-running sync to audio when playing
    playheadFrac = playheadFrac.clamp(0.0, 1.0);
    
    // Convert back to absolute position
    return Duration(milliseconds: (playheadFrac * durationMs).round());
  }
}



class AddSampleDialog extends StatefulWidget {
  const AddSampleDialog({super.key, this.sampleId});

  final String? sampleId;

  @override
  State<AddSampleDialog> createState() => _AddSampleDialogState();
}

class _AddSampleDialogState extends State<AddSampleDialog> {
  final _nameController = TextEditingController();
  String _selectedCategory = 'General';
  final _notesController = TextEditingController();
  bool _isLoading = false;
  String? _selectedFilePath;

  @override
  void initState() {
    super.initState();
    if (widget.sampleId != null) {
      final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
      final sample = sampleProvider.getSampleById(widget.sampleId!);
      if (sample != null) {
        _nameController.text = sample.name;
        _selectedCategory = sample.category;
        _notesController.text = sample.notes ?? '';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.sampleId != null ? 'Add Audio to Sample' : 'Add New Sample'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Sample Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Consumer<SampleProvider>(
            builder: (context, sampleProvider, child) {
              return DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: sampleProvider.categories
                    .where((cat) => cat != 'All')
                    .map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  }
                },
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _pickAudioFile,
            icon: _isLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.audio_file),
            label: Text(_isLoading ? 'Loading...' : (_selectedFilePath != null ? 'Change Audio File' : 'Select Audio File')),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          if (_selectedFilePath != null) ...[
            const SizedBox(height: 8),
            Text(
              'File selected: ${_selectedFilePath!.split('/').last}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedFilePath != null ? _saveSample : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _pickAudioFile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // TODO: Implement file picker
      // This would use file_picker package to select audio files
      // For now, simulate file selection
      await Future.delayed(const Duration(seconds: 1));
      _selectedFilePath = '/path/to/selected/audio/file.mp3';
    } catch (e) {
      // Handle error
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSample() async {
    if (_selectedFilePath == null) return;

    final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
    
    // Generate waveform data and get actual duration
    final waveformData = await audioProvider.generateWaveformData(_selectedFilePath!);
    final actualDuration = await audioProvider.getAudioDuration(_selectedFilePath!);
    
    if (widget.sampleId != null) {
      // Update existing blank sample
      await sampleProvider.updateBlankSample(
        widget.sampleId!,
        _selectedFilePath!,
        _nameController.text.trim(),
        actualDuration,
        waveformData: waveformData,
      );
    } else {
      // Create new sample (not blank)
      final newSample = AudioSample(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        filePath: _selectedFilePath!,
        duration: actualDuration,
        category: _selectedCategory,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        isBlank: false,
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        waveformData: waveformData,
      );
      await sampleProvider.addSample(newSample);
    }

    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}



class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // TODO: Add settings options
          Text('Settings coming soon...'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
} 

class _EditableSampleName extends StatefulWidget {
  final AudioSample sample;
  final Future<void> Function(BuildContext, AudioSample) onColorPicker;
  const _EditableSampleName({required this.sample, required this.onColorPicker});

  @override
  State<_EditableSampleName> createState() => _EditableSampleNameState();
}

class _EditableSampleNameState extends State<_EditableSampleName> {
  late TextEditingController _controller;
  bool _editing = false;

  // Use the same contrast logic as SampleButton for consistency
  static const double _luminanceCutoverForBlack = 1; // higher -> more white overall
  static const double _minWhiteContrast = 1.6; // allow softer contrast to favor white look
  static const double _desatThreshold = 0.12; // treat as grey if saturation <= this
  static const double _veryLightLuminance = 0.92; // only use black on very light greys

  Color _bestForegroundOn(
    Color background, {
    Color light = Colors.white,
    Color dark = Colors.black,
  }) {
    final double bgL = background.computeLuminance(); // 0..1
    final double contrastWithWhite = (1.0 + 0.05) / (bgL + 0.05);
    // If color is desaturated (grey-ish), bias towards white unless it's a very light grey
    final hsl = HSLColor.fromColor(background);
    if (hsl.saturation <= _desatThreshold) {
      return (bgL < _veryLightLuminance) ? light : dark;
    }
    // Otherwise, prefer white unless background is very light OR white contrast is extremely poor
    final bool useWhite = (bgL < _luminanceCutoverForBlack) && (contrastWithWhite >= _minWhiteContrast);
    return useWhite ? light : dark;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.sample.name);
  }

  @override
  void didUpdateWidget(covariant _EditableSampleName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sample.name != widget.sample.name) {
      _controller.text = widget.sample.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveName() {
    final newName = _controller.text.trim();
    if (newName.isNotEmpty && newName != widget.sample.name) {
      final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
      sampleProvider.updateSample(widget.sample.copyWith(name: newName));
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final panelColor = Theme.of(context).colorScheme.surface;
    return Selector<SampleProvider, AudioSample?>(
      selector: (context, sampleProvider) => sampleProvider.getSampleById(widget.sample.id),
      builder: (context, selectedSample, _) {
        Color fillColor;
        if (selectedSample != null && selectedSample.customColor != null) {
          fillColor = Color(selectedSample.customColor!);
        } else {
          fillColor = Theme.of(context).colorScheme.outline.withOpacity(0.3);
        }
        // Force white on default fill for active samples without custom color (same as sample button)
        Color textColor;
        if (selectedSample != null && !selectedSample.isBlank && selectedSample.customColor == null) {
          textColor = Colors.white;
        } else {
          textColor = _bestForegroundOn(fillColor);
        }
        return Row(
          children: [
            // Label text field
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _editing = true),
                child: AbsorbPointer(
                  absorbing: !_editing,
                  child: TextField(
                    controller: _controller,
                    readOnly: !_editing,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      filled: true,
                      fillColor: fillColor,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(6),
                          bottomLeft: Radius.circular(6),
                          topRight: Radius.circular(0),
                          bottomRight: Radius.circular(0),
                        ),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _saveName(),
                    onEditingComplete: _saveName,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            // Color picker button
            SizedBox(
              width: 48,
              height: 36,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(0),
                      bottomLeft: Radius.circular(0),
                      topRight: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  backgroundColor: fillColor,
                  foregroundColor: selectedSample != null && !selectedSample.isBlank && selectedSample.customColor == null
                      ? Colors.white
                      : _bestForegroundOn(fillColor),
                  elevation: 0,
                ),
                onPressed: selectedSample != null && !selectedSample.isBlank
                    ? () async {
                        await widget.onColorPicker(context, selectedSample);
                      }
                    : null,
                child: const Icon(Icons.palette, size: 20),
              ),
            ),
          ],
        );
      },
    );
  }
} 

Widget _buildRectControlButton(
  IconData icon,
  String tooltip, {
  required VoidCallback? onPressed,
  bool enabled = true,
}) {
  return SizedBox(
    width: 48,
    height: 36,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: EdgeInsets.zero,
        backgroundColor: enabled ? Colors.grey[700] : Colors.grey[800],
        foregroundColor: enabled ? Colors.white : Colors.grey[500],
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Icon(icon, size: 20),
    ),
  );
} 



// Update _TimeGridPainter to accept startTime and endTime
class _TimeGridPainter extends CustomPainter {
  final Duration duration;
  final Duration position;
  final Duration? trimStart;
  final Duration? trimEnd;
  final TextStyle labelStyle;
  final String Function(Duration) formatDuration;
  final int numLabels;
  final Color gridColor;

  _TimeGridPainter({
    required this.duration,
    required this.position,
    this.trimStart,
    this.trimEnd,
    required this.labelStyle,
    required this.formatDuration,
    this.numLabels = 10,
    this.gridColor = const Color(0xFF888888),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;
    final double durationMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final Paint gridPaint = Paint()
      ..color = gridColor.withOpacity(0.5)
      ..strokeWidth = 1;
    final Paint playheadPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2;

    // Draw grid lines and labels
    for (int i = 0; i <= numLabels; i++) {
      final double frac = i / numLabels;
      final double x = frac * width;
      canvas.drawLine(Offset(x, 0), Offset(x, height - 2), gridPaint);
      if (i < numLabels) {
        final labelMs = (durationMs * frac).clamp(0, durationMs);
        final label = formatDuration(Duration(milliseconds: labelMs.round()));
        final tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr,
        );
        tp.layout(minWidth: 0, maxWidth: 48);
        double labelX = x + 4;
        if (labelX + tp.width > width) labelX = width - tp.width;
        tp.paint(canvas, Offset(labelX, height - tp.height));
      }
    }

    // Draw playhead (same logic as waveform area)
    final trimStartMs = trimStart?.inMilliseconds ?? 0;
    final trimEndMs = (trimEnd != null && trimEnd!.inMilliseconds > 0) ? trimEnd!.inMilliseconds : duration.inMilliseconds;
    final posMs = position.inMilliseconds;
    
    // Don't draw playhead if position is negative (indicating no playhead should be shown)
    if (posMs < 0) {
      return;
    }
    
    // Calculate playhead position relative to trim region
    final trimStartFrac = trimStartMs / durationMs;
    final trimEndFrac = trimEndMs / durationMs;
    final playheadFrac = (posMs - trimStartMs) / (trimEndMs - trimStartMs);
    
    // Only draw if within trim region
    if (playheadFrac >= 0.0 && playheadFrac <= 1.0 && duration.inMilliseconds > 0) {
      final playheadX = (trimStartFrac + playheadFrac * (trimEndFrac - trimStartFrac)) * width;
      canvas.drawLine(Offset(playheadX, 0), Offset(playheadX, height), playheadPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimeGridPainter oldDelegate) {
    return duration != oldDelegate.duration ||
        position != oldDelegate.position ||
        labelStyle != oldDelegate.labelStyle ||
        trimStart != oldDelegate.trimStart ||
        trimEnd != oldDelegate.trimEnd;
  }
} 

class _RectangularThumbShape extends SliderComponentShape {
  const _RectangularThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(8.0, 20.0);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Paint paint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.blue
      ..style = PaintingStyle.fill;

    // Draw a rectangular thumb
    final Rect rect = Rect.fromCenter(
      center: center,
      width: 8.0,
      height: 20.0,
    );
    canvas.drawRect(rect, paint);
  }
}

class _RectangularOverlayShape extends SliderComponentShape {
  const _RectangularOverlayShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(16.0, 28.0);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Paint paint = Paint()
      ..color = (sliderTheme.thumbColor ?? Colors.blue).withOpacity(0.2)
      ..style = PaintingStyle.fill;

    // Draw a rectangular overlay
    final Rect rect = Rect.fromCenter(
      center: center,
      width: 16.0,
      height: 28.0,
    );
    canvas.drawRect(rect, paint);
  }
} 

class _PitchFader extends StatelessWidget {
  final AudioSample sample;
  final ValueChanged<double> onChanged;
  final VoidCallback? onValueTap;
  static const double minSemitones = -12.0; // -1 octave
  static const double maxSemitones = 12.0; // +1 octave
  static const double centerSemitones = 0.0; // No change

  const _PitchFader({required this.sample, required this.onChanged, this.onValueTap, Key? key}) : super(key: key);

  // Convert semitones to pitch multiplier
  double _semitonesToPitch(double semitones) {
    return pow(2.0, semitones / 12.0).toDouble();
  }

  // Convert pitch multiplier to semitones
  double _pitchToSemitones(double pitch) {
    return 12.0 * log(pitch) / log(2.0);
  }

  @override
  Widget build(BuildContext context) {
    // Convert current pitch to semitones
    final currentSemitones = _pitchToSemitones(sample.pitch);
    
    // LINEAR SEMITONE MAPPING (Centered at 0 semitones):
    // Map semitone value (-12 to +12) to slider position (0.0 to 1.0)
    // Center at 0 semitones (no change)
    double sliderPos;
    if (currentSemitones <= centerSemitones) {
      // Map -12 to 0 semitones range to slider 0.0 to 0.5
      sliderPos = 0.5 * ((currentSemitones - minSemitones) / (centerSemitones - minSemitones)).clamp(0.0, 1.0);
    } else {
      // Map 0 to +12 semitones range to slider 0.5 to 1.0
      sliderPos = 0.5 + 0.5 * ((currentSemitones - centerSemitones) / (maxSemitones - centerSemitones)).clamp(0.0, 1.0);
    }
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 140,
          child: RotatedBox(
            quarterTurns: -1,
                          child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const _RectangularThumbShape(),
                  overlayShape: const _RectangularOverlayShape(),
                  activeTrackColor: Colors.grey[700], // Same as inactive to remove fill color
                  inactiveTrackColor: Colors.grey[700],
                  thumbColor: Colors.grey[400], // No color changes for pitch
                ),
              child: Slider(
                value: sliderPos,
                min: 0,
                max: 1,
                onChanged: (pos) {
                  // Map slider position (0.0-1.0) to semitone value with center at 0
                  double semitones;
                  if (pos < 0.5) {
                    // Map slider 0.0-0.5 to semitones -12 to 0
                    semitones = minSemitones + (centerSemitones - minSemitones) * (pos / 0.5);
                  } else {
                    // Map slider 0.5-1.0 to semitones 0 to +12
                    semitones = centerSemitones + (maxSemitones - centerSemitones) * ((pos - 0.5) / 0.5);
                  }
                  
                  // Latch to 0 when close to center (within ±0.05 slider range)
                  const double latchThreshold = 0.05;
                  if ((pos - 0.5).abs() < latchThreshold) {
                    semitones = centerSemitones; // Snap to exactly 0 semitones (no change)
                    print('[PitchFader] Latched to 0 semitones (no change)');
                  }
                  
                  // Convert semitones to pitch multiplier
                  final pitch = _semitonesToPitch(semitones);
                  
                  print('[PitchFader] Slider pos: ${pos.toStringAsFixed(3)} → Semitones: ${semitones.toStringAsFixed(1)} → Pitch: ${pitch.toStringAsFixed(3)}');
                  
                  onChanged(pitch);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onValueTap,
          child: Text(
            '${_pitchToSemitones(sample.pitch).toStringAsFixed(0)} st',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[400], // No color changes for pitch
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _GainFader extends StatelessWidget {
  final AudioSample sample;
  final ValueChanged<double> onChanged;
  final VoidCallback? onValueTap;
  static const double minDb = -48.0;
  static const double maxDb = 12.0;
  static const double centerDb = 0.0; // Unity gain at center

  const _GainFader({required this.sample, required this.onChanged, this.onValueTap, Key? key}) : super(key: key);

  Color _colorForDb(double db) {
    if (db > 6) return Colors.red;
    if (db > 0) return Colors.yellow[700]!;
    return Colors.green[600]!;
  }

  @override
  Widget build(BuildContext context) {
    // LOGARITHMIC FADER MAPPING (Centered at Unity Gain):
    // 1. Map current dB value to slider position (0.0 to 1.0)
    //    For values below center: slider_pos = 0.5 * (gainDb - minDb) / (centerDb - minDb)
    //    For values above center: slider_pos = 0.5 + 0.5 * (gainDb - centerDb) / (maxDb - centerDb)
    // 2. When fader moves, map slider position back to dB:
    //    For slider < 0.5: db_value = minDb + (centerDb - minDb) * (slider_pos / 0.5)
    //    For slider >= 0.5: db_value = centerDb + (maxDb - centerDb) * ((slider_pos - 0.5) / 0.5)
    // 3. Convert dB to amplitude: amplitude = pow(10.0, db_value / 20.0)
    
    double sliderPos;
    if (sample.gainDb <= centerDb) {
      // Map -96 dB to 0 dB range to slider 0.0 to 0.5
      sliderPos = 0.5 * ((sample.gainDb - minDb) / (centerDb - minDb)).clamp(0.0, 1.0);
    } else {
      // Map 0 dB to +12 dB range to slider 0.5 to 1.0
      sliderPos = 0.5 + 0.5 * ((sample.gainDb - centerDb) / (maxDb - centerDb)).clamp(0.0, 1.0);
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 140,
          child: RotatedBox(
            quarterTurns: -1,
                          child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const _RectangularThumbShape(),
                  overlayShape: const _RectangularOverlayShape(),
                  activeTrackColor: _colorForDb(sample.gainDb), // Lighter grey for active fill
                  inactiveTrackColor: Colors.grey[700],
                  thumbColor: Colors.grey[300], // Same grey as active track
                ),
              child: Slider(
                value: sliderPos,
                min: 0,
                max: 1,
                onChanged: (pos) {
                  // Map slider position (0.0-1.0) to dB value with center at 0 dB
                  double db;
                  if (pos < 0.5) {
                    // Map slider 0.0-0.5 to dB -96 to 0
                    db = minDb + (centerDb - minDb) * (pos / 0.5);
                  } else {
                    // Map slider 0.5-1.0 to dB 0 to +12
                    db = centerDb + (maxDb - centerDb) * ((pos - 0.5) / 0.5);
                  }
                  
                  // Latch to 0 dB when close to center (within ±0.05 slider range)
                  const double latchThreshold = 0.05;
                  if ((pos - 0.5).abs() < latchThreshold) {
                    db = centerDb; // Snap to exactly 0 dB
                    print('[GainFader] Latched to 0 dB (unity gain)');
                  }
                  
                  // Debug: Log the mapping for verification
                  final amplitude = pow(10.0, db / 20.0);
                  print('[GainFader] Slider pos: ${pos.toStringAsFixed(3)} → dB: ${db.toStringAsFixed(1)} → Amplitude: ${amplitude.toStringAsFixed(6)}');
                  
                  onChanged(db);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onValueTap,
          child: Text(
            '${sample.gainDb.toStringAsFixed(1)} dB',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _colorForDb(sample.gainDb),
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
} 