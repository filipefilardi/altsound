import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/jellyfin/jellyfin_repository.dart';
import '../../../data/jellyfin/models/media_item.dart';
import '../current_track_playlist_presence.dart';
import '../now_playing_favorite.dart';

void _invalidateTrackPlaylistPresence(WidgetRef ref) {
  ref.invalidate(currentTrackPlaylistPresenceProvider);
}

/// Opens the add-to-playlist sheet (and handles selection). When
/// [includeLikedSongsShortcut] is true, offers "Liked songs" first (favorite +
/// Jellyfin Liked Songs playlist).
Future<void> openAddTrackToPlaylistFlow(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  bool includeLikedSongsShortcut = false,
}) async {
  final repo = ref.read(jellyfinRepositoryProvider);
  final playlists = await repo.playlists();
  if (!context.mounted) return;

  if (playlists.isEmpty && !includeLikedSongsShortcut) {
    await _showCreatePlaylistDialog(context, ref, trackId: trackId);
    _invalidateTrackPlaylistPresence(ref);
    return;
  }

  final selectedId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(
        child: ListView(
          children: [
            if (includeLikedSongsShortcut) ...[
              ListTile(
                leading: const Icon(Icons.favorite),
                title: const Text('Liked songs'),
                subtitle: const Text('Favorite and add to Liked Songs playlist'),
                onTap: () => Navigator.of(sheetContext).pop('__liked__'),
              ),
              if (playlists.isNotEmpty) const Divider(height: 1),
            ],
            const ListTile(
              title: Text('Add to playlist'),
            ),
            ...playlists.map(
              (playlist) => ListTile(
                title: Text(playlist.name),
                onTap: () => Navigator.of(sheetContext).pop(playlist.id),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.playlist_add_circle_outlined),
              title: const Text('Create new playlist'),
              onTap: () => Navigator.of(sheetContext).pop('__create__'),
            ),
          ],
        ),
      ),
    ),
  );

  if (!context.mounted) return;
  await _handlePlaylistSelection(context, ref, trackId: trackId, selectedId: selectedId);
  _invalidateTrackPlaylistPresence(ref);
}

/// Lists playlists (and favorite-only state) the track is saved in; tap a row
/// to remove from that playlist (and clear favorite when removing Liked songs).
Future<void> openManageTrackPlaylistsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  required CurrentTrackPlaylistPresence presence,
}) async {
  final repo = ref.read(jellyfinRepositoryProvider);
  final likedPlaylist = await repo.likedSongsPlaylist();
  final likedId = likedPlaylist?.id;

  final inLikedPlaylist = likedId != null &&
      presence.memberships.any((m) => m.playlistId == likedId);

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(
        child: ListView(
          children: [
            const ListTile(
              title: Text('Saved in'),
              subtitle: Text('Tap a row to remove'),
            ),
            if (presence.isFavorite && !inLikedPlaylist)
              ListTile(
                leading: const Icon(Icons.favorite),
                title: const Text('Favorites'),
                trailing: const Icon(Icons.remove_circle_outline),
                onTap: () async {
                  try {
                    await repo.setFavorite(trackId, favorite: false);
                    if (!sheetContext.mounted) return;
                    Navigator.of(sheetContext).pop();
                    _invalidateTrackPlaylistPresence(ref);
                    ref.invalidate(nowPlayingFavoriteProvider);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Removed from favorites')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not update: $e')),
                    );
                  }
                },
              ),
            ...presence.memberships.map(
              (m) => ListTile(
                leading: Icon(
                  likedId != null && m.playlistId == likedId
                      ? Icons.favorite
                      : Icons.playlist_play,
                ),
                title: Text(m.playlistName),
                trailing: const Icon(Icons.remove_circle_outline),
                onTap: () async {
                  try {
                    await repo.removeTrackFromPlaylistByEntry(
                      playlistId: m.playlistId,
                      playlistItemEntryId: m.playlistItemEntryId,
                    );
                    if (likedId != null && m.playlistId == likedId) {
                      await repo.setFavorite(trackId, favorite: false);
                    }
                    if (!sheetContext.mounted) return;
                    Navigator.of(sheetContext).pop();
                    _invalidateTrackPlaylistPresence(ref);
                    ref.invalidate(nowPlayingFavoriteProvider);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Removed from ${m.playlistName}')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not remove: $e')),
                    );
                  }
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to another playlist'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(
                  openAddTrackToPlaylistFlow(
                    context,
                    ref,
                    trackId: trackId,
                    includeLikedSongsShortcut: true,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _handlePlaylistSelection(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  required String? selectedId,
}) async {
  if (selectedId == null) return;
  final repo = ref.read(jellyfinRepositoryProvider);
  if (selectedId == '__create__') {
    await _showCreatePlaylistDialog(context, ref, trackId: trackId);
    return;
  }
  if (selectedId == '__liked__') {
    try {
      await repo.setFavorite(trackId, favorite: true);
      await repo.addTrackToLikedSongs(trackId);
      ref.invalidate(nowPlayingFavoriteProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Liked songs')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
    return;
  }

  final playlists = await repo.playlists();
  if (!context.mounted) return;
  BrowseItem? selected;
  for (final p in playlists) {
    if (p.id == selectedId) {
      selected = p;
      break;
    }
  }
  if (selected == null) return;
  await repo.addTrackToPlaylist(trackId: trackId, playlistId: selectedId);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Added to ${selected.name}')),
  );
}

Future<void> _showCreatePlaylistDialog(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
}) async {
  final ctrl = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Create playlist'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  final playlistName = name?.trim() ?? '';
  if (playlistName.isEmpty) return;

  final repo = ref.read(jellyfinRepositoryProvider);
  final created = await repo.createPlaylist(playlistName);
  await repo.addTrackToPlaylist(trackId: trackId, playlistId: created.id);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Playlist "${created.name}" created')),
  );
}
