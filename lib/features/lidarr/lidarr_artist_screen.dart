import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/lidarr/lidarr_repository.dart';
import '../../data/lidarr/models/lidarr_models.dart';

final lidarrArtistAlbumsProvider = FutureProvider.family
    .autoDispose<List<LidarrAlbumResult>, LidarrArtistResult>((ref, artist) {
  final repo = ref.watch(lidarrRepositoryProvider);
  if (repo == null) {
    throw const LidarrException('Lidarr is not connected.');
  }
  return repo.artistAlbums(
    artistName: artist.name,
    foreignArtistId: artist.foreignArtistId,
  );
});

class LidarrArtistScreen extends ConsumerWidget {
  const LidarrArtistScreen({required this.artist, super.key});

  final LidarrArtistResult artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lidarrArtistAlbumsProvider(artist));
    return Scaffold(
      appBar: AppBar(title: Text(artist.name)),
      body: async.when(
        loading: () => const _Loading(),
        error: (e, _) => ErrorStateView(
          title: "Couldn't load discography",
          message: e.toString(),
          onRetry: () => ref.invalidate(lidarrArtistAlbumsProvider(artist)),
        ),
        data: (albums) {
          if (albums.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No albums found for this artist.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${albums.length} releases',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
              ...albums.map(
                (album) => _AlbumRequestTile(artist: artist, album: album),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AlbumRequestTile extends ConsumerStatefulWidget {
  const _AlbumRequestTile({required this.artist, required this.album});

  final LidarrArtistResult artist;
  final LidarrAlbumResult album;

  @override
  ConsumerState<_AlbumRequestTile> createState() => _AlbumRequestTileState();
}

class _AlbumRequestTileState extends ConsumerState<_AlbumRequestTile> {
  bool _busy = false;
  bool _requested = false;

  Future<void> _request() async {
    final repo = ref.read(lidarrRepositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      final defaults = await repo.defaults();
      await repo.addAlbum(widget.artist, widget.album, defaults: defaults);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _requested = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Requested "${widget.album.title}" via Lidarr.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lidarr error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final subtitle = [
      if (album.albumType != null && album.albumType!.isNotEmpty) album.albumType!,
      if (album.releaseDate != null && album.releaseDate!.isNotEmpty)
        album.releaseDate!.split('T').first,
    ].join(' • ');

    Widget? leading;
    if (album.imageUrl != null) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 48,
          height: 48,
          child: CachedNetworkImage(
            imageUrl: album.imageUrl!,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: AppColors.surfaceElevated),
            errorWidget: (_, __, ___) => Container(
              color: AppColors.surfaceElevated,
              child: const Icon(Icons.album, color: AppColors.textTertiary, size: 20),
            ),
          ),
        ),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      leading: leading,
      title: Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          : null,
      trailing: _requested
          ? const Icon(Icons.check, color: AppColors.primary)
          : _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : TextButton(
                  onPressed: _request,
                  child: const Text('REQUEST'),
                ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Skeleton.line(width: 120, height: 12),
          const SizedBox(height: 16),
          for (int i = 0; i < 12; i++) ...[
            Skeleton.line(height: 14),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
