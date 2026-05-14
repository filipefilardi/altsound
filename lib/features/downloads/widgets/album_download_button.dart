import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/download_preferences.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/downloads/widgets/collection_download_button.dart';

class AlbumDownloadButton extends ConsumerWidget {
  const AlbumDownloadButton({required this.album, super.key});
  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CollectionDownloadButton(
      tracks: album.tracks,
      confirmDialogTitle: 'Remove download',
      confirmDialogContent: 'Remove "${album.name}" from your downloads?',
      downloadTooltip: 'Download album',
      onEnqueue: () {
        ref.read(downloadManagerProvider.notifier).enqueueAlbum(album);
        ref.read(downloadPreferencesProvider.notifier).subscribeAlbum(album.id);
      },
      onDelete: () {
        ref.read(downloadManagerProvider.notifier).deleteAlbum(album.id);
        ref
            .read(downloadPreferencesProvider.notifier)
            .unsubscribeAlbum(album.id);
      },
    );
  }
}
