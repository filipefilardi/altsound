import 'package:flutter/material.dart';
import 'package:picons/picons.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/features/player/playback_handler.dart';

/// Inline error pill shown in the now-playing screen when playback fails.
/// Exposes [onSkip] to advance past the broken track and [onDismiss] to hide.
class PlayerErrorBanner extends StatelessWidget {
  const PlayerErrorBanner({
    required this.error,
    required this.onSkip,
    required this.onDismiss,
    super.key,
  });

  final PlayerError error;
  final VoidCallback onSkip;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            PiconsRegular.warningCircle,
            color: AppColors.error,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              error.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
            child: const Text('Skip'),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(PiconsRegular.x, size: 18),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
