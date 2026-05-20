import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/empty_state.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/downloaded_track.dart';
import 'package:altsound/features/downloads/widgets/downloaded_album_tile.dart';
import 'package:altsound/features/downloads/widgets/downloads_summary.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    final manager = ref.read(downloadManagerProvider.notifier);

    if (!manager.supported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Downloads')),
        body: const EmptyState(
          icon: PiconsRegular.cloudSlash,
          title: "Downloads aren't available on web",
          message: 'Open AltSound on iOS or Android to download for offline.',
        ),
      );
    }

    final byAlbum = <String, List<DownloadedTrack>>{};
    for (final t in downloads.tracks.values) {
      byAlbum.putIfAbsent(t.albumId ?? 'unknown', () => []).add(t);
    }
    final albumIds = byAlbum.keys.toList()
      ..sort((a, b) {
        final aDate = byAlbum[a]!
            .map((t) => t.downloadedAt)
            .reduce((x, y) => x.isAfter(y) ? x : y);
        final bDate = byAlbum[b]!
            .map((t) => t.downloadedAt)
            .reduce((x, y) => x.isAfter(y) ? x : y);
        return bDate.compareTo(aDate);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: albumIds.isEmpty
          ? const EmptyState(
              icon: PiconsRegular.downloadSimple,
              title: 'No downloads yet',
              message: 'Tap the download icon on any album to keep it offline.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.miniPlayerInset,
              ),
              itemCount: albumIds.length + 2,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return DownloadsSummary(
                    trackCount: downloads.tracks.length,
                    albumCount: albumIds.length,
                    totalSize: downloads.totalSizeBytes,
                    queueLength: downloads.queueLength,
                  );
                }
                if (i == 1) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xs,
                      AppSpacing.md,
                      0,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      'READY OFFLINE',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  );
                }

                final albumId = albumIds[i - 2];
                final tracks = byAlbum[albumId]!;
                final first = tracks.first;
                return DownloadedAlbumTile(
                  albumId: albumId,
                  trackCount: tracks.length,
                  totalSize: tracks.fold(0, (s, t) => s + t.fileSize),
                  totalDuration: tracks.fold(
                    Duration.zero,
                    (s, t) => s + t.duration,
                  ),
                  albumName: first.albumName ?? 'Unknown album',
                  artistName: first.artistName,
                  imageItemId: first.imageItemId,
                  imageTag: first.imageTag,
                );
              },
            ),
    );
  }
}
