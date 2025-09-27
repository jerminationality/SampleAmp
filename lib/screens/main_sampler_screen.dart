
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart'; // ignore: unused_import
import 'package:flutter_colorpicker/flutter_colorpicker.dart'; // ignore: unused_import
import 'package:file_picker/file_picker.dart';
import 'package:flutter_oknob/flutter_oldschool_knob.dart'; // ignore: unused_import
import 'package:flutter_oknob/widgets/flutter_widget_painter.dart'; // ignore: unused_import
import 'package:live_audio_sampler/providers/audio_provider.dart';
import 'package:live_audio_sampler/providers/sample_provider.dart';
import 'package:live_audio_sampler/models/audio_sample.dart';
import 'package:live_audio_sampler/widgets/sample_grid.dart'; // ignore: unused_import
import 'package:live_audio_sampler/widgets/effects_panel.dart'; // ignore: unused_import
import 'package:live_audio_sampler/widgets/transport_controls.dart'; // ignore: unused_import
import 'package:live_audio_sampler/widgets/sample_button.dart';
import 'package:live_audio_sampler/utils.dart';

// Painter to draw the chamfered trim region (fill + 1px yellow border)
class _TrimRegionPainter extends CustomPainter {
  final double startFrac; // 0..1
  final double endFrac;   // 0..1
  final Color fillColor;
  final Color borderColor;
  final double chamfer;      // not used in this variant; kept for API compatibility
  final double borderWidth;  // in px

  const _TrimRegionPainter({
    required this.startFrac,
    required this.endFrac,
    required this.fillColor,
    required this.borderColor,
    this.chamfer = 8.0,
    this.borderWidth = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    // Clamp to safe range
    final double l = (startFrac.clamp(0.0, 1.0)) * width;
    final double r = (endFrac.clamp(0.0, 1.0)) * width;
    if (r <= l) return;

    // Darken area OUTSIDE the trim window to emphasize the active (trimmed) region
    final Paint dimPaint = Paint()
      ..isAntiAlias = false
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    if (l > 0) {
      canvas.drawRect(Rect.fromLTRB(0, 0, l, height), dimPaint);
    }
    if (r < width) {
      canvas.drawRect(Rect.fromLTRB(r, 0, width, height), dimPaint);
    }

    // 1) Draw rectangular region (no cutouts)
    final rect = Rect.fromLTRB(l, 0, r, height);
    final fillPaint = Paint()
      ..isAntiAlias = true
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    final strokePaint = Paint()
      ..isAntiAlias = true
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, strokePaint);

    // 2) Draw fixed-size yellow triangle markers strictly clipped to the region rect
    //    so nothing can render outside the yellow border.
    final double mark = (height * 0.12).clamp(10.0, 14.0); // fixed proportionate size
    final Paint markerFill = Paint()
      ..isAntiAlias = true
      ..color = borderColor
      ..style = PaintingStyle.fill;
    final Paint markerStroke = Paint()
      ..isAntiAlias = true
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.clipRect(rect);

    // Left-top triangle (inside the rect)
    Path lt = Path()
      ..moveTo(l + mark, 0)
      ..lineTo(l, mark)
      ..lineTo(l, 0)
      ..close();
    canvas.drawPath(lt, markerFill);
    canvas.drawPath(lt, markerStroke);

    // Left-bottom triangle
    Path lb = Path()
      ..moveTo(l + mark, height)
      ..lineTo(l, height - mark)
      ..lineTo(l, height)
      ..close();
    canvas.drawPath(lb, markerFill);
    canvas.drawPath(lb, markerStroke);

    // Right-top triangle
    Path rt = Path()
      ..moveTo(r - mark, 0)
      ..lineTo(r, mark)
      ..lineTo(r, 0)
      ..close();
    canvas.drawPath(rt, markerFill);
    canvas.drawPath(rt, markerStroke);

    // Right-bottom triangle
    Path rb = Path()
      ..moveTo(r - mark, height)
      ..lineTo(r, height - mark)
      ..lineTo(r, height)
      ..close();
    canvas.drawPath(rb, markerFill);
    canvas.drawPath(rb, markerStroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TrimRegionPainter oldDelegate) {
    return startFrac != oldDelegate.startFrac ||
        endFrac != oldDelegate.endFrac ||
        fillColor != oldDelegate.fillColor ||
        borderColor != oldDelegate.borderColor ||
        chamfer != oldDelegate.chamfer ||
        borderWidth != oldDelegate.borderWidth;
  }
}


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
  // Time-display tooltip state (kept for now; may be removed if tap-only without tooltip)
  Offset? _timeTooltipPosition;
  String? _timeTooltipText;
  static const double _minTrimFraction = 0.02;
  double? _playheadPosition; // 0.0-1.0 relative to waveform
  bool _playheadLockedToStart = true;
  Duration? _draggingTrimStartTime;
  Duration? _draggingTrimEndTime;
  // Removed time display drag tooltip state (tap-to-seek only)
  // Track drag bases and accumulated deltas so handle follows finger precisely
  double _dragStartBasePxStart = 0.0;
  double _dragAccumDxStart = 0.0;
  double _dragStartBasePxEnd = 0.0;
  double _dragAccumDxEnd = 0.0;
  // Whether the user explicitly sought in the time window; governs playhead visibility when not playing
  bool _userHasSought = false;
  // Keys to unify playhead rendering across time bar and waveform area
  final GlobalKey _panelStackKey = GlobalKey();
  final GlobalKey _timeBarKey = GlobalKey();
  final GlobalKey _waveformKey = GlobalKey();

  Rect? _rectFor(GlobalKey childKey, GlobalKey ancestorKey) {
    final ctx = childKey.currentContext;
    final anc = ancestorKey.currentContext;
    if (ctx == null || anc == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    final ancBox = anc.findRenderObject() as RenderBox?;
    if (box == null || ancBox == null || !box.hasSize || !ancBox.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: ancBox);
    return topLeft & box.size;
  }

  // Cache provider refs for safe listener removal in dispose
  AudioProvider? _audioProviderRef;
  SampleProvider? _sampleProviderRef;

  @override
  void initState() {
    super.initState();
    // Add listeners after first frame and cache provider refs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sampleProviderRef = Provider.of<SampleProvider>(context, listen: false);
      _sampleProviderRef!.addListener(_checkSelectedSampleExists);

      _audioProviderRef = Provider.of<AudioProvider>(context, listen: false);
      _audioProviderRef!.addListener(_handleAudioProviderUpdate);
    });
  }

  @override
  void dispose() {
    _audioProviderRef?.removeListener(_handleAudioProviderUpdate);
    _sampleProviderRef?.removeListener(_checkSelectedSampleExists);
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
      } else {
        // Keep local selected sample fresh so UI reflects async updates (e.g., waveform loading)
        final updated = sampleProvider.getSampleById(_selectedSample!.id);
        if (updated != null && updated != _selectedSample) {
          setState(() {
            _selectedSample = updated;
          });
        }
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
      // If engine is at the beginning, treat as defaulted state → hide playhead until user seeks
      // This covers initialization and post-finish reset.
      if (audioProvider.position.inMilliseconds <= 0) {
        setState(() {
          _playheadPosition = null;
          _userHasSought = false;
        });
      }
    }
    // Trigger a repaint so time bars/playhead update
    setState(() {});
  }

  // Quick helper: convert semitones <-> pitch
  double _semitonesToPitch(double semitones) => pow(2.0, semitones / 12.0).toDouble();
  double _pitchToSemitones(double pitch) => 12.0 * log(pitch) / log(2.0);

  Future<void> _promptSetPitchSemitones(BuildContext context) async {
    if (_selectedSample == null) return;
    final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
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

  // ---- Gain helpers ----
  // Gain bounds used by the gain dialog
  static const double _gainMinDb = -48.0;
  static const double _gainMaxDb = 12.0;

  // Removed unused _gainSliderPositionForSample helper.

  // removed unused _scaledWaveformSamplesForDisplay

  Future<void> _promptSetGainDb(BuildContext context) async {
    if (_selectedSample == null) return;
    final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
    final controller = TextEditingController(text: _selectedSample!.gainDb.toStringAsFixed(1));

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Set Gain (dB)'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
            decoration: const InputDecoration(hintText: 'Range: -48.0 to +12.0 dB'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.trim());
                if (parsed == null) {
                  Navigator.of(ctx).pop();
                  return;
                }
                final clamped = parsed.clamp(_gainMinDb, _gainMaxDb);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
  backgroundColor: Theme.of(context).colorScheme.surface,
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
                  Expanded(
                    flex: 2,
                    child: _buildLeftPanel(),
                  ),
                  const SizedBox(width: 4),
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
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                ),
                // Inner grid handles its own padding; avoid extra padding here
                child: _buildSampleGrid(),
              ),
            ),
            // Tab buttons at the very bottom (separate from grid background)
            Container(
              padding: const EdgeInsets.only(top: 0, left: 12, right: 12, bottom: 0),
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

  // (removed) _getDisplayTextForSample was unused

  Widget _buildSampleGrid() {
  // Responsive grid: tablet default 6x4 (24), phone (any orientation) 6x2 (12)
    final media = MediaQuery.of(context);
    final bool isPhone = media.size.shortestSide < 600;
  final int cols = isPhone ? 6 : 6;
  final int rows = isPhone ? 2 : 4;
    final int totalSlots = cols * rows;
    return LayoutBuilder(
      builder: (context, constraints) {
  // Calculate button size to fit grid in panel (uniform padding on all sides)
  // Clamp to avoid negative sizes on very small layouts
  final double spacingDefault = isPhone ? 4 : 6;
  final double gridPadding = isPhone ? 8 : 12;
  final double safeW = max(0.0, constraints.maxWidth);
  final double safeH = max(0.0, constraints.maxHeight);
  final double gridWidth = max(0.0, safeW - 2 * gridPadding);
  final double gridHeight = max(0.0, safeH - 2 * gridPadding);
  // Adapt spacing if the grid is very small to avoid negative tile sizes
  final double spacingX = min(spacingDefault, (cols > 1) ? (gridWidth / (cols - 1 + 1e-6)) : spacingDefault);
  final double spacingY = min(spacingDefault, (rows > 1) ? (gridHeight / (rows - 1 + 1e-6)) : spacingDefault);
  final double buttonWidthNumerator = max(0.0, gridWidth - (cols - 1) * spacingX);
  final double buttonHeightNumerator = max(0.0, gridHeight - (rows - 1) * spacingY);
  final double buttonWidth = buttonWidthNumerator / cols;
  // Remove extra height fudge to avoid unintended top gap; ensure rows fill available height
  final double buttonHeight = buttonHeightNumerator / rows;
  // Ensure a positive aspect ratio for grid tiles
  final double safeButtonW = buttonWidth > 0 ? buttonWidth : 1.0;
  final double safeButtonH = buttonHeight > 0 ? buttonHeight : 1.0;
  final double childAspect = safeButtonW / safeButtonH;
        return Padding(
          padding: EdgeInsets.fromLTRB(gridPadding, gridPadding, gridPadding, gridPadding),
          child: Consumer<SampleProvider>(
            builder: (context, sampleProvider, child) {
              final samples = sampleProvider.currentPageSamples;
              return GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
      crossAxisSpacing: spacingX,
      mainAxisSpacing: spacingY,
      childAspectRatio: childAspect,
                ),
                itemCount: totalSlots,
                itemBuilder: (context, index) {
                  if (index < samples.length) {
                    final sample = samples[index];
                    return DragTarget<AudioSample>(
                      onWillAcceptWithDetails: (details) {
                        final data = details.data;
                        return data.id != sample.id;
                      },
                      onAcceptWithDetails: (details) {
                        final data = details.data;
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
            width: max(0.0, buttonWidth),
            height: max(0.0, buttonHeight),
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
          width: max(0.0, buttonWidth),
          height: max(0.0, buttonHeight),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.grey.withValues(alpha: 0.5),
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
          width: max(0.0, buttonWidth),
          height: max(0.0, buttonHeight),
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
        return _buildAddButton(width: max(0.0, buttonWidth), height: max(0.0, buttonHeight));
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

  // (removed) _buildSampleButton was unused

  // (removed) _buildDraggableSampleButton was unused

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
          color: (Colors.grey[800] ?? Colors.grey).withValues(alpha: 0.25),
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
          // Top: sample label/color and playback buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Label + color picker (full width)
                Consumer<SampleProvider>(
                  builder: (context, sampleProvider, child) {
                    final selectedSample = _selectedSample;
                    if (selectedSample != null) {
                      return _EditableSampleName(
                        sample: selectedSample,
                        onColorPicker: _showGridColorPicker,
                      );
                    }
                    // Disabled shell when nothing selected
                    final disabledBgColor = Colors.grey[900];
                    return Row(
                      children: [
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
                const SizedBox(height: 8),
                // Playback buttons row
                Consumer<AudioProvider>(
                  builder: (context, audioProvider, _) {
                    final hasSelectedSample = _selectedSample != null;
                    final isLoadingSel = hasSelectedSample && (_selectedSample!.isWaveformLoading);
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildRectControlButton(
                          Icons.first_page,
                          'Rewind',
                          onPressed: hasSelectedSample && !isLoadingSel
                              ? () async {
                                  audioProvider.seek(Duration.zero);
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
                          enabled: hasSelectedSample && !isLoadingSel,
                        ),
                        const SizedBox(width: 2),
                        _buildRectControlButton(
                          Icons.play_arrow,
                          'Play',
                          onPressed: hasSelectedSample && !isLoadingSel
                              ? () async {
                                  final sel = _selectedSample;
                                  if (sel != null) {
                                    if (audioProvider.currentSample?.id == sel.id) {
                                      await audioProvider.play();
                                    } else {
                                      await audioProvider.playSample(sel);
                                    }
                                    setState(() {
                                      _playheadLockedToStart = false;
                                    });
                                  }
                                }
                              : null,
                          enabled: hasSelectedSample && !isLoadingSel,
                        ),
                        const SizedBox(width: 2),
                        _buildRectControlButton(
                          Icons.pause,
                          'Pause',
                          onPressed: hasSelectedSample && !isLoadingSel
                              ? () async {
                                  await audioProvider.pause();
                                }
                              : null,
                          enabled: hasSelectedSample && !isLoadingSel,
                        ),
                        const SizedBox(width: 2),
                        _buildRectControlButton(
                          Icons.stop,
                          'Stop',
                          onPressed: hasSelectedSample && !isLoadingSel
                              ? () async {
                                  await audioProvider.stop();
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
                          enabled: hasSelectedSample && !isLoadingSel,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          
          // Playback clock retained but hidden for now (kept for future use)
          Offstage(
            offstage: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Consumer<AudioProvider>(
                builder: (context, audioProvider, _) {
                  final sample = _selectedSample;
                  final text = (sample == null)
                      ? '00:00:00 / 00:00:00'
                      : '${formatDuration(sample.startTime)} / ${formatDuration((sample.endTime > Duration.zero && sample.endTime < sample.duration) ? sample.endTime : sample.duration)}';
                  return Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  );
                },
              ),
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

  // (removed) _buildControlButton was unused

  Widget _buildBottomPanel() {
    final hasSelectedSample = _selectedSample != null;
  // (removed) unused debugSample lookup
    return Stack(
      key: _panelStackKey,
      children: [
        Container(
          // Responsive height: shorter on phone landscape
          // Tablet/desktop: 240; Phone landscape: 140
          height: () {
            final media = MediaQuery.of(context);
            final bool isLandscape = media.orientation == Orientation.landscape;
            final bool isPhone = media.size.shortestSide < 600;
            return (isPhone && isLandscape) ? 140.0 : 240.0;
          }(),
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
                        key: _timeBarKey,
                        height: 20,
                        child: Consumer<AudioProvider>(
                          builder: (context, audioProvider, _) {
                            final sample = _selectedSample;
                            final duration = sample?.duration ?? Duration.zero;
                            final durationMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
                            // Tap/drag clamping computed inside inner GestureDetector using sample times
                            return StatefulBuilder(
                                builder: (context, setInnerState) {
                                  return GestureDetector(
                                    onTapDown: (details) {
                                      if (sample == null) return;
                                      final renderBox = context.findRenderObject() as RenderBox;
                                      final local = details.localPosition;
                                      final width = renderBox.size.width;
                                      final dx = local.dx.clamp(0.0, width);
                                      final startFrac = (sample.startTime.inMilliseconds / durationMs).clamp(0.0, 1.0);
                                      final endFrac = (sample.endTime > Duration.zero)
                                          ? (sample.endTime.inMilliseconds / durationMs).clamp(0.0, 1.0)
                                          : 1.0;
                                      final frac = (dx / width).clamp(startFrac, endFrac);
                                      // Absolute time along full file
                                      final seekAbs = Duration(milliseconds: (frac * durationMs).round());
                                      // For trimmed samples, the player expects clip-relative seek (0 at trim start)
                                      final seekTarget = sample.isTrimmed
                                          ? seekAbs - sample.startTime
                                          : seekAbs;
                                      setState(() {
                                        _playheadLockedToStart = false;
                                        _playheadPosition = frac;
                                        _userHasSought = true;
                                      });
                                      audioProvider.seek(seekTarget);
                                    },
                                    onHorizontalDragStart: (details) async {
                                      if (sample == null) return;
                                      // If currently playing, pause so we can scrub precisely
                                      if (audioProvider.isPlaying) {
                                        await audioProvider.pause();
                                      }
                                      final renderBox = context.findRenderObject() as RenderBox;
                                      final local = details.localPosition;
                                      final width = renderBox.size.width;
                                      final dx = local.dx.clamp(0.0, width);
                                      final startFrac = (sample.startTime.inMilliseconds / durationMs).clamp(0.0, 1.0);
                                      final endFrac = (sample.endTime > Duration.zero)
                                          ? (sample.endTime.inMilliseconds / durationMs).clamp(0.0, 1.0)
                                          : 1.0;
                                      final frac = (dx / width).clamp(startFrac, endFrac);
                                      final seekAbs = Duration(milliseconds: (frac * durationMs).round());
                                      final seekTarget = sample.isTrimmed
                                          ? seekAbs - sample.startTime
                                          : seekAbs;
                                      setState(() {
                                        _playheadLockedToStart = false;
                                        _playheadPosition = frac;
                                        _timeTooltipPosition = Offset(dx, 0);
                                        _timeTooltipText = formatDuration(seekAbs);
                                        _userHasSought = true;
                                      });
                                      audioProvider.seek(seekTarget);
                                    },
                                    onHorizontalDragUpdate: (details) {
                                      if (sample == null) return;
                                      final renderBox = context.findRenderObject() as RenderBox;
                                      final width = renderBox.size.width;
                                      final dxRaw = details.localPosition.dx;
                                      final dx = dxRaw.clamp(0.0, width);
                                      final startFrac = (sample.startTime.inMilliseconds / durationMs).clamp(0.0, 1.0);
                                      final endFrac = (sample.endTime > Duration.zero)
                                          ? (sample.endTime.inMilliseconds / durationMs).clamp(0.0, 1.0)
                                          : 1.0;
                                      final frac = (dx / width).clamp(startFrac, endFrac);
                                      final seekAbs = Duration(milliseconds: (frac * durationMs).round());
                                      final seekTarget = sample.isTrimmed
                                          ? seekAbs - sample.startTime
                                          : seekAbs;
                                      setState(() {
                                        _playheadPosition = frac;
                                        _timeTooltipPosition = Offset(dx, 0);
                                        _timeTooltipText = formatDuration(seekAbs);
                                        _userHasSought = true;
                                      });
                                      audioProvider.seek(seekTarget);
                                    },
                                    onHorizontalDragEnd: (_) {
                                      if (audioProvider.isPlaying) return;
                                      setState(() {
                                        _timeTooltipPosition = null;
                                        _timeTooltipText = null;
                                      });
                                    },
                                    child: Stack(
                                      children: [
                SizedBox(
                                          width: double.infinity,
                                          height: double.infinity,
                                          child: CustomPaint(
                                            painter: _TimeGridPainter(
                                              duration: duration,
                  // Hide built-in playhead; we draw a single overlay across both windows
                  position: const Duration(milliseconds: -1),
                                              trimStart: sample?.startTime,
                                              trimEnd: (sample != null && sample.endTime > Duration.zero) ? sample.endTime : null,
                                              labelStyle: TextStyle(
                                                color: hasSelectedSample ? Colors.grey : Colors.grey.withValues(alpha: 0.3),
                                                fontSize: 10,
                                              ),
                                              formatDuration: formatDuration,
                                              numLabels: 6,
                                              gridColor: hasSelectedSample ? Colors.grey.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.1),
                                            ),
                                          ),
                                        ),
                                        if (_timeTooltipPosition != null && _timeTooltipText != null)
                                          Positioned(
                                            left: _timeTooltipPosition!.dx,
                                            top: 0,
                                            child: Material(
                                              color: Colors.transparent,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(alpha: 0.8),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  _timeTooltipText!,
                                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 1),
            Expanded(
                        child: Container(
              key: _waveformKey,
                          decoration: BoxDecoration(
                            color: hasSelectedSample
                                ? Colors.black.withValues(alpha: 0.3)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Stack(
                            children: [
                              if (hasSelectedSample && _selectedSample!.waveformData != null && _selectedSample!.waveformData!.isNotEmpty)
                                RepaintBoundary(
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 0),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          return _WaveformFillOptimized(
                                            magnitude: _selectedSample!.waveformData!,
                                            width: constraints.maxWidth,
                                            height: constraints.maxHeight,
                                            gainDb: _selectedSample!.gainDb,
                                            compressionStrength: 2.2,
                                            edgeMarginPx: 2.0,
                                            visualScale: 0.9,
                                            fillColor: Colors.grey.shade200,
                                            strokeColor: Colors.white,
                                            drawStroke: true,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              if (hasSelectedSample)
                                _buildTrimHandles(context, _selectedSample!, hasSelectedSample),
                              // Waveform loading overlay
                              if (hasSelectedSample && (_selectedSample!.isWaveformLoading || _selectedSample!.waveformData == null || _selectedSample!.waveformData!.isEmpty))
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Analyzing waveform…',
                                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              if (_dragTooltipPosition != null && _dragTooltipText != null)
                                Positioned(
                                  left: _dragTooltipPosition!.dx,
                                  top: _dragTooltipPosition!.dy,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.8),
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
                                        color: Colors.grey.withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Select a sample',
                                        style: TextStyle(
                                          color: Colors.grey.withValues(alpha: 0.7),
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
                      // Controls moved to right panel for phone/tablet
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Overlay a single playhead across both time bar and waveform
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: Consumer<AudioProvider>(
              builder: (context, audioProvider, _) {
                return CustomPaint(
                  painter: _UnifiedPlayheadPainter(state: this, repaint: audioProvider),
                );
              },
            ),
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
                  ? (Colors.grey[700] ?? Colors.grey).withValues(alpha: 0.25)
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

  // (removed) _showSampleContextMenu was unused

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
                  sampleProvider.updateSampleColor(sample.id, colors[index].toARGB32());
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

  // Get duration quickly, then add a shell sample so it appears immediately
  final actualDuration = await audioProvider.getAudioDuration(filePath);
    
    if (sampleId != null) {
      // Update existing blank sample
      await sampleProvider.updateBlankSample(
        sampleId,
        filePath,
        fileName,
        actualDuration,
        waveformData: null,
      );
      // Auto-select only if nothing is currently playing
      final updatedSample = sampleProvider.getSampleById(sampleId);
      final audioProviderNow = Provider.of<AudioProvider>(context, listen: false);
      if (updatedSample != null && !audioProviderNow.isPlaying) {
        _selectSample(updatedSample);
      }
      // Generate waveform in background and update
      final waveformData = await audioProvider.generateWaveformData(filePath);
      if (waveformData != null) {
        await sampleProvider.setSampleWaveform(sampleId, waveformData);
      }
    } else {
      // Create shell then generate waveform asynchronously
      final shell = await sampleProvider.addSampleShell(
        name: fileName,
        category: 'General',
        filePath: filePath,
        duration: actualDuration,
        notes: null,
      );
      // Auto-select only if nothing is currently playing
      final audioProviderNow = Provider.of<AudioProvider>(context, listen: false);
      if (!audioProviderNow.isPlaying) {
        final latest = sampleProvider.getSampleById(shell.id) ?? shell;
        _selectSample(latest);
      }
      final waveformData = await audioProvider.generateWaveformData(filePath);
      if (waveformData != null) {
        await sampleProvider.setSampleWaveform(shell.id, waveformData);
      }
    }
  }

  void _handleDragEnd(DraggableDetails details, AudioSample sample, SampleProvider sampleProvider) {
    // Get the screen size
    final screenSize = MediaQuery.of(context).size;
    const edgeThreshold = 20.0; // Distance from edge to trigger delete
    
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

  // (removed) _getSampleButtonColor was unused

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
    
  // "panel" render box not used currently; kept for potential overlay alignment in future
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
  // Tappable area is 32px centered on the trim point (±16px)
  const handleTapWidth = 32.0;
        const minFrac = _minTrimFraction;
        final minDistPx = minFrac * width;
        // Remove duplicate duration definition - use the one from outer scope
        // Remove duplicate startFrac and endFrac definitions - use the ones from outer scope
        final startPx = startFrac * width;
        final endPx = endFrac * width;
        return Stack(
          children: [
            // Chamfered trim region (matches PNG): thin yellow border, subtle fill
    Positioned.fill(
              child: CustomPaint(
                painter: _TrimRegionPainter(
                  startFrac: startFrac,
                  endFrac: endFrac,
  fillColor: Colors.yellow.withValues(alpha: 0.05),
                  borderColor: Colors.yellow,
                  chamfer: 10.0,
                  borderWidth: 1.0,
                ),
              ),
            ),
            // Playhead line removed; unified overlay painter draws a single line across time bar and waveform
            // Start handle
            Positioned(
              left: (startPx - (handleTapWidth / 2)).clamp(0.0, width - handleTapWidth),
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
                    final handleLeft = (startPx - (handleTapWidth / 2)).clamp(0.0, width - handleTapWidth);
                    final handleRight = (handleLeft + handleTapWidth).clamp(0.0, width);
                    if (playheadX >= handleLeft && playheadX <= handleRight) {
                      audioProvider.stop();
                    }
                  }
                },
                onHorizontalDragStart: (details) {
                  setState(() {
                    _isDraggingStart = true;
            _dragAccumDxStart = 0.0;
            _dragStartBasePxStart = startPx; // capture base position at drag start
                      _draggingTrimStartTime = Duration(milliseconds: (startFrac * durationMs).round());
                  });
                },
                onHorizontalDragUpdate: (details) {
                  _dragAccumDxStart += details.delta.dx;
                  final localX = (_dragStartBasePxStart + _dragAccumDxStart).clamp(0.0, endPx - minDistPx);
                  final newFrac = (localX / width).clamp(0.0, endFrac - minFrac);
                  setState(() {
                    _draggingTrimStart = newFrac;
                      _draggingTrimStartTime = Duration(milliseconds: (newFrac * durationMs).round());
                    _dragTooltipPosition = Offset(localX, 0);
                    _dragTooltipText = formatDuration(Duration(milliseconds: (newFrac * durationMs).round()));
                    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
                    final isPlayingThis = audioProvider.isPlaying && audioProvider.playingSample?.id == sample.id;
                    if (!isPlayingThis && _playheadLockedToStart) {
                      _playheadPosition = newFrac;
                    }
                  });
                  // If playing, stop immediately if playhead leaves new trim region
                  final audioProviderCheck = Provider.of<AudioProvider>(context, listen: false);
                  final playingThisNow = audioProviderCheck.isPlaying && audioProviderCheck.playingSample?.id == sample.id;
                  if (playingThisNow) {
                    final playbackPositionMs = audioProviderCheck.position.inMilliseconds;
                    final startAbsMs = (newFrac * durationMs).round();
                    final endAbsMs = sample.endTime.inMilliseconds > 0 ? sample.endTime.inMilliseconds : durationMs;
                    final currentAbsMs = playbackPositionMs + sample.startTime.inMilliseconds;
                    if (currentAbsMs <= startAbsMs || currentAbsMs >= endAbsMs) {
                      audioProviderCheck.stop();
                    }
                  }
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
                      // Visual is provided by the chamfered region painter; no extra line needed.
                      if (_isDraggingStart && _draggingTrimStartTime != null)
                        Positioned(
                          top: -32,
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
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
              left: (endPx - (handleTapWidth / 2)).clamp(0.0, width - handleTapWidth),
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
                    final handleLeft = (endPx - (handleTapWidth / 2)).clamp(0.0, width - handleTapWidth);
                    final handleRight = (handleLeft + handleTapWidth).clamp(0.0, width);
                    if (playheadX >= handleLeft && playheadX <= handleRight) {
                      audioProvider.stop();
                    }
                  }
                },
                onHorizontalDragStart: (details) {
                  setState(() {
                    _isDraggingEnd = true;
            _dragAccumDxEnd = 0.0;
            _dragStartBasePxEnd = endPx; // capture base position at drag start
                      _draggingTrimEndTime = Duration(milliseconds: (endFrac * durationMs).round());
                  });
                },
                onHorizontalDragUpdate: (details) {
          _dragAccumDxEnd += details.delta.dx;
          final localX = (_dragStartBasePxEnd + _dragAccumDxEnd).clamp(startPx + minDistPx, width);
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
                  // If playing, stop immediately if playhead leaves new trim region
                  final audioProviderCheck = Provider.of<AudioProvider>(context, listen: false);
                  final playingThisNow = audioProviderCheck.isPlaying && audioProviderCheck.playingSample?.id == sample.id;
                  if (playingThisNow) {
                    final playbackPositionMs = audioProviderCheck.position.inMilliseconds;
                    final startAbsMs = sample.startTime.inMilliseconds;
                    final endAbsMs = (newFrac * durationMs).round();
                    final currentAbsMs = playbackPositionMs + sample.startTime.inMilliseconds;
                    if (currentAbsMs <= startAbsMs || currentAbsMs >= endAbsMs) {
                      audioProviderCheck.stop();
                    }
                  }
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
                      // Visual is provided by the chamfered region painter; no extra line needed.
                      if (_isDraggingEnd && _draggingTrimEndTime != null)
                        Positioned(
                          top: -32,
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
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
  // Do not show a playhead by default for inactive samples; only after user taps/drags
  _playheadPosition = null;
  _playheadLockedToStart = true;
  _timeTooltipPosition = null;
  _timeTooltipText = null;
  _userHasSought = false;
    });
    // Update AudioProvider current sample to reset baseline trim tracking
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
    audioProvider.setCurrentSample(sample);
  }

  // (removed) _calculatePlayheadPosition was unused
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
                initialValue: _selectedCategory,
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

  if (!mounted) return;
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
  // Panel color resolved via Theme below as needed
    return Selector<SampleProvider, AudioSample?>(
      selector: (context, sampleProvider) => sampleProvider.getSampleById(widget.sample.id),
      builder: (context, selectedSample, _) {
        Color fillColor;
        if (selectedSample != null && selectedSample.customColor != null) {
          fillColor = Color(selectedSample.customColor!);
        } else {
          fillColor = Theme.of(context).colorScheme.outline.withValues(alpha: 0.3);
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
    required this.numLabels,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;
    final double durationMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final Paint gridPaint = Paint()
  ..color = gridColor.withValues(alpha: 0.5)
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

class _UnifiedPlayheadPainter extends CustomPainter {
  final _MainSamplerScreenState state;
  _UnifiedPlayheadPainter({required this.state, Listenable? repaint}) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final ctx = state.context;
    if (state._selectedSample == null) return;
    final audioProvider = Provider.of<AudioProvider>(ctx, listen: false);
  // Prefer provider's current sample for live-accurate trims during playback
  final effectiveSample = (audioProvider.currentSample?.id == state._selectedSample!.id)
    ? audioProvider.currentSample!
    : state._selectedSample!;
  final durationMs = (effectiveSample.duration.inMilliseconds > 0)
    ? effectiveSample.duration.inMilliseconds
    : 1;
  // Consider "playing this" if the provider reports playing and the currentSample matches.
  final isPlayingThis = audioProvider.isPlaying && audioProvider.currentSample?.id == effectiveSample.id;

    // Determine fraction 0..1 along full duration
    double? frac;
    if (isPlayingThis) {
      // Apply latency compensation for visual playhead while playing
      final adjusted = audioProvider.position - audioProvider.latencyCompensation;
      final safeAdjusted = adjusted.isNegative ? Duration.zero : adjusted;
      final absMs = (safeAdjusted + effectiveSample.startTime).inMilliseconds.toDouble();
      frac = (absMs / durationMs).clamp(0.0, 1.0);
    } else if (audioProvider.currentSample?.id == effectiveSample.id) {
      // Paused on this sample: keep playhead visible at the paused position (no latency offset)
      final pausedAbsMs = (audioProvider.position + effectiveSample.startTime).inMilliseconds.toDouble();
      frac = (pausedAbsMs / durationMs).clamp(0.0, 1.0);
    } else if (state._userHasSought && state._playheadPosition != null) {
      // Not the current sample; if the user has sought locally, show that position
      frac = state._playheadPosition!.clamp(0.0, 1.0);
    }
    if (frac == null) return; // hide when not playing and not sought

    // Compute rectangles for time bar and waveform within the panel stack
    final panelBox = state._panelStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (panelBox == null || !panelBox.hasSize) return;
    final timeRect = state._rectFor(state._timeBarKey, state._panelStackKey);
    final waveRect = state._rectFor(state._waveformKey, state._panelStackKey);

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2;

    void drawLineAcross(Rect r) {
      final x = r.left + r.width * frac!;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), paint);
    }

    if (timeRect != null) drawLineAcross(timeRect);
    if (waveRect != null) drawLineAcross(waveRect);
  }

  @override
  bool shouldRepaint(covariant _UnifiedPlayheadPainter oldDelegate) => true;
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
  ..color = (sliderTheme.thumbColor ?? Colors.blue).withValues(alpha: 0.2)
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

// Simple mirrored waveform renderer that fills symmetrically around center
// Optimized waveform: downsample to ~1 point per pixel, LUT-compressed, fill-only mirrored
class _WaveformFillOptimized extends StatelessWidget {
  final List<double> magnitude; // [0,1] per source sample
  final double width;
  final double height;
  final double gainDb;
  final double compressionStrength; // e.g., 2.2
  final double edgeMarginPx; // top/bottom margin
  final double visualScale; // pre-compression visual scaler (0..1), e.g., 0.9
  final Color fillColor;
  final Color strokeColor; // optional center line only when drawStroke=true
  final bool drawStroke;

  const _WaveformFillOptimized({
    required this.magnitude,
    required this.width,
    required this.height,
    required this.gainDb,
    required this.compressionStrength,
    required this.edgeMarginPx,
    this.visualScale = 0.9,
    required this.fillColor,
    required this.strokeColor,
    this.drawStroke = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _WaveformFillOptimizedPainter(
        magnitude: magnitude,
        gainDb: gainDb,
        compressionStrength: compressionStrength,
        edgeMarginPx: edgeMarginPx,
  visualScale: visualScale,
        fillColor: fillColor,
        strokeColor: strokeColor,
        drawStroke: drawStroke,
      ),
    );
  }
}

class _WaveformFillOptimizedPainter extends CustomPainter {
  final List<double> magnitude; // [0,1]
  final double gainDb;
  final double compressionStrength;
  final double edgeMarginPx;
  final double visualScale;
  final Color fillColor;
  final Color strokeColor;
  final bool drawStroke;

  // Small LUT to avoid recomputing tanh per point when dragging gain
  static const int _lutSize = 256;
  static final Map<double, List<double>> _lutCache = {}; // key: compressionStrength

  _WaveformFillOptimizedPainter({
    required this.magnitude,
    required this.gainDb,
    required this.compressionStrength,
    required this.edgeMarginPx,
  required this.visualScale,
    required this.fillColor,
    required this.strokeColor,
    required this.drawStroke,
  });

  List<double> _getLut(double strength) {
    // Round strength to 2 decimals to bound cache keys
    final double key = double.parse(strength.toStringAsFixed(2));
    final existing = _lutCache[key];
    if (existing != null) return existing;
    // Build LUT for x in [0, 1.5] to allow some headroom before clamping
    final List<double> lut = List.filled(_lutSize, 0.0);
    double _tanh(double z) {
      final double e2z = exp(2.0 * z);
      return (e2z - 1.0) / (e2z + 1.0);
    }
    final double denom = _tanh(key);
    for (int i = 0; i < _lutSize; i++) {
      final double x = (i / (_lutSize - 1)) * 1.5; // 0..1.5
      final double y = _tanh(key * x) / (denom == 0 ? 1.0 : denom);
      lut[i] = y.clamp(0.0, 1.0);
    }
    _lutCache[key] = lut;
    return lut;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (magnitude.isEmpty || size.width <= 0 || size.height <= 0) return;

    // Downsample to 1 value per pixel using max within each bucket for better peak visibility
    final int targetPoints = size.width.ceil();
    final int srcLen = magnitude.length;
    final List<double> env = List<double>.filled(targetPoints, 0.0, growable: false);
    for (int x = 0; x < targetPoints; x++) {
      final int start = ((x / targetPoints) * srcLen).floor();
      final int end = (((x + 1) / targetPoints) * srcLen).ceil().clamp(start + 1, srcLen);
      double maxV = 0.0;
      for (int i = start; i < end; i++) {
        final v = magnitude[i].abs();
        if (v > maxV) maxV = v;
      }
      env[x] = maxV;
    }

    final double amp = pow(10.0, gainDb / 20.0).toDouble().clamp(0.0, 4.0);
    final lut = _getLut(compressionStrength);
    double compress(double x) {
      if (x <= 0) return 0.0;
      // Map x to LUT index 0.._lutSize-1 based on x in 0..1.5 range
      final double xi = (x * 1.0).clamp(0.0, 1.5) / 1.5;
      final double f = xi * (lut.length - 1);
      final int i0 = f.floor();
      final int i1 = (i0 + 1).clamp(0, lut.length - 1);
      final double t = f - i0;
      return lut[i0] * (1 - t) + lut[i1] * t;
    }

    final double margin = edgeMarginPx.clamp(0.0, size.height / 3.0);
    final double centerY = size.height / 2.0;
    final double half = centerY - 1.0 - margin;
    final Path fill = Path();
    final List<Offset> upper = List.filled(env.length, Offset.zero);
    for (int x = 0; x < env.length; x++) {
      final double frac = env.length > 1 ? x / (env.length - 1) : 0.0;
  final double vx = compress(env[x] * amp * visualScale).clamp(0.0, 1.0);
      final double yOff = vx * half;
      final double yUp = centerY - yOff;
      final double px = frac * size.width;
      final Offset p = Offset(px, yUp);
      upper[x] = p;
    }
    if (upper.isEmpty) return;
    fill.addPolygon(upper, false);
    // Lower path reversed
    for (int x = upper.length - 1; x >= 0; x--) {
      final Offset up = upper[x];
      final double dy = centerY - up.dy;
      fill.lineTo(up.dx, centerY + dy);
    }
    fill.close();

    final Paint fillPaint = Paint()
      ..isAntiAlias = true
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(fill, fillPaint);

    if (drawStroke) {
      // Outline the waveform to keep shape visible in quiet areas
      final Paint outline = Paint()
        ..isAntiAlias = true
  ..color = strokeColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      canvas.drawPath(fill, outline);

      // Draw a faint center line across
      final Paint centerPaint = Paint()
        ..isAntiAlias = true
  ..color = strokeColor.withValues(alpha: 0.18)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), centerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformFillOptimizedPainter old) {
    // Repaint when gain or size-affecting params change, or when source array identity changes
    return identical(magnitude, old.magnitude) == false ||
        gainDb != old.gainDb ||
        compressionStrength != old.compressionStrength ||
        edgeMarginPx != old.edgeMarginPx ||
  visualScale != old.visualScale ||
        fillColor != old.fillColor ||
        strokeColor != old.strokeColor ||
        drawStroke != old.drawStroke;
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