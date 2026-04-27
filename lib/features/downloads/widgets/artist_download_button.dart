import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/downloads/download_preferences.dart';
import '../../../data/jellyfin/jellyfin_repository.dart';
import '../../../data/jellyfin/models/media_item.dart';
import 'wifi_required_dialog.dart';

class ArtistDownloadButton extends ConsumerStatefulWidget {
  const ArtistDownloadButton({required this.artist, super.key});
  final Artist artist;

  @override
  ConsumerState<ArtistDownloadButton> createState() =>
      _ArtistDownloadButtonState();
}

class _ArtistDownloadButtonState extends ConsumerState<ArtistDownloadButton> {
  bool _fetching = false;

  Future<void> _downloadAll() async {
    final prefs = ref.read(downloadPreferencesProvider.notifier);
    final canDownload = await prefs.canDownloadNow();
    if (!mounted) return;
    if (!canDownload) {
      showWifiRequiredDialog(context);
      return;
    }

    setState(() => _fetching = true);
    final repo = ref.read(jellyfinRepositoryProvider);
    final manager = ref.read(downloadManagerProvider.notifier);

    var enqueued = 0;
    var failed = 0;

    try {
      final albums = await Future.wait(
        widget.artist.albums.map((a) async {
          try {
            return await repo.album(a.id);
          } catch (_) {
            return null;
          }
        }),
      );
      for (final album in albums) {
        if (album == null) {
          failed++;
          continue;
        }
        await manager.enqueueAlbum(album);
        prefs.subscribeAlbum(album.id);
        enqueued += album.tracks.length;
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }

    if (!mounted) return;
    final msg = enqueued == 0
        ? 'Nothing to download'
        : 'Downloading $enqueued song${enqueued == 1 ? '' : 's'} from ${widget.artist.name}'
            '${failed > 0 ? ' ($failed album${failed == 1 ? '' : 's'} failed)' : ''}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadManagerProvider);
    final manager = ref.read(downloadManagerProvider.notifier);

    if (!manager.supported) return const SizedBox.shrink();
    if (widget.artist.albums.isEmpty) return const SizedBox.shrink();

    final albumIds = widget.artist.albums.map((a) => a.id).toSet();
    final inProgress = downloads.progress.keys.any((trackId) {
      final albumId = downloads.tracks[trackId]?.albumId;
      return albumId != null && albumIds.contains(albumId);
    });
    final hasQueuedForArtist = downloads.queuedTrackIds.any((trackId) {
      final albumId = downloads.tracks[trackId]?.albumId;
      return albumId != null && albumIds.contains(albumId);
    });
    final isBlocked = !inProgress &&
        hasQueuedForArtist &&
        downloads.isBlockedByWifiOnly;

    if (_fetching) {
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
      onPressed: _downloadAll,
    );
  }
}
