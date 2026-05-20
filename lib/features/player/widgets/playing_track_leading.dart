import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/core/widgets/local_or_network_image.dart';
import 'package:altsound/features/player/player_providers.dart';

/// Leading column for track rows: index number, highlighted when playing.
class PlayingTrackLeading extends ConsumerWidget {
  const PlayingTrackLeading({
    required this.jellyfinTrackId,
    required this.indexLabel,
    super.key,
  });

  final String jellyfinTrackId;
  final String indexLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == jellyfinTrackId;

    return SizedBox(
      width: 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            indexLabel,
            style: TextStyle(
              color: isCurrent ? AppColors.primary : AppColors.textTertiary,
              fontSize: 13,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 56x56 art for search results with a primary border when this track is playing.
class SearchTrackArtwork extends ConsumerWidget {
  const SearchTrackArtwork({
    super.key,
    required this.imageUrl,
    required this.jellyfinTrackId,
    required this.isArtistShape,
  });

  final String? imageUrl;
  final String jellyfinTrackId;
  final bool isArtistShape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == jellyfinTrackId;

    final br = BorderRadius.circular(isArtistShape ? 28 : 8);
    Widget fallback() => Container(
      color: AppColors.surfaceElevated,
      child: const Icon(PiconsRegular.musicNote, color: AppColors.textTertiary),
    );
    Widget artwork() {
      final url = imageUrl;
      if (url == null || url.isEmpty) return fallback();
      return LocalOrNetworkImage(
        source: url,
        fit: BoxFit.cover,
        placeholderBuilder: (_) => Container(color: AppColors.surfaceElevated),
        errorBuilder: (_) => fallback(),
      );
    }

    return SizedBox(
      width: 56,
      height: 56,
      child: ClipRRect(
        borderRadius: br,
        child: isCurrent
            ? DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 2),
                  borderRadius: br,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isArtistShape ? 26 : 6),
                    child: artwork(),
                  ),
                ),
              )
            : artwork(),
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
