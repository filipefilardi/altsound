import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_gradients.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/features/player/player_providers.dart';

/// Previous / Play-Pause / Next transport row on the now-playing screen.
class PlayerMainControls extends ConsumerWidget {
  const PlayerMainControls({
    required this.playing,
    required this.onLyrics,
    required this.onQueue,
    super.key,
  });
  final bool playing;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 32,
              icon: const Icon(
                PhosphorIconsFill.skipBack,
                color: AppColors.textPrimary,
              ),
              onPressed: controller.previous,
            ),
            const SizedBox(width: AppSpacing.lg),
            PlayerPlayPauseButton(playing: playing, onTap: controller.togglePlay),
            const SizedBox(width: AppSpacing.lg),
            IconButton(
              iconSize: 32,
              icon: const Icon(
                PhosphorIconsFill.skipForward,
                color: AppColors.textPrimary,
              ),
              onPressed: controller.next,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              iconSize: 22,
              icon: const Icon(
                PhosphorIconsRegular.microphoneStage,
                color: AppColors.textSecondary,
              ),
              onPressed: onLyrics,
              tooltip: 'Lyrics',
            ),
            IconButton(
              iconSize: 22,
              icon: const Icon(
                PhosphorIconsRegular.queue,
                color: AppColors.textSecondary,
              ),
              onPressed: onQueue,
              tooltip: 'Queue',
            ),
          ],
        ),
      ],
    );
  }
}

/// Large round gradient play/pause button used in [PlayerMainControls] and
/// exposed standalone for callers that want just the central control.
class PlayerPlayPauseButton extends StatelessWidget {
  const PlayerPlayPauseButton({
    required this.playing,
    required this.onTap,
    super.key,
  });
  final bool playing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: AppGradients.accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Icon(
              playing ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
              color: AppColors.onAccent,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }
}
