import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps [child] with a tactile press response — a subtle scale-down while
/// pressed plus light haptic feedback on tap.
///
/// Use this for custom card / chip / button-like surfaces built from
/// `Container`s, which otherwise give no press feedback. When [onTap] (and
/// [onLongPress]) are null the wrapper is inert and dims the child to signal a
/// disabled state.
class AppTappable extends StatefulWidget {
  const AppTappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.haptic = true,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale applied while pressed. 1.0 disables the scale effect.
  final double pressedScale;

  /// Whether to fire [HapticFeedback.lightImpact] on tap.
  final bool haptic;

  /// When false the wrapper is non-interactive and the child is dimmed.
  final bool enabled;

  @override
  State<AppTappable> createState() => _AppTappableState();
}

class _AppTappableState extends State<AppTappable> {
  bool _pressed = false;

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _setPressed(bool value) {
    if (!_interactive || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: _interactive
          ? () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap?.call();
            }
          : null,
      onLongPress: _interactive ? widget.onLongPress : null,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _interactive ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}
