import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/data/jellyfin/playback_reporting_api.dart';

final recentlyAddedProvider = FutureProvider.autoDispose<List<BrowseItem>>(
  (ref) => ref.watch(jellyfinRepositoryProvider).recentlyAddedAlbums(),
);

final recentlyPlayedProvider = FutureProvider.autoDispose<List<BrowseItem>>(
  (ref) => ref.watch(jellyfinRepositoryProvider).recentlyPlayedAlbums(),
);

final mostPlayedProvider = FutureProvider.autoDispose<List<BrowseItem>>((
  ref,
) async {
  const limit = 20;
  const weekDays = 7;
  final repo = ref.watch(jellyfinRepositoryProvider);
  final reporting = ref.watch(playbackReportingApiProvider);

  // Preferred: plugin's all-user weekly activity, then map track ids -> albums.
  final breakdown = await reporting.globalItemBreakdown(
    days: weekDays,
    limit: 500,
  );
  if (breakdown != null && breakdown.isNotEmpty) {
    final trackIds = breakdown.map((b) => b.label).toList(growable: false);
    final tracks = await repo.tracksByIds(trackIds);
    final trackById = {for (final t in tracks) t.id: t};
    final scoreByAlbumId = <String, int>{};
    final orderByAlbumId = <String, int>{};
    var order = 0;
    for (final row in breakdown) {
      final track = trackById[row.label];
      final albumId = track?.albumId;
      if (albumId == null || albumId.isEmpty) continue;
      final score = row.count > 0 ? row.count : row.timeSeconds;
      if (score <= 0) continue;
      scoreByAlbumId.update(albumId, (v) => v + score, ifAbsent: () => score);
      orderByAlbumId.putIfAbsent(albumId, () => order++);
    }
    if (scoreByAlbumId.isNotEmpty) {
      final albumIds = scoreByAlbumId.keys.toList()
        ..sort((a, b) {
          final byScore = scoreByAlbumId[b]!.compareTo(scoreByAlbumId[a]!);
          return byScore != 0
              ? byScore
              : orderByAlbumId[a]!.compareTo(orderByAlbumId[b]!);
        });
      final albums = await repo.itemsByIds(albumIds.take(limit).toList());
      final filtered = albums
          .where((a) => a.kind == MediaKind.album)
          .toList(growable: false);
      if (filtered.isNotEmpty) return filtered;
    }
  }

  // Fallback: still weekly, but scoped to current user only.
  final since = DateTime.now().toUtc().subtract(const Duration(days: weekDays));
  final weekly = await repo.mostPlayedAlbumsSince(since: since, limit: limit);
  if (weekly.isNotEmpty) return weekly;

  // Last resort for servers that don't honor MinDateLastPlayed well.
  return repo.mostPlayedAlbums(limit: limit);
});
