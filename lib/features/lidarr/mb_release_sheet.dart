import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/lidarr/lidarr_repository.dart';
import '../../data/musicbrainz/musicbrainz_repository.dart';

final _releaseTracksProvider =
    FutureProvider.autoDispose.family<List<MusicBrainzTrack>, String>(
  (ref, mbid) => ref.read(musicBrainzRepositoryProvider).releaseGroupTracks(mbid),
);

/// Shows the track listing for a [MusicBrainzReleaseGroup] in a bottom sheet.
/// Pass [isInLidarr] so the request button can be shown or hidden.
class MbReleaseSheet extends ConsumerStatefulWidget {
  const MbReleaseSheet({
    required this.release,
    required this.artist,
    required this.isInLidarr,
    super.key,
  });

  final MusicBrainzReleaseGroup release;
  final MusicBrainzArtist artist;
  final bool isInLidarr;

  @override
  ConsumerState<MbReleaseSheet> createState() => _MbReleaseSheetState();
}

class _MbReleaseSheetState extends ConsumerState<MbReleaseSheet> {
  bool _busy = false;
  bool _requested = false;

  Future<void> _request() async {
    final repo = ref.read(lidarrRepositoryProvider);
    if (repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Configure Lidarr in Settings to request albums.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final lidarrArtists = await repo.searchArtists(widget.artist.name);
      final lidarrArtist =
          lidarrArtists.where((a) => a.foreignArtistId == widget.artist.id).firstOrNull ??
              lidarrArtists.firstOrNull;
      if (lidarrArtist == null) throw Exception('Artist not found in Lidarr catalog');

      final lidarrAlbums = await repo.artistAlbums(
        artistName: widget.artist.name,
        foreignArtistId: lidarrArtist.foreignArtistId,
      );
      final lidarrAlbum =
          lidarrAlbums.where((a) => a.foreignAlbumId == widget.release.id).firstOrNull;
      if (lidarrAlbum == null) throw Exception('Album not found in Lidarr catalog');

      final defaults = await repo.defaults();
      await repo.addAlbum(lidarrArtist, lidarrAlbum, defaults: defaults);

      if (!mounted) return;
      setState(() {
        _busy = false;
        _requested = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Requested "${widget.release.title}" via Lidarr')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final tracksAsync = ref.watch(_releaseTracksProvider(r.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Album header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: CachedNetworkImage(
                      imageUrl: r.coverArtUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: AppColors.surfaceElevated),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surfaceElevated,
                        child: const Icon(Icons.album,
                            color: AppColors.textTertiary, size: 28),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (r.year.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          r.year,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                      if (r.primaryType != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          r.primaryType!,
                          style: const TextStyle(
                              color: AppColors.textTertiary, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _statusWidget(context),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Track listing ─────────────────────────────────────────────
          Expanded(
            child: tracksAsync.when(
              loading: () => Skeleton.group(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: 10,
                  itemBuilder: (_, i) => ListTile(
                    leading: Skeleton.box(width: 24, height: 13),
                    title: Skeleton.line(height: 13),
                    trailing: Skeleton.box(width: 32, height: 11),
                  ),
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Could not load track listing.\n$e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
              data: (tracks) {
                if (tracks.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No track listing available for this release.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }

                // Group by disc if multi-disc.
                final multiDisc =
                    tracks.any((t) => t.discNumber > 1);

                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: tracks.length + (multiDisc ? _discHeaderCount(tracks) : 0),
                  itemBuilder: (_, i) {
                    if (!multiDisc) {
                      return _TrackRow(track: tracks[i]);
                    }
                    return _buildWithDiscHeaders(tracks, i);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusWidget(BuildContext context) {
    if (widget.isInLidarr) {
      return _InLidarrBadge();
    }
    if (_requested) {
      return const Icon(Icons.check_circle_outline, color: AppColors.primary);
    }
    if (_busy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    return TextButton(
      onPressed: _request,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('REQUEST'),
    );
  }

  // Simple multi-disc layout: insert a disc header row before each new disc.
  // We handle this by building a flattened list with interleaved headers.
  int _discHeaderCount(List<MusicBrainzTrack> tracks) {
    final discs = <int>{};
    for (final t in tracks) {
      discs.add(t.discNumber);
    }
    return discs.length;
  }

  Widget _buildWithDiscHeaders(List<MusicBrainzTrack> tracks, int flatIndex) {
    // Build a flat list of [header | track] items lazily.
    final items = <_DiscItem>[];
    int? lastDisc;
    for (final t in tracks) {
      if (t.discNumber != lastDisc) {
        items.add(_DiscItem.header(t.discNumber));
        lastDisc = t.discNumber;
      }
      items.add(_DiscItem.track(t));
    }
    final item = items[flatIndex];
    if (item.isHeader) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(
          'Disc ${item.discNumber}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      );
    }
    return _TrackRow(track: item.track!);
  }
}

class _DiscItem {
  _DiscItem.header(this.discNumber)
      : isHeader = true,
        track = null;
  _DiscItem.track(this.track)
      : isHeader = false,
        discNumber = track!.discNumber;

  final bool isHeader;
  final int discNumber;
  final MusicBrainzTrack? track;
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track});
  final MusicBrainzTrack track;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      minVerticalPadding: 6,
      leading: SizedBox(
        width: 28,
        child: Text(
          track.number,
          textAlign: TextAlign.right,
          style: const TextStyle(
              color: AppColors.textTertiary, fontSize: 13),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      trailing: track.formattedDuration.isNotEmpty
          ? Text(
              track.formattedDuration,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            )
          : null,
    );
  }
}

class _InLidarrBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'IN LIDARR',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
