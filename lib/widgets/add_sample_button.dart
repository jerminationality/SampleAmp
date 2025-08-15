import 'package:flutter/material.dart';

class AddSampleButton extends StatefulWidget {
  final VoidCallback onTap;

  const AddSampleButton({
    super.key,
    required this.onTap,
  });

  @override
  State<AddSampleButton> createState() => _AddSampleButtonState();
}

class _AddSampleButtonState extends State<AddSampleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _opacityAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _isHovered = true;
        });
        _animationController.forward();
      },
      onExit: (_) {
        setState(() {
          _isHovered = false;
        });
        _animationController.reverse();
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _opacityAnimation.value,
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: _getButtonColor(),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getBorderColor(),
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Plus icon
                      Icon(
                        Icons.add_circle_outline,
                        size: 32,
                        color: _getIconColor(),
                      ),
                      const SizedBox(height: 8),
                      
                      // Text
                      Text(
                        'Add Sample',
                        style: TextStyle(
                          color: _getTextColor(),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 4),
                      
                      // Subtitle
                      Text(
                        'Tap to import',
                        style: TextStyle(
                          color: _getTextColor().withOpacity(0.6),
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _getButtonColor() {
    if (_isHovered) {
      return Theme.of(context).colorScheme.primary.withOpacity(0.1);
    } else {
      return Theme.of(context).colorScheme.surface.withOpacity(0.5);
    }
  }

  Color _getBorderColor() {
    if (_isHovered) {
      return Theme.of(context).colorScheme.primary.withOpacity(0.5);
    } else {
      return Theme.of(context).colorScheme.outline.withOpacity(0.2);
    }
  }

  Color _getIconColor() {
    if (_isHovered) {
      return Theme.of(context).colorScheme.primary;
    } else {
      return Theme.of(context).colorScheme.onSurface.withOpacity(0.5);
    }
  }

  Color _getTextColor() {
    if (_isHovered) {
      return Theme.of(context).colorScheme.primary;
    } else {
      return Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
    }
  }
} 