import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart' as jf;
import 'package:altsound/data/local/playback_preferences.dart';

MediaItem mediaItemForTrack({
  required Ref ref,
  required JellyfinRepository repo,
  required DownloadManager downloads,
  required jf.Track track,
  String? contextId,
  String? syncPlayPlaylistItemId,
}) {
  final localPath = downloads.localPath(track.id);
  final localArtPath = downloads.localArtworkPath(track.id);
  final art = (track.imageTag == null || track.imageTag!.isEmpty)
      ? null
      : (localArtPath != null
            ? Uri.file(localArtPath).toString()
            : repo.imageUrl(
                track.imageItemId,
                imageTag: track.imageTag,
                size: 600,
              ));
  final quality = ref.read(playbackPreferencesProvider).streamingQuality;
  final streamUrl = localPath != null
      ? Uri.file(localPath).toString()
      : repo.streamUrl(
          track.id,
          maxBitrate: quality == StreamingQuality.original
              ? null
              : quality.bitrate,
        );
  return MediaItem(
    id: track.id,
    title: track.name,
    album: track.albumName,
    artist: track.artistName,
    duration: track.duration,
    artUri: art == null ? null : Uri.parse(art),
    extras: {
      'streamUrl': streamUrl,
      'streamingQuality': quality.name,
      'jellyfinId': track.id,
      'albumId': track.albumId,
      'artistId': track.artistId,
      'isOffline': localPath != null,
      if (contextId != null) 'contextId': contextId,
      if (syncPlayPlaylistItemId != null)
        'syncPlayPlaylistItemId': syncPlayPlaylistItemId,
    },
  );
}
