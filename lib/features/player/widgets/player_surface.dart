import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';

/// Wraps the now-playing content with a swipe-down-to-dismiss gesture. The
/// child translates with the drag, fades out as it moves further, and either
/// pops the route on release past the threshold or settles back to zero.
class PlayerDismissibleSurface extends StatefulWidget {
  const PlayerDismissibleSurface({required this.child, super.key});
  final Widget child;

  @override
  State<PlayerDismissibleSurface> createState() =>
      _PlayerDismissibleSurfaceState();
}

class _PlayerDismissibleSurfaceState extends State<PlayerDismissibleSurface>
    with SingleTickerProviderStateMixin {
  double _dy = 0;
  late final AnimationController _settle;
  Animation<double>? _settleAnim;

  @override
  void initState() {
    super.initState();
    // Eager init: a lazy field initializer would run on first read; if that
    // first read is dispose(), vsync looks up TickerMode on a deactivated element.
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(_onSettleTick);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onSettleTick() {
    if (_settleAnim != null) {
      setState(() => _dy = _settleAnim!.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final dismissThreshold = screenH * 0.18;
    final progress = (_dy / (screenH * 0.6)).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {
        _settle.stop();
      },
      onVerticalDragUpdate: (d) {
        final delta = d.primaryDelta ?? 0;
        if (delta == 0) return;
        setState(() {
          _dy = (_dy + delta).clamp(0.0, screenH);
        });
      },
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_dy > dismissThreshold || v > 700) {
          HapticFeedback.lightImpact();
          context.pop();
        } else {
          _settleAnim = Tween<double>(begin: _dy, end: 0).animate(
            CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic),
          );
          _settle.forward(from: 0);
        }
      },
      child: Opacity(
        opacity: 1 - progress * 0.6,
        child: Transform.translate(offset: Offset(0, _dy), child: widget.child),
      ),
    );
  }
}

/// Small visual drag indicator at the top of the now-playing surface.
class PlayerDragHandle extends StatelessWidget {
  const PlayerDragHandle({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textTertiary.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Solid surface-colored backdrop filling the now-playing screen.
class PlayerBackdrop extends StatelessWidget {
  const PlayerBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: DecoratedBox(decoration: BoxDecoration(color: AppColors.surface)),
    );
  }
}
