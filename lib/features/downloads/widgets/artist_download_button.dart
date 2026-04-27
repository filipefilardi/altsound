import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/downloads/download_preferences.dart';
import '../../../data/jellyfin/models/media_item.dart';
import 'artist_download_fetches.dart';
import 'wifi_required_dialog.dart';

class ArtistDownloadButton extends ConsumerWidget {
  const ArtistDownloadButton({required this.artist, super.key});
  final Artist artist;

  Future<void> _onPressed(BuildContext context, WidgetRef ref) async {
    final prefs = ref.read(downloadPreferencesProvider.notifier);
    final canDownload = await prefs.canDownloadNow();
    if (!context.mounted) return;
    if (!canDownload) {
      showWifiRequiredDialog(context);
      return;
    }

    final result = await ref
        .read(artistDownloadFetchesProvider.notifier)
        .downloadAll(artist);
    if (!context.mounted) return;

    final enqueued = result.enqueued;
    final failed = result.failed;
    final msg = enqueued == 0
        ? 'Nothing to download'
        : 'Downloading $enqueued song${enqueued == 1 ? '' : 's'} from ${artist.name}'
            '${failed > 0 ? ' ($failed album${failed == 1 ? '' : 's'} failed)' : ''}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    final manager = ref.read(downloadManagerProvider.notifier);
    final fetching =
        ref.watch(artistDownloadFetchesProvider).contains(artist.id);

    if (!manager.supported) return const SizedBox.shrink();
    if (artist.albums.isEmpty) return const SizedBox.shrink();

    final albumIds = artist.albums.map((a) => a.id).toSet();
    final inProgress = downloads.progress.keys.any((trackId) {
      final albumId = downloads.tracks[trackId]?.albumId;
      return albumId != null && albumIds.contains(albumId);
    });
    final hasQueuedForArtist = downloads.queuedTrackIds.any((trackId) {
      final albumId = downloads.tracks[trackId]?.albumId;
      return albumId != null && albumIds.contains(albumId);
    });
    final isBlocked =
        !inProgress && hasQueuedForArtist && downloads.isBlockedByWifiOnly;

    if (fetching) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }

    if (inProgress) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Icon(Icons.downloading, color: AppColors.primary),
        ),
      );
    }

    if (isBlocked) {
      return IconButton(
        tooltip: 'Waiting for WiFi — tap to change settings',
        icon: const Icon(Icons.wifi_off_rounded, color: AppColors.textSecondary),
        onPressed: () => showWifiRequiredDialog(context),
      );
    }

    return IconButton(
      tooltip: 'Download all songs',
      icon: const Icon(Icons.download_outlined, color: AppColors.textPrimary),
      onPressed: () => _onPressed(context, ref),
    );
  }
}
