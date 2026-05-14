import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/download_preferences.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';

/// Outcome of [ArtistDownloadFetchesController.downloadAll].
typedef ArtistDownloadResult = ({int enqueued, int failed});

/// Tracks which artists currently have a "download all" metadata fetch in
/// flight. Lifted out of the button widget so the spinner survives screen
/// dismounts (user backs out and comes back) and the underlying work keeps
/// running to completion either way.
final artistDownloadFetchesProvider =
    NotifierProvider<ArtistDownloadFetchesController, Set<String>>(
      ArtistDownloadFetchesController.new,
    );

class ArtistDownloadFetchesController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool isFetching(String artistId) => state.contains(artistId);

  /// Fetch every album's full track list for [artist] and enqueue them all,
  /// subscribing each album in [downloadPreferencesProvider]. While running,
  /// [artist.id] is added to [state] so the UI can render a spinner.
  Future<ArtistDownloadResult> downloadAll(Artist artist) async {
    state = {...state, artist.id};
    final repo = ref.read(jellyfinRepositoryProvider);
    final manager = ref.read(downloadManagerProvider.notifier);
    final prefs = ref.read(downloadPreferencesProvider.notifier);

    var enqueued = 0;
    var failed = 0;
    try {
      final albums = await Future.wait(
        artist.albums.map((a) async {
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
      state = {...state}..remove(artist.id);
    }
    return (enqueued: enqueued, failed: failed);
  }
}
