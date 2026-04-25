import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../player_providers.dart';

/// Leading column for track rows: index, or playing/paused + optional progress.
class PlayingTrackLeading extends ConsumerWidget {
  const PlayingTrackLeading({
    required this.jellyfinTrackId,
    required this.indexLabel,
    required this.trackDuration,
    super.key,
  });

  final String jellyfinTrackId;
  final String indexLabel;
  final Duration trackDuration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMediaItemProvider).value;
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == jellyfinTrackId;

    return SizedBox(
      width: 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isCurrent)
            Icon(
              playing ? Icons.equalizer : Icons.pause,
              color: AppColors.primary,
              size: 20,
            )
          else
            Text(
              indexLabel,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (isCurrent && trackDuration.inMilliseconds > 0) ...[
            const SizedBox(height: 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 3,
                value: (position.inMilliseconds / trackDuration.inMilliseconds)
                    .clamp(0.0, 1.0),
                backgroundColor: AppColors.divider,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 56x56 art for search results with a bottom progress bar when this track is playing.
class SearchTrackArtwork extends ConsumerWidget {
  const SearchTrackArtwork({
    super.key,
    required this.imageUrl,
    required this.jellyfinTrackId,
    required this.isArtistShape,
  });

  final String imageUrl;
  final String jellyfinTrackId;
  final bool isArtistShape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMediaItemProvider).value;
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == jellyfinTrackId;
    final duration = current?.duration ?? Duration.zero;
    final progress = isCurrent && duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final br = BorderRadius.circular(isArtistShape ? 28 : 8);
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: br,
              child: isCurrent
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary, width: 2),
                        borderRadius: br,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(isArtistShape ? 26 : 6),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: AppColors.surfaceElevated),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.surfaceElevated,
                              child: const Icon(
                                Icons.music_note,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: AppColors.surfaceElevated),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surfaceElevated,
                        child: const Icon(
                          Icons.music_note,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
            ),
          ),
          if (isCurrent)
            Positioned(
              right: 4,
              top: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  playing ? Icons.equalizer : Icons.pause,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
            ),
          if (isCurrent && duration.inMilliseconds > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                minHeight: 3,
                value: progress,
                backgroundColor: Colors.black.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Optional trailing duration: dim when not current, highlight when current.
class PlayingTrackDuration extends ConsumerWidget {
  const PlayingTrackDuration({
    required this.jellyfinTrackId,
    required this.trackDuration,
    super.key,
  });

  final String jellyfinTrackId;
  final Duration trackDuration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == jellyfinTrackId;
    return Text(
      formatDuration(trackDuration),
      style: TextStyle(
        color: isCurrent ? AppColors.primary : AppColors.textSecondary,
        fontSize: 12,
        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}
