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
        data: (albums) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              'Lidarr discography',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              albums.isEmpty
                  ? 'No albums found from Lidarr for this artist.'
                  : '${albums.length} albums found',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            ...albums.map(
              (album) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (album.albumType != null && album.albumType!.isNotEmpty)
                      album.albumType!,
                    if (album.releaseDate != null && album.releaseDate!.isNotEmpty)
                      album.releaseDate!.split('T').first,
                  ].join(' • '),
                  style:
                      const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
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
          Skeleton.line(width: 170, height: 18),
          const SizedBox(height: 8),
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
