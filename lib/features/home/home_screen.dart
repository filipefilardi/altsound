import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/header_action_buttons.dart';
import '../../core/widgets/local_or_network_image.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/last_played/last_played_controller.dart';
import '../../data/last_played/last_played_record.dart';
import '../../data/local/connectivity_provider.dart';
import '../auth/auth_controller.dart';
import '../downloads/offline_library_view.dart';
import '../player/instant_mix.dart';
import '../player/player_providers.dart';
import 'home_controller.dart';
import 'recommendations_provider.dart';
import 'widgets/shelf.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final username = state is AuthAuthenticated ? state.session.username : '';
    final isOffline = ref.watch(isOfflineProvider);

    if (isOffline) {
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(child: _Greeting(username: username)),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
              sliver: SliverToBoxAdapter(child: _ResumeCard()),
            ),
            const SliverFillRemaining(child: OfflineLibraryView()),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(recentlyAddedProvider);
          ref.invalidate(recentlyPlayedProvider);
          ref.invalidate(mostPlayedProvider);
          ref.invalidate(homeRecommendationsProvider);
          await Future.wait([
            ref.read(recentlyAddedProvider.future),
            ref.read(recentlyPlayedProvider.future),
            ref.read(mostPlayedProvider.future),
            ref.read(homeRecommendationsProvider.future),
          ]);
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              sliver: SliverToBoxAdapter(child: _Greeting(username: username)),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
              sliver: SliverToBoxAdapter(child: _ResumeCard()),
            ),
            const SliverToBoxAdapter(child: _ForYouSection()),
            SliverList.list(
              children: [
                const SizedBox(height: 8),
                Shelf(
                  title: 'Recently added',
                  items: ref.watch(recentlyAddedProvider),
                  onSeeAll: () => context.push('/recently-added'),
                ),
                Shelf(
                  title: 'Most played',
                  items: ref.watch(mostPlayedProvider),
                ),
                Shelf(
                  title: 'Recently played',
                  items: ref.watch(recentlyPlayedProvider),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: Theme.of(context).textTheme.headlineMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const HeaderActionButtons(),
      ],
    );
  }
}

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(lastPlayedProvider);
    if (record == null) return const SizedBox.shrink();

    final albumId = record.albumId;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: albumId == null ? null : () => context.push('/album/$albumId'),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: LocalOrNetworkImage(
                      source: record.imageUrl,
                      errorBuilder: (_) => const _ResumeArtFallback(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'PICK UP WHERE YOU LEFT OFF',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          record.trackName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          _resumeSubtitle(record),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  if (albumId != null) const SizedBox(width: 12),
                ],
              ),
            ),
            if (record.durationMs > 0)
              LinearProgressIndicator(
                value: record.progress,
                minHeight: 2,
                backgroundColor: AppColors.surfaceHighlight,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }

  String _resumeSubtitle(LastPlayedRecord r) {
    final parts = <String>[
      if (r.artistName.isNotEmpty) r.artistName,
      if (r.albumName != null && r.albumName!.isNotEmpty) r.albumName!,
    ];
    return parts.join(' · ');
  }
}

class _ResumeArtFallback extends StatelessWidget {
  const _ResumeArtFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface,
      child: Icon(Icons.album_rounded, color: AppColors.textTertiary, size: 32),
    );
  }
}

/// Personalized "for you" recommendations on Home: last Instant Mix,
/// "Because you played" picks (daily-rotated by [homeRecommendationsProvider]),
/// and Forgotten favorites. Hides itself entirely when no tile has data
/// and on offline (none of these are reachable without the server).
class _ForYouSection extends ConsumerWidget {
  const _ForYouSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    final recs = ref.watch(homeRecommendationsProvider).value;

    if (isOffline) return const SizedBox.shrink();

    final repo = ref.read(jellyfinRepositoryProvider);
    final tiles = <Widget>[];

    final becauseAlbum = recs?.becauseAlbum;
    if (becauseAlbum != null) {
      tiles.add(_ForYouCard(
        eyebrow: 'BECAUSE YOU PLAYED',
        title: becauseAlbum.name,
        subtitle: becauseAlbum.subtitle ?? 'Mix from album',
        imageUrl: becauseAlbum.imageTag == null
            ? null
            : repo.imageUrl(becauseAlbum.id, imageTag: becauseAlbum.imageTag),
        fallbackIcon: Icons.album_rounded,
        onTap: () => openInstantMixPage(
          context,
          ref,
          itemId: becauseAlbum.id,
          kind: InstantMixSeedKind.album,
          title: becauseAlbum.name,
        ),
      ));
    }

    final becauseTrack = recs?.becauseTrack;
    if (becauseTrack != null) {
      tiles.add(_ForYouCard(
        eyebrow: 'BECAUSE YOU PLAYED',
        title: becauseTrack.name,
        subtitle: becauseTrack.artistName,
        imageUrl: becauseTrack.imageTag == null
            ? null
            : repo.imageUrl(becauseTrack.imageItemId,
                imageTag: becauseTrack.imageTag),
        fallbackIcon: Icons.music_note_rounded,
        onTap: () => openInstantMixPage(
          context,
          ref,
          itemId: becauseTrack.id,
          kind: InstantMixSeedKind.track,
          title: becauseTrack.name,
        ),
      ));
    }

    final becauseArtist = recs?.becauseArtist;
    if (becauseArtist != null) {
      tiles.add(_ForYouCard(
        eyebrow: 'INSPIRED BY',
        title: becauseArtist.name,
        subtitle: 'Mix from artist',
        imageUrl: becauseArtist.imageTag == null
            ? null
            : repo.imageUrl(becauseArtist.id,
                imageTag: becauseArtist.imageTag),
        fallbackIcon: Icons.person_rounded,
        onTap: () => openInstantMixPage(
          context,
          ref,
          itemId: becauseArtist.id,
          kind: InstantMixSeedKind.artist,
          title: becauseArtist.name,
        ),
      ));
    }

    final forgotten = recs?.forgottenFavorites ?? const [];
    if (forgotten.isNotEmpty) {
      final cover = forgotten.firstWhere(
        (t) => t.imageTag != null && t.imageTag!.isNotEmpty,
        orElse: () => forgotten.first,
      );
      tiles.add(_ForYouCard(
        eyebrow: 'FORGOTTEN FAVORITES',
        title: 'Songs you used to love',
        subtitle:
            '${forgotten.length} song${forgotten.length == 1 ? '' : 's'}',
        imageUrl: cover.imageTag == null
            ? null
            : repo.imageUrl(cover.imageItemId, imageTag: cover.imageTag),
        fallbackIcon: Icons.history_rounded,
        onTap: () => ref.read(playerControllerProvider).playTracks(
              forgotten,
              contextId: 'forgotten-favorites',
            ),
      ));
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Text(
            'For you',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        SizedBox(
          height: 248,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => tiles[i],
          ),
        ),
      ],
    );
  }

}

class _ForYouCard extends StatelessWidget {
  const _ForYouCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.fallbackIcon,
    required this.onTap,
  });

  static const double width = 168;

  final String eyebrow;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fallback = _ForYouCardArtFallback(icon: fallbackIcon);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      splashColor: AppColors.primary.withValues(alpha: 0.06),
      highlightColor: AppColors.primary.withValues(alpha: 0.03),
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: imageUrl == null
                        ? fallback
                        : LocalOrNetworkImage(
                            source: imageUrl,
                            placeholderBuilder: (_) => fallback,
                            errorBuilder: (_) => fallback,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForYouCardArtFallback extends StatelessWidget {
  const _ForYouCardArtFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceElevated,
      child: Center(
        child: Icon(icon, color: AppColors.primary, size: 48),
      ),
    );
  }
}
