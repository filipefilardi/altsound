import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/empty_state.dart';
import 'package:altsound/core/widgets/local_or_network_image.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/downloaded_playlist.dart';
import 'package:altsound/data/downloads/downloaded_track.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/local/connectivity_provider.dart';

class OfflineLibraryView extends ConsumerWidget {
  const OfflineLibraryView({
    super.key,
    this.showEmptyState = true,
    this.scrollable = true,
    this.padding = const EdgeInsets.only(
      top: AppSpacing.sm,
      bottom: AppSpacing.miniPlayerInset,
    ),
  });

  final bool showEmptyState;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    final isOffline = ref.watch(isOfflineProvider);

    final albums = _groupAlbums(downloads.tracks.values.toList());
    final playlists = downloads.playlists.values.toList()
      ..sort((a, b) {
        final aTime = _latestDownload(a, downloads);
        final bTime = _latestDownload(b, downloads);
        return bTime.compareTo(aTime);
      });

    if (albums.isEmpty && playlists.isEmpty) {
      if (!showEmptyState) return const SizedBox.shrink();
      return EmptyState(
        icon: isOffline ? Icons.wifi_off_rounded : Icons.download_rounded,
        title: isOffline ? "You're offline" : 'No downloads yet',
        message: isOffline
            ? 'No downloaded songs yet.\nDownload albums or playlists while online to listen anywhere.'
            : 'Downloaded albums and playlists will appear here.',
      );
    }

    final repo = ref.watch(jellyfinRepositoryProvider);
    final items = <_OfflineItem>[];

    if (playlists.isNotEmpty) {
      items.add(const _OfflineItem.header('Playlists'));
      for (final p in playlists) {
        items.add(_OfflineItem.playlist(p));
      }
    }

    if (albums.isNotEmpty) {
      items.add(const _OfflineItem.header('Albums'));
      for (final a in albums) {
        items.add(_OfflineItem.album(a));
      }
    }

    return ListView.builder(
      padding: padding,
      primary: scrollable ? null : false,
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item.isHeader) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(
              item.header!.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          );
        }

        if (item.playlist != null) {
          final p = item.playlist!;
          final trackCount = p.trackIds
              .where((id) => downloads.tracks.containsKey(id))
              .length;
          final localArt = _firstLocalArtwork(
            p.trackIds
                .map((id) => downloads.tracks[id])
                .whereType<DownloadedTrack>(),
          );
          final remoteArt = isOffline || p.imageTag == null
              ? null
              : repo.imageUrl(p.id, imageTag: p.imageTag, size: 200);
          return _ContentTile(
            imageSource: localArt ?? remoteArt,
            title: p.name,
            subtitle: '$trackCount songs downloaded',
            isRound: false,
            onTap: () => context.push('/playlist/${p.id}'),
          );
        }

        final a = item.album!;
        final localArt = _firstLocalArtwork(a.tracks);
        final remoteArt = isOffline || a.imageTag == null
            ? null
            : repo.imageUrl(a.imageItemId, imageTag: a.imageTag, size: 200);
        return _ContentTile(
          imageSource: localArt ?? remoteArt,
          title: a.albumName,
          subtitle: '${a.artistName} · ${a.trackCount} songs',
          isRound: false,
          onTap: () => context.push('/album/${a.albumId}'),
        );
      },
    );
  }

  /// Returns the first non-null artwork path among [tracks], or null.
  String? _firstLocalArtwork(Iterable<DownloadedTrack> tracks) {
    for (final t in tracks) {
      final p = t.artworkPath;
      if (p != null && p.isNotEmpty) return p;
    }
    return null;
  }

  List<_AlbumGroup> _groupAlbums(List<DownloadedTrack> tracks) {
    final map = <String, List<DownloadedTrack>>{};
    for (final t in tracks) {
      (map[t.albumId ?? 'unknown'] ??= []).add(t);
    }
    return map.entries.map((e) => _AlbumGroup(e.key, e.value)).toList()
      ..sort((a, b) => b.latestDownload.compareTo(a.latestDownload));
  }

  DateTime _latestDownload(
    DownloadedPlaylist playlist,
    DownloadsState downloads,
  ) {
    final times = playlist.trackIds
        .map((id) => downloads.tracks[id]?.downloadedAt)
        .where((t) => t != null)
        .cast<DateTime>();
    if (times.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return times.reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

// ── data helpers ────────────────────────────────────────────────────────────

class _AlbumGroup {
  _AlbumGroup(this.albumId, this.tracks);
  final String albumId;
  final List<DownloadedTrack> tracks;

  String get albumName => tracks.first.albumName ?? 'Unknown Album';
  String get artistName => tracks.first.artistName;
  String get imageItemId => tracks.first.imageItemId;
  String? get imageTag => tracks.first.imageTag;
  int get trackCount => tracks.length;
  DateTime get latestDownload =>
      tracks.map((t) => t.downloadedAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

class _OfflineItem {
  const _OfflineItem._({this.header, this.playlist, this.album});

  const _OfflineItem.header(String text) : this._(header: text);
  const _OfflineItem.playlist(DownloadedPlaylist p) : this._(playlist: p);
  _OfflineItem.album(_AlbumGroup a) : this._(album: a);

  final String? header;
  final DownloadedPlaylist? playlist;
  final _AlbumGroup? album;

  bool get isHeader => header != null;
}

// ── shared tile ─────────────────────────────────────────────────────────────

class _ContentTile extends StatelessWidget {
  const _ContentTile({
    required this.imageSource,
    required this.title,
    required this.subtitle,
    required this.isRound,
    required this.onTap,
  });

  final String? imageSource;
  final String title;
  final String subtitle;
  final bool isRound;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(isRound ? 28 : 6),
        child: SizedBox(
          width: 52,
          height: 52,
          child: LocalOrNetworkImage(
            source: imageSource,
            placeholderBuilder: (_) =>
                const ColoredBox(color: AppColors.surfaceElevated),
            errorBuilder: (_) => const ColoredBox(
              color: AppColors.surfaceElevated,
              child: Icon(
                Icons.album_rounded,
                color: AppColors.textTertiary,
                size: 24,
              ),
            ),
          ),
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      onTap: onTap,
    );
  }
}
