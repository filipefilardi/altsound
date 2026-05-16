import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/features/player/player_providers.dart';

/// Scrub bar + elapsed / remaining timestamps. Drives playback position via
/// [playerControllerProvider.seek]; renders using effective (local *or*
/// remote) position/duration providers.
class PlayerScrubber extends ConsumerStatefulWidget {
  const PlayerScrubber({super.key});

  @override
  ConsumerState<PlayerScrubber> createState() => _PlayerScrubberState();
}

class _PlayerScrubberState extends ConsumerState<PlayerScrubber> {
  double? _dragValueMs;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(effectivePositionProvider);
    final duration = ref.watch(effectiveDurationProvider);
    final controller = ref.read(playerControllerProvider);

    final clamped = position > duration ? duration : position;
    final maxMs = duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final actualValue = clamped.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final dragValue = _dragValueMs?.clamp(0.0, maxMs);
    final value = (dragValue ?? actualValue).toDouble();
    final displayedPosition = Duration(milliseconds: value.toInt());

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
            onChangeStart: (x) => setState(() => _dragValueMs = x),
            onChanged: (x) => setState(() => _dragValueMs = x),
            onChangeEnd: (x) {
              controller.seek(Duration(milliseconds: x.toInt()));
              setState(() => _dragValueMs = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(displayedPosition),
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
