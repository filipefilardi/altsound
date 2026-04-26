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
  final presence = await ref.read(currentTrackPlaylistPresenceProvider.future);
  if (!context.mounted) return;

  if (presence.memberships.isEmpty) {
    await _saveToLikedSongs(context, ref, trackId: trackId);
    _invalidateTrackPlaylistPresence(ref);
    return;
  }

  await openManageTrackPlaylistsSheet(
    context,
    ref,
    trackId: trackId,
    presence: presence,
  );
  _invalidateTrackPlaylistPresence(ref);
}

/// Lists all playlists with search and allows add/remove in place.
Future<void> openManageTrackPlaylistsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  required CurrentTrackPlaylistPresence presence,
}) async {
  final repo = ref.read(jellyfinRepositoryProvider);
  final likedPlaylist = await repo.likedSongsPlaylist();
  final allPlaylists = await repo.playlists();

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(
        child: _ManageTrackPlaylistsSheet(
          trackId: trackId,
          initialPresence: presence,
          allPlaylists: allPlaylists,
          likedPlaylistId: likedPlaylist?.id,
        ),
      ),
    ),
  );
}

Future<void> _saveToLikedSongs(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
}) async {
  final repo = ref.read(jellyfinRepositoryProvider);
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

class _ManageTrackPlaylistsSheet extends ConsumerStatefulWidget {
  const _ManageTrackPlaylistsSheet({
    required this.trackId,
    required this.initialPresence,
    required this.allPlaylists,
    required this.likedPlaylistId,
  });

  final String trackId;
  final CurrentTrackPlaylistPresence initialPresence;
  final List<BrowseItem> allPlaylists;
  final String? likedPlaylistId;

  @override
  ConsumerState<_ManageTrackPlaylistsSheet> createState() =>
      _ManageTrackPlaylistsSheetState();
}

class _ManageTrackPlaylistsSheetState
    extends ConsumerState<_ManageTrackPlaylistsSheet> {
  final _searchCtrl = TextEditingController();
  final Set<String> _playlistIdsContainingTrack = <String>{};
  final Map<String, String> _entryIdByPlaylistId = <String, String>{};
  bool _isFavorite = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.initialPresence.isFavorite;
    for (final membership in widget.initialPresence.memberships) {
      _playlistIdsContainingTrack.add(membership.playlistId);
      _entryIdByPlaylistId[membership.playlistId] = membership.playlistItemEntryId;
    }
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlists = widget.allPlaylists.where((playlist) {
      if (_query.isEmpty) return true;
      return playlist.name.toLowerCase().contains(_query);
    }).toList();

    return Column(
      children: [
        const ListTile(title: Text('Saved in')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Search playlists',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => unawaited(_createPlaylistAndAttach(context)),
              icon: const Icon(Icons.playlist_add),
              label: const Text('Create new playlist'),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (widget.likedPlaylistId != null)
                _PlaylistToggleRow(
                  icon: Icons.favorite,
                  title: 'Liked songs',
                  selected: _playlistIdsContainingTrack.contains(widget.likedPlaylistId),
                  onChanged: (selected) => unawaited(
                    _toggleLikedSongs(selected: selected),
                  ),
                ),
              ...playlists.map(
                (playlist) => _PlaylistToggleRow(
                  icon: Icons.playlist_play,
                  title: playlist.name,
                  selected: _playlistIdsContainingTrack.contains(playlist.id),
                  onChanged: (selected) => unawaited(
                    _togglePlaylist(playlist: playlist, selected: selected),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _togglePlaylist({
    required BrowseItem playlist,
    required bool selected,
  }) async {
    final repo = ref.read(jellyfinRepositoryProvider);
    try {
      if (selected) {
        await repo.addTrackToPlaylist(
          trackId: widget.trackId,
          playlistId: playlist.id,
        );
        final entryId = await repo.playlistEntryIdForTrack(
          playlistId: playlist.id,
          trackId: widget.trackId,
        );
        if (!mounted) return;
        setState(() {
          _playlistIdsContainingTrack.add(playlist.id);
          if (entryId != null) _entryIdByPlaylistId[playlist.id] = entryId;
        });
      } else {
        final entryId = _entryIdByPlaylistId[playlist.id] ??
            await repo.playlistEntryIdForTrack(
              playlistId: playlist.id,
              trackId: widget.trackId,
            );
        if (entryId != null) {
          await repo.removeTrackFromPlaylistByEntry(
            playlistId: playlist.id,
            playlistItemEntryId: entryId,
          );
        }
        if (!mounted) return;
        setState(() {
          _playlistIdsContainingTrack.remove(playlist.id);
          _entryIdByPlaylistId.remove(playlist.id);
        });
      }
      _invalidateTrackPlaylistPresence(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update ${playlist.name}: $e')),
      );
    }
  }

  Future<void> _toggleLikedSongs({required bool selected}) async {
    final likedId = widget.likedPlaylistId;
    if (likedId == null) return;
    final repo = ref.read(jellyfinRepositoryProvider);
    try {
      if (selected) {
        await repo.setFavorite(widget.trackId, favorite: true);
        await repo.addTrackToLikedSongs(widget.trackId);
        final entryId = await repo.playlistEntryIdForTrack(
          playlistId: likedId,
          trackId: widget.trackId,
        );
        if (!mounted) return;
        setState(() {
          _isFavorite = true;
          _playlistIdsContainingTrack.add(likedId);
          if (entryId != null) _entryIdByPlaylistId[likedId] = entryId;
        });
      } else {
        final entryId = _entryIdByPlaylistId[likedId] ??
            await repo.playlistEntryIdForTrack(
              playlistId: likedId,
              trackId: widget.trackId,
            );
        if (entryId != null) {
          await repo.removeTrackFromPlaylistByEntry(
            playlistId: likedId,
            playlistItemEntryId: entryId,
          );
        }
        if (_isFavorite) {
          await repo.setFavorite(widget.trackId, favorite: false);
        }
        if (!mounted) return;
        setState(() {
          _isFavorite = false;
          _playlistIdsContainingTrack.remove(likedId);
          _entryIdByPlaylistId.remove(likedId);
        });
      }
      _invalidateTrackPlaylistPresence(ref);
      ref.invalidate(nowPlayingFavoriteProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update Liked songs: $e')),
      );
    }
  }

  Future<void> _createPlaylistAndAttach(BuildContext context) async {
    await _showCreatePlaylistDialog(context, ref, trackId: widget.trackId);
    if (!mounted) return;
    final repo = ref.read(jellyfinRepositoryProvider);
    final refreshed = await repo.playlistsContainingTrack(
      widget.trackId,
      playlistsCache: widget.allPlaylists,
    );
    if (!mounted) return;
    setState(() {
      _playlistIdsContainingTrack
        ..clear()
        ..addAll(refreshed.map((m) => m.playlistId));
      _entryIdByPlaylistId
        ..clear()
        ..addEntries(
          refreshed.map((m) => MapEntry(m.playlistId, m.playlistItemEntryId)),
        );
    });
    _invalidateTrackPlaylistPresence(ref);
  }
}

class _PlaylistToggleRow extends StatelessWidget {
  const _PlaylistToggleRow({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      onChanged: (value) => onChanged(value ?? false),
      title: Text(title),
      secondary: Icon(icon),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}
