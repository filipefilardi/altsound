import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';

final artistProvider = FutureProvider.family<Artist, String>((ref, artistId) {
  return ref.read(jellyfinRepositoryProvider).artist(artistId);
});

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({required this.artistId, super.key});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(artistProvider(artistId));
    return Scaffold(
      appBar: AppBar(title: const Text('Artist')),
      body: async.when(
        loading: () => const _ArtistLoading(),
        error: (e, _) => ErrorStateView(
          title: "Couldn't load this artist",
          message: e.toString(),
          onRetry: () => ref.invalidate(artistProvider(artistId)),
        ),
        data: (artist) => _ArtistView(artist: artist),
      ),
    );
  }
}

class _ArtistView extends ConsumerWidget {
  const _ArtistView({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(jellyfinRepositoryProvider);
    final imageUrl = repo.imageUrl(artist.id, imageTag: artist.imageTag, size: 320);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: SizedBox(
                width: 80,
                height: 80,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: AppColors.surfaceElevated),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surfaceElevated,
                    child: const Icon(Icons.person, color: AppColors.textTertiary),
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
                    artist.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${artist.albums.length} albums',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('Discography', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (artist.albums.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No albums found in your Jellyfin library.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          ...artist.albums.map(
            (album) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                album.subtitle ?? 'Album',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              trailing:
                  const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              onTap: () => context.push('/album/${album.id}'),
            ),
          ),
      ],
    );
  }
}

class _ArtistLoading extends StatelessWidget {
  const _ArtistLoading();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Row(
            children: [
              Skeleton.box(width: 80, height: 80, radius: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton.line(width: 180, height: 20),
                    SizedBox(height: 8),
                    Skeleton.line(width: 90, height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Skeleton.line(width: 120, height: 16),
          const SizedBox(height: 12),
          for (int i = 0; i < 8; i++) ...[
            Skeleton.line(height: 14),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
