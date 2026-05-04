import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/local_or_network_image.dart';
import '../../core/widgets/play_pill.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../playlist/playlist_providers.dart';
import 'instant_mix.dart';
import 'player_providers.dart';
import 'widgets/mini_player_slot.dart';
import 'widgets/playing_track_leading.dart';
import 'widgets/track_more_menu_button.dart';

typedef _InstantMixRequest = ({String itemId, InstantMixSeedKind? kind});

class InstantMixDetail {
  const InstantMixDetail({required this.tracks, required this.artworkUrl});

  final List<Track> tracks;
  final String? artworkUrl;
}

const _instantMixCacheTtl = Duration(minutes: 10);

final instantMixTracksProvider = FutureProvider.autoDispose
    .family<InstantMixDetail, _InstantMixRequest>((ref, request) async {
      final keepAlive = ref.keepAlive();
      final timer = Timer(_instantMixCacheTtl, keepAlive.close);
      ref.onDispose(timer.cancel);

      final repo = ref.read(jellyfinRepositoryProvider);
      final mixTracks = await repo.instantMix(request.itemId);
      if (request.kind != InstantMixSeedKind.track) {
        return InstantMixDetail(
          tracks: mixTracks,
          artworkUrl: await repo.primaryImageUrl(request.itemId, size: 600),
        );
      }

      final seedTrack = await repo.track(request.itemId);
      return InstantMixDetail(
        tracks: [
          seedTrack,
          ...mixTracks.where((track) => track.id != seedTrack.id),
        ],
        artworkUrl: seedTrack.imageTag == null || seedTrack.imageTag!.isEmpty
            ? null
            : repo.imageUrl(
                seedTrack.imageItemId,
                imageTag: seedTrack.imageTag,
                size: 600,
              ),
      );
    });

class InstantMixScreen extends ConsumerWidget {
  const InstantMixScreen({
    required this.seedItemId,
    required this.seedKind,
    required this.seedTitle,
    super.key,
  });

  final String seedItemId;
  final InstantMixSeedKind? seedKind;
  final String? seedTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = (itemId: seedItemId, kind: seedKind);
    final mixAsync = ref.watch(instantMixTracksProvider(request));

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const MiniPlayerSlot(
        withTopDivider: true,
        reserveSpaceWhenEmpty: true,
      ),
      body: mixAsync.when(
        loading: () => const _InstantMixLoading(),
        error: (e, _) => ErrorStateView(
          title: "Couldn't load Instant Mix",
          message: '$e',
          onRetry: () => ref.invalidate(instantMixTracksProvider(request)),
        ),
        data: (detail) => RefreshIndicator(
          onRefresh: () async =>
              ref.refresh(instantMixTracksProvider(request).future),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                stretch: true,
                leading: const BackButton(),
                expandedHeight: 380,
                backgroundColor: AppColors.background,
                flexibleSpace: FlexibleSpaceBar(
                  background: _InstantMixHeader(
                    seedTitle: seedTitle,
                    artworkUrl: detail.artworkUrl,
                    trackCount: detail.tracks.length,
                  ),
                ),
              ),
              if (detail.tracks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.auto_awesome_rounded,
                    title: 'No songs found',
                    message: 'Jellyfin did not return any tracks for this mix.',
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: _InstantMixActionRow(
                    seedItemId: seedItemId,
                    seedKind: seedKind,
                    seedTitle: seedTitle,
                    tracks: detail.tracks,
                  ),
                ),
                SliverList.builder(
                  itemCount: detail.tracks.length,
                  itemBuilder: (context, index) => _InstantMixTrackTile(
                    seedItemId: seedItemId,
                    tracks: detail.tracks,
                    index: index,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InstantMixHeader extends StatelessWidget {
  const _InstantMixHeader({
    required this.seedTitle,
    required this.artworkUrl,
    required this.trackCount,
  });

  final String? seedTitle;
  final String? artworkUrl;
  final int trackCount;

  @override
  Widget build(BuildContext context) {
    final title = seedTitle?.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.surfaceElevated,
            AppColors.surface,
            AppColors.background,
          ],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                  spreadRadius: -6,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 220,
                height: 220,
                child: LocalOrNetworkImage(
                  source: artworkUrl,
                  placeholderBuilder: (_) => const _InstantMixArtFallback(),
                  errorBuilder: (_) => const _InstantMixArtFallback(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Instant Mix',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            title == null || title.isEmpty ? 'Generated by Jellyfin' : title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (trackCount > 0) ...[
            const SizedBox(height: 2),
            Text(
              '$trackCount song${trackCount == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _InstantMixArtFallback extends StatelessWidget {
  const _InstantMixArtFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceElevated,
      child: const Icon(
        Icons.auto_awesome_rounded,
        color: AppColors.primary,
        size: 64,
      ),
    );
  }
}

class _InstantMixActionRow extends ConsumerWidget {
  const _InstantMixActionRow({
    required this.seedItemId,
    required this.seedKind,
    required this.seedTitle,
    required this.tracks,
  });

  final String seedItemId;
  final InstantMixSeedKind? seedKind;
  final String? seedTitle;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playbackStateProvider).value;
    final currentMediaItem = ref.watch(currentMediaItemProvider).value;
    final shuffleEnabled =
        ref.watch(playerShuffleEnabledProvider).value ?? false;
    final contextId = _instantMixContextId(seedItemId);
    final isMixPlaying =
        playbackState?.playing == true &&
        (currentMediaItem?.extras?['contextId'] as String?) == contextId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          PlayPill(
            onTap: () {
              final controller = ref.read(playerControllerProvider);
              if (isMixPlaying) {
                controller.togglePlay();
                return;
              }
              controller.playTracks(
                tracks,
                contextId: contextId,
                randomizeStart: false,
              );
            },
            icon: isMixPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: isMixPlaying ? 'Pause' : 'Play',
          ),
          const SizedBox(width: 12),
          Expanded(child: _InstantMixMeta(tracks: tracks)),
          IconButton(
            tooltip: 'Shuffle',
            icon: Icon(
              Icons.shuffle_rounded,
              color: shuffleEnabled ? AppColors.primary : AppColors.textPrimary,
            ),
            onPressed: () => ref.read(playerControllerProvider).toggleShuffle(),
          ),
          IconButton(
            tooltip: 'Regenerate mix',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              final request = (itemId: seedItemId, kind: seedKind);
              ref.invalidate(instantMixTracksProvider(request));
            },
          ),
          IconButton(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () async {
              final action = await showModalBottomSheet<_InstantMixAction>(
                context: context,
                showDragHandle: true,
                builder: (sheetContext) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.add_to_queue_rounded),
                        title: const Text('Add to queue'),
                        onTap: () => Navigator.of(
                          sheetContext,
                        ).pop(_InstantMixAction.addToQueue),
                      ),
                      ListTile(
                        leading: const Icon(Icons.playlist_add_rounded),
                        title: const Text('Create playlist from mix'),
                        onTap: () => Navigator.of(
                          sheetContext,
                        ).pop(_InstantMixAction.createPlaylist),
                      ),
                    ],
                  ),
                ),
              );
              if (action == null || !context.mounted) return;
              switch (action) {
                case _InstantMixAction.addToQueue:
                  await _addMixToQueue(context, ref, tracks);
                case _InstantMixAction.createPlaylist:
                  await _createPlaylistFromMix(
                    context,
                    ref,
                    seedTitle: seedTitle,
                    tracks: tracks,
                  );
              }
            },
          ),
        ],
      ),
    );
  }
}

enum _InstantMixAction { addToQueue, createPlaylist }

class _InstantMixMeta extends StatelessWidget {
  const _InstantMixMeta({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final totalDuration = tracks.fold(
      Duration.zero,
      (sum, track) => sum + track.duration,
    );
    return Text(
      formatLongDuration(totalDuration),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

class _InstantMixTrackTile extends ConsumerWidget {
  const _InstantMixTrackTile({
    required this.seedItemId,
    required this.tracks,
    required this.index,
  });

  final String seedItemId;
  final List<Track> tracks;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = tracks[index];
    final contextId = _instantMixContextId(seedItemId);
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == track.id;
    final isCurrentInContext =
        isCurrent && current.extras?['contextId'] == contextId;
    final isDownloaded = ref
        .watch(downloadManagerProvider)
        .isDownloaded(track.id);
    final album = track.albumName;
    final subtitle = album == null || album.isEmpty
        ? track.artistName
        : '${track.artistName} · $album';

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      onTap: () {
        if (isCurrentInContext) {
          context.push('/now-playing');
          return;
        }
        ref
            .read(playerControllerProvider)
            .playTracks(
              tracks,
              startIndex: index,
              contextId: contextId,
              selectedTrack: true,
            );
      },
      leading: PlayingTrackLeading(
        jellyfinTrackId: track.id,
        indexLabel: '${index + 1}',
      ),
      title: Text(
        track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent ? AppColors.primary : AppColors.textPrimary,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDownloaded)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(
                Icons.download_for_offline_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ),
          PlayingTrackDuration(
            jellyfinTrackId: track.id,
            trackDuration: track.duration,
          ),
          TrackMoreMenuButton(track: track),
        ],
      ),
    );
  }
}

class _InstantMixLoading extends StatelessWidget {
  const _InstantMixLoading();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Skeleton.group(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            children: [
              Skeleton.box(width: 220, height: 220),
              const SizedBox(height: 16),
              Skeleton.line(width: 180, height: 18),
              const SizedBox(height: 8),
              Skeleton.line(width: 120, height: 12),
              const SizedBox(height: 28),
              for (int i = 0; i < 8; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Skeleton.box(width: 28, height: 28, radius: 6),
                      const SizedBox(width: 14),
                      Expanded(child: Skeleton.line(height: 14)),
                      const SizedBox(width: 14),
                      Skeleton.line(width: 36, height: 12),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _createPlaylistFromMix(
  BuildContext context,
  WidgetRef ref, {
  required String? seedTitle,
  required List<Track> tracks,
}) async {
  final defaultName = seedTitle == null || seedTitle.trim().isEmpty
      ? 'Instant Mix'
      : 'Instant Mix - ${seedTitle.trim()}';
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _CreateInstantMixPlaylistDialog(initialName: defaultName),
  );
  final playlistName = name?.trim();
  if (playlistName == null || playlistName.isEmpty || !context.mounted) return;

  try {
    final repo = ref.read(jellyfinRepositoryProvider);
    final playlist = await repo.createPlaylist(playlistName);
    await repo.addTracksToPlaylist(
      trackIds: tracks.map((track) => track.id).toList(),
      playlistId: playlist.id,
    );
    ref.invalidate(playlistProvider(playlist.id));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Created "${playlist.name}" with ${tracks.length} song${tracks.length == 1 ? '' : 's'}',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not create playlist: $e')));
  }
}

class _CreateInstantMixPlaylistDialog extends StatefulWidget {
  const _CreateInstantMixPlaylistDialog({required this.initialName});

  final String initialName;

  @override
  State<_CreateInstantMixPlaylistDialog> createState() =>
      _CreateInstantMixPlaylistDialogState();
}

class _CreateInstantMixPlaylistDialogState
    extends State<_CreateInstantMixPlaylistDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

Future<void> _addMixToQueue(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
) async {
  final added = await ref
      .read(playerControllerProvider)
      .addTracksToQueue(tracks);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Added $added song${added == 1 ? '' : 's'} to queue'),
    ),
  );
}

String _instantMixContextId(String seedItemId) => 'instant-mix:$seedItemId';
