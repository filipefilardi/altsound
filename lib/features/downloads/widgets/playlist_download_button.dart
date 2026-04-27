import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/downloads/download_manager.dart';
import '../../../data/downloads/download_preferences.dart';
import '../../../data/jellyfin/models/media_item.dart';
import 'collection_download_button.dart';

class PlaylistDownloadButton extends ConsumerWidget {
  const PlaylistDownloadButton({required this.playlist, super.key});
  final PlaylistDetail playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CollectionDownloadButton(
      tracks: playlist.tracks,
      confirmDialogTitle: 'Remove downloads',
      confirmDialogContent:
          'Remove all downloaded songs from "${playlist.name}"?',
      downloadTooltip: 'Download playlist',
      onEnqueue: () {
        ref.read(downloadManagerProvider.notifier).enqueuePlaylist(playlist);
        ref
            .read(downloadPreferencesProvider.notifier)
            .subscribePlaylist(playlist.id);
      },
      onDelete: () {
        ref
            .read(downloadManagerProvider.notifier)
            .deletePlaylist(playlist.id);
        ref
            .read(downloadPreferencesProvider.notifier)
            .unsubscribePlaylist(playlist.id);
      },
    );
  }
}
