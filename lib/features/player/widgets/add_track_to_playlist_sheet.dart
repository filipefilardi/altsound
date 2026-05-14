import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/player/current_track_playlist_presence.dart';
import 'package:altsound/features/player/now_playing_favorite.dart';
import 'package:altsound/features/playlist/playlist_providers.dart';

void _invalidateTrackPlaylistPresence(WidgetRef ref) {
  ref.invalidate(currentTrackPlaylistPresenceProvider);
}

Future<void> openAddTrackToPlaylistFlow(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  bool includeLikedSongsShortcut = false,
}) async {
  if (includeLikedSongsShortcut) {
    await _addTrackToLikedSongs(context, ref, trackId: trackId);
    return;
  }
  await openManageTrackPlaylistsSheet(context, ref, trackId: trackId);
  _invalidateTrackPlaylistPresence(ref);
}

Future<void> _addTrackToLikedSongs(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
}) async {
  final repo = ref.read(jellyfinRepositoryProvider);
  try {
    await repo.setFavorite(trackId, favorite: true);
    await repo.addTrackToLikedSongs(trackId);
    final liked = await repo.likedSongsPlaylist();
    if (liked != null) {
      ref.invalidate(playlistProvider(liked.id));
    }
    ref.invalidate(likedSongsPlaylistProvider);
    _invalidateTrackPlaylistPresence(ref);
    ref.invalidate(nowPlayingFavoriteProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Added to Liked songs')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not add to Liked songs: $e')));
  }
}

Future<void> openAddTracksToPlaylistFlow(
  BuildContext context,
  WidgetRef ref, {
  required List<String> trackIds,
}) async {
  if (trackIds.isEmpty) return;
  final repo = ref.read(jellyfinRepositoryProvider);
  final playlists = await repo.playlists();
  if (!context.mounted) return;

  final target = await showModalBottomSheet<BrowseItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(child: _PickPlaylistSheet(playlists: playlists)),
    ),
  );
  if (target == null || !context.mounted) return;

  var addedCount = 0;
  var skippedCount = 0;
  for (final id in trackIds) {
    final added = await repo.addTrackToPlaylist(
      trackId: id,
      playlistId: target.id,
    );
    if (added) {
      addedCount++;
    } else {
      skippedCount++;
    }
  }
  ref.invalidate(playlistProvider(target.id));
  if (!context.mounted) return;
  final skippedText = skippedCount == 0
      ? ''
      : ' · $skippedCount duplicate${skippedCount == 1 ? '' : 's'} skipped';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Added $addedCount song${addedCount == 1 ? '' : 's'} to "${target.name}"$skippedText',
      ),
    ),
  );
}

/// Fetches the correct presence for [trackId] then shows the manage sheet.
Future<void> openManageTrackPlaylistsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
}) async {
  final repo = ref.read(jellyfinRepositoryProvider);
  final results = await Future.wait([
    repo.likedSongsPlaylist(),
    repo.playlists(),
    repo.isFavorite(trackId),
  ]);

  final likedPlaylist = results[0] as BrowseItem?;
  final allPlaylists = results[1] as List<BrowseItem>;
  final isFavorite = results[2] as bool;

  final memberships = await repo.playlistsContainingTrack(
    trackId,
    playlistsCache: allPlaylists,
  );
  final presence = CurrentTrackPlaylistPresence(
    isFavorite: isFavorite,
    memberships: memberships,
  );

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
          initialPlaylists: allPlaylists,
          likedPlaylistId: likedPlaylist?.id,
        ),
      ),
    ),
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
      title: const Text('New playlist'),
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
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Playlist "${created.name}" created')));
}

class _ManageTrackPlaylistsSheet extends ConsumerStatefulWidget {
  const _ManageTrackPlaylistsSheet({
    required this.trackId,
    required this.initialPresence,
    required this.initialPlaylists,
    required this.likedPlaylistId,
  });

  final String trackId;
  final CurrentTrackPlaylistPresence initialPresence;
  final List<BrowseItem> initialPlaylists;
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
  late List<BrowseItem> _allPlaylists;
  String? _likedPlaylistId;
  bool _isFavorite = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _allPlaylists = List.of(widget.initialPlaylists);
    _likedPlaylistId = widget.likedPlaylistId;
    _isFavorite = widget.initialPresence.isFavorite;
    for (final membership in widget.initialPresence.memberships) {
      _playlistIdsContainingTrack.add(membership.playlistId);
      _entryIdByPlaylistId[membership.playlistId] =
          membership.playlistItemEntryId;
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
    final playlists = _allPlaylists.where((playlist) {
      if (_likedPlaylistId != null && playlist.id == _likedPlaylistId) {
        return false;
      }
      if (_query.isEmpty) return true;
      return playlist.name.toLowerCase().contains(_query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Text(
            'ADD TO PLAYLIST',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Search playlists',
              prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              _NewPlaylistRow(
                onTap: () => unawaited(_createPlaylistAndAttach(context)),
              ),
              const SizedBox(height: AppSpacing.xs),
              _PlaylistToggleRow(
                icon: PhosphorIconsRegular.heart,
                iconColor: AppColors.like,
                title: 'Liked songs',
                selected:
                    _likedPlaylistId != null &&
                    _playlistIdsContainingTrack.contains(_likedPlaylistId),
                onTap: () => unawaited(
                  _toggleLikedSongs(
                    selected:
                        !(_likedPlaylistId != null &&
                            _playlistIdsContainingTrack.contains(
                              _likedPlaylistId,
                            )),
                  ),
                ),
              ),
              ...playlists.map(
                (playlist) => _PlaylistToggleRow(
                  icon: PhosphorIconsRegular.queue,
                  iconColor: AppColors.primary,
                  title: playlist.name,
                  selected: _playlistIdsContainingTrack.contains(playlist.id),
                  onTap: () => unawaited(
                    _togglePlaylist(
                      playlist: playlist,
                      selected: !_playlistIdsContainingTrack.contains(
                        playlist.id,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
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
        final entryId =
            _entryIdByPlaylistId[playlist.id] ??
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
      ref.invalidate(playlistProvider(playlist.id));
      _invalidateTrackPlaylistPresence(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update ${playlist.name}: $e')),
      );
    }
  }

  Future<void> _toggleLikedSongs({required bool selected}) async {
    final repo = ref.read(jellyfinRepositoryProvider);
    try {
      if (selected) {
        await repo.setFavorite(widget.trackId, favorite: true);
        await repo.addTrackToLikedSongs(widget.trackId);
        final liked = await repo.likedSongsPlaylist();
        final likedId = liked?.id;
        if (likedId == null) {
          throw StateError('Could not resolve Liked songs playlist');
        }
        final entryId = await repo.playlistEntryIdForTrack(
          playlistId: likedId,
          trackId: widget.trackId,
        );
        if (!mounted) return;
        setState(() {
          _isFavorite = true;
          _likedPlaylistId = likedId;
          if (_allPlaylists.every((playlist) => playlist.id != likedId) &&
              liked != null) {
            _allPlaylists = [liked, ..._allPlaylists];
          }
          _playlistIdsContainingTrack.add(likedId);
          if (entryId != null) _entryIdByPlaylistId[likedId] = entryId;
        });
      } else {
        final likedId = _likedPlaylistId;
        if (likedId == null) return;
        final entryId =
            _entryIdByPlaylistId[likedId] ??
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
      final likedId = _likedPlaylistId;
      if (likedId != null) {
        ref.invalidate(playlistProvider(likedId));
      }
      ref.invalidate(likedSongsPlaylistProvider);
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
    final liked = await repo.likedSongsPlaylist();
    final refreshedPlaylists = await repo.playlists();
    final refreshedMemberships = await repo.playlistsContainingTrack(
      widget.trackId,
      playlistsCache: refreshedPlaylists,
    );
    if (!mounted) return;
    setState(() {
      _allPlaylists = refreshedPlaylists;
      _likedPlaylistId = liked?.id;
      _playlistIdsContainingTrack
        ..clear()
        ..addAll(refreshedMemberships.map((m) => m.playlistId));
      _entryIdByPlaylistId
        ..clear()
        ..addEntries(
          refreshedMemberships.map(
            (m) => MapEntry(m.playlistId, m.playlistItemEntryId),
          ),
        );
    });
    for (final m in refreshedMemberships) {
      ref.invalidate(playlistProvider(m.playlistId));
    }
    _invalidateTrackPlaylistPresence(ref);
  }
}

class _NewPlaylistRow extends StatelessWidget {
  const _NewPlaylistRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: const Icon(
          PhosphorIconsRegular.plus,
          color: AppColors.primary,
          size: 22,
        ),
      ),
      title: Text(
        'New playlist',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: onTap,
    );
  }
}

class _PlaylistToggleRow extends StatelessWidget {
  const _PlaylistToggleRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          selected ? PhosphorIconsRegular.checkCircle : PhosphorIconsRegular.circle,
          key: ValueKey(selected),
          color: selected ? AppColors.primary : AppColors.textTertiary,
          size: 22,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _PickPlaylistSheet extends StatefulWidget {
  const _PickPlaylistSheet({required this.playlists});

  final List<BrowseItem> playlists;

  @override
  State<_PickPlaylistSheet> createState() => _PickPlaylistSheetState();
}

class _PickPlaylistSheetState extends State<_PickPlaylistSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
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
    final playlists = widget.playlists.where((playlist) {
      if (_query.isEmpty) return true;
      return playlist.name.toLowerCase().contains(_query);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Text(
            'ADD TO PLAYLIST',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Search playlists',
              prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
            ),
          ),
        ),
        Expanded(
          child: playlists.isEmpty
              ? const Center(
                  child: Text(
                    'No playlists found',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  itemCount: playlists.length,
                  itemBuilder: (_, index) {
                    final playlist = playlists[index];
                    return ListTile(
                      leading: const Icon(
                        PhosphorIconsRegular.queue,
                        color: AppColors.primary,
                      ),
                      title: Text(playlist.name),
                      onTap: () => Navigator.of(context).pop(playlist),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
