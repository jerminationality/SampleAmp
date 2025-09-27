import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:live_audio_sampler/models/audio_sample.dart';
import 'package:live_audio_sampler/providers/audio_provider.dart';
import 'package:live_audio_sampler/providers/sample_provider.dart';
import 'package:live_audio_sampler/screens/main_sampler_screen.dart';

class SampleButton extends StatefulWidget {
  final AudioSample sample;
  final String? gridPosition;
  final String? selectedSampleId;
  final VoidCallback? onAddAudio;
  final VoidCallback? onSelect;

  const SampleButton({
    super.key,
    required this.sample,
    this.gridPosition,
    this.selectedSampleId,
    this.onAddAudio,
    this.onSelect,
  });

  @override
  State<SampleButton> createState() => _SampleButtonState();
}

class _SampleButtonState extends State<SampleButton>
    with SingleTickerProviderStateMixin {
  static OverlayEntry? _activeMenuEntry;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  final bool _isPressed = false;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  // Prefer white text in most cases, with special handling for greys/desaturated colors
  // Adjustable thresholds for aesthetics vs readability
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
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioProvider>(
      builder: (context, audioProvider, _) {
        return CompositedTransformTarget(
          link: _layerLink,
          child: GestureDetector(
            onTap: _playSample,
            onLongPress: _onLongPress,
            child: AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Stack(
                    children: [
                      Container(
                    decoration: BoxDecoration(
                      color: _getButtonColor(),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: widget.selectedSampleId == widget.sample.id ? Colors.yellow : Colors.transparent,
                        width: widget.selectedSampleId == widget.sample.id ? 1 : 0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getSampleIcon(),
                          size: 32,
                          color: _getIconColor(),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _getDisplayText(),
                            style: TextStyle(
                              color: _getTextColor(),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!widget.sample.isBlank) ...[
                        ],
                        if (widget.sample.isFavorite)
                          const Icon(
                            Icons.favorite,
                            size: 16,
                            color: Colors.red,
                          ),
                      ],
                    ),
                      ),
                      // Loading spinner removed per request
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Color _getButtonColor() {
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
    final isPlayingSample = audioProvider.playingSample?.id == widget.sample.id;
    final isPlaying = audioProvider.isPlaying && isPlayingSample;

    if (isPlaying) {
      return Theme.of(context).colorScheme.primary;
    } else if (_isPressed) {
  return Theme.of(context).colorScheme.primary.withValues(alpha: 0.7);
    } else if (!widget.sample.isBlank) {
      // For active samples, use custom color as background if available
      if (widget.sample.customColor != null) {
        return Color(widget.sample.customColor!);
      }
      // Active sample buttons (with audio) get a solid background color
  return Theme.of(context).colorScheme.outline.withValues(alpha: 0.3);
    } else {
      // Blank samples always use surface color for background
      return Theme.of(context).colorScheme.surface;
    }
  }

  // _getBorderColor is no longer needed

  Color _getIconColor() {
    // Force white on default fill for active samples without custom color
    if (!widget.sample.isBlank && widget.sample.customColor == null) {
      return Colors.white;
    }
    final bg = _getButtonColor();
    // Derive foreground for icon based on actual background for best readability
    return _bestForegroundOn(bg);
  }

  Color _getTextColor() {
    // Force white on default fill for active samples without custom color
    if (!widget.sample.isBlank && widget.sample.customColor == null) {
      return Colors.white;
    }
    final bg = _getButtonColor();
    return _bestForegroundOn(bg);
  }

  IconData _getSampleIcon() {
    if (widget.sample.isBlank) {
      return Icons.add; // + icon for blank samples
    } else if (widget.sample.volume != 1.0) {
      return Icons.volume_up;
    } else if (widget.sample.pitch != 1.0) {
      return Icons.tune;
    } else {
      return Icons.graphic_eq; // Diamond/waveform icon for normal samples
    }
  }

  String _getDisplayText() {
    if (widget.sample.isBlank) {
      return 'Add Audio';
    } else if (widget.sample.name.isEmpty || widget.sample.name.trim().isEmpty) {
      // Show grid position if no name is provided
      return widget.gridPosition ?? 'Unknown';
    } else {
      return widget.sample.name;
    }
  }

  // Removed unused _formatDuration helper (no longer displayed on buttons)

  void _playSample() {
    if (widget.sample.isBlank) {
      _showAddAudioDialog();
    } else {
      final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
      final latestSample = sampleProvider.getSampleById(widget.sample.id) ?? widget.sample;
      final audioProvider = Provider.of<AudioProvider>(context, listen: false);
      // Always update current selection
      audioProvider.setCurrentSample(latestSample);
  // Play regardless of waveform loading; waveform extraction runs in background
  audioProvider.playSample(latestSample);
      // Also select the sample when tapped
      if (widget.onSelect != null) {
        widget.onSelect!();
      }
    }
  }

  void _onLongPress() {
    _showContextMenu();
  }

  void _showAddAudioDialog() {
    if (widget.onAddAudio != null) {
      widget.onAddAudio!();
    } else {
      // Show the Add Audio dialog
      showDialog(
        context: context,
        builder: (context) => const AddSampleDialog(),
      );
    }
  }

  void _showContextMenu() {
    // Close any previously open menu
    _activeMenuEntry?.remove();
    _activeMenuEntry = null;

    final overlay = Overlay.of(context);
    OverlayEntry? overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Dismiss when tapping outside
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                overlayEntry?.remove();
                if (_activeMenuEntry == overlayEntry) _activeMenuEntry = null;
              },
              behavior: HitTestBehavior.translucent,
            ),
          ),
          // Menu positioned relative to the button
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 60), // Position below the button
            child: Material(
              elevation: 12.0,
              borderRadius: BorderRadius.circular(12.0),
              child: Container(
                width: 180, // Slightly wider for better appearance
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12.0,
                      offset: const Offset(0, 4),
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMenuItem('Select', 'select', overlayEntry!),
                    const Divider(height: 1, color: Colors.grey, indent: 8, endIndent: 8),
                    _buildMenuItem('Change Color', 'color', overlayEntry),
                    const Divider(height: 1, color: Colors.grey, indent: 8, endIndent: 8),
                    _buildMenuItem('Duplicate', 'duplicate', overlayEntry),
                    const Divider(height: 1, color: Colors.grey, indent: 8, endIndent: 8),
                    _buildMenuItem('Delete', 'delete', overlayEntry),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(overlayEntry);
    _activeMenuEntry = overlayEntry;
  }

  Widget _buildMenuItem(String text, String value, OverlayEntry overlayEntry) {
    return InkWell(
      onTap: () {
        overlayEntry.remove();
        if (_activeMenuEntry == overlayEntry) _activeMenuEntry = null;
        _handleMenuSelection(value);
      },
      child: Container(
        width: 160, // Match parent width
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _handleMenuSelection(String value) {
    if (value == 'select') {
      _selectSample();
    } else if (value == 'color') {
      _showColorPicker();
    } else if (value == 'duplicate') {
      if (!widget.sample.isBlank) {
        _duplicateSample(context);
      } else {
        // Cannot duplicate a blank sample
      }
    } else if (value == 'delete') {
      _deleteSample(context);
    }
  }

  void _showColorPicker() {
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

    showDialog(
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
                  sampleProvider.updateSampleColor(widget.sample.id, colors[index].toARGB32());
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

  // Removed unused _getColorName

  void _selectSample() {
    // Only select the sample, do not play audio
    if (widget.onSelect != null) {
      widget.onSelect!();
    }
  }

  void _duplicateSample(BuildContext context) {
    final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
    sampleProvider.duplicateSample(widget.sample.id);
  }

  void _deleteSample(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sample'),
        content: Text('Are you sure you want to delete "${widget.sample.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final sampleProvider = Provider.of<SampleProvider>(context, listen: false);
              sampleProvider.deleteSample(widget.sample.id);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
} 