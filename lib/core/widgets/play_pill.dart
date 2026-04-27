import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';

/// Circular accent-gradient play/pause button used at the top of album,
/// artist, and playlist screens. Pass [onTap] = null to render a disabled
/// (50% opacity) state.
class PlayPill extends StatelessWidget {
  const PlayPill({
    required this.onTap,
    required this.icon,
    required this.tooltip,
    super.key,
  });

  final VoidCallback? onTap;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Tooltip(
        message: tooltip,
        child: Container(
          decoration: BoxDecoration(
            gradient: AppGradients.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 6),
                spreadRadius: -3,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              splashColor: AppColors.primary.withValues(alpha: 0.2),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(icon, color: AppColors.onAccent, size: 30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
