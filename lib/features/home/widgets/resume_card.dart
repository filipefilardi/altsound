import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/artwork_placeholder.dart';
import 'package:altsound/core/widgets/local_or_network_image.dart';
import 'package:altsound/data/last_played/last_played_controller.dart';
import 'package:altsound/data/last_played/last_played_record.dart';

/// "Pick up where you left off" card on the home screen, sourced from the
/// last-played record. Hidden when there is no record. Tapping opens the
/// album page; the bottom progress bar reflects last-known playback position.
class ResumeCard extends ConsumerWidget {
  const ResumeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(lastPlayedProvider);
    if (record == null) return const SizedBox.shrink();

    final albumId = record.albumId;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: albumId == null ? null : () => context.push('/album/$albumId'),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          color: AppColors.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: LocalOrNetworkImage(
                  source: record.imageUrl,
                  errorBuilder: (_) => const SizedBox.shrink(),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColors.background.withValues(alpha: 0.55),
                      AppColors.surface.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 92,
                        height: 92,
                        child: LocalOrNetworkImage(
                          source: record.imageUrl,
                          errorBuilder: (_) => const ArtworkPlaceholder(
                            iconSize: 32,
                            backgroundColor: AppColors.surface,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'PICK UP WHERE YOU LEFT OFF',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              record.trackName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              _resumeSubtitle(record),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      if (albumId != null) const SizedBox(width: AppSpacing.md),
                    ],
                  ),
                ),
                if (record.durationMs > 0)
                  LinearProgressIndicator(
                    value: record.progress,
                    minHeight: 2,
                    backgroundColor: AppColors.surfaceHighlight.withValues(
                      alpha: 0.6,
                    ),
                    color: AppColors.primary,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _resumeSubtitle(LastPlayedRecord r) {
    final parts = <String>[
      if (r.artistName.isNotEmpty) r.artistName,
      if (r.albumName != null && r.albumName!.isNotEmpty) r.albumName!,
    ];
    return parts.join(' · ');
  }
}
