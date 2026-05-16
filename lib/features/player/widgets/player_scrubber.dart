import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/features/player/player_providers.dart';

/// Scrub bar + elapsed / remaining timestamps. Drives playback position via
/// [playerControllerProvider.seek]; renders using effective (local *or*
/// remote) position/duration providers.
class PlayerScrubber extends ConsumerWidget {
  const PlayerScrubber({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(effectivePositionProvider);
    final duration = ref.watch(effectiveDurationProvider);

    final clamped = position > duration ? duration : position;
    final maxMs = duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final value = clamped.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: AppColors.primary,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withValues(alpha: 0.16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: maxMs,
            onChanged: (x) => ref
                .read(playerControllerProvider)
                .seek(Duration(milliseconds: x.toInt())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(clamped),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                formatDuration(duration),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
