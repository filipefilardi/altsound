import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/search_normalization.dart';
import 'package:altsound/core/widgets/empty_state.dart';
import 'package:altsound/core/widgets/error_state.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/widgets/instant_mix_action_row.dart';
import 'package:altsound/features/player/widgets/instant_mix_header.dart';
import 'package:altsound/features/player/widgets/instant_mix_loading.dart';
import 'package:altsound/features/player/widgets/instant_mix_track_tile.dart';
import 'package:altsound/features/player/widgets/mini_player_slot.dart';
import 'package:altsound/features/player/widgets/track_listing_widgets.dart';

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

class InstantMixScreen extends ConsumerStatefulWidget {
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
  ConsumerState<InstantMixScreen> createState() => _InstantMixScreenState();
}

class _InstantMixScreenState extends ConsumerState<InstantMixScreen> {
  final _filterController = TextEditingController();
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      setState(() => _filterQuery = _filterController.text.trim());
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seedItemId = widget.seedItemId;
    final seedKind = widget.seedKind;
    final seedTitle = widget.seedTitle;
    final request = (itemId: seedItemId, kind: seedKind);
    final mixAsync = ref.watch(instantMixTracksProvider(request));

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const MiniPlayerSlot(
        withTopDivider: true,
        reserveSpaceWhenEmpty: true,
      ),
      body: mixAsync.when(
        skipLoadingOnReload: true,
        loading: () => const InstantMixLoading(),
        error: (e, _) => ErrorStateView(
          title: "Couldn't load Instant Mix",
          message: '$e',
          onRetry: () => ref.invalidate(instantMixTracksProvider(request)),
        ),
        data: (detail) {
          final visibleTracks = _visibleMixTracks(detail.tracks, _filterQuery);
          return RefreshIndicator(
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
                    background: InstantMixHeader(
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
                      message:
                          'Jellyfin did not return any tracks for this mix.',
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: InstantMixActionRow(
                      seedItemId: seedItemId,
                      seedKind: seedKind,
                      seedTitle: seedTitle,
                      tracks: visibleTracks,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                      child: TrackFilterBar(
                        controller: _filterController,
                        filterQuery: _filterQuery,
                        visibleCount: visibleTracks.length,
                        totalCount: detail.tracks.length,
                        hintText: 'Filter mix',
                      ),
                    ),
                  ),
                  if (visibleTracks.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.lg),
                        child: Text(
                          'No songs match your filter.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: visibleTracks.length,
                      itemBuilder: (context, index) => InstantMixTrackTile(
                        seedItemId: seedItemId,
                        tracks: visibleTracks,
                        index: index,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}







List<Track> _visibleMixTracks(List<Track> tracks, String query) {
  if (query.isEmpty) return tracks;
  return tracks
      .where(
        (track) => searchMatches(query, [
          track.name,
          track.artistName,
          track.albumName,
        ]),
      )
      .toList();
}





