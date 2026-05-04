import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/header_action_buttons.dart';
import '../../core/widgets/local_or_network_image.dart';
import '../../data/last_instant_mix/last_instant_mix_controller.dart';
import '../../data/last_instant_mix/last_instant_mix_record.dart';
import '../../data/last_played/last_played_controller.dart';
import '../../data/last_played/last_played_record.dart';
import '../../data/local/connectivity_provider.dart';
import '../auth/auth_controller.dart';
import '../downloads/offline_library_view.dart';
import '../player/instant_mix.dart';
import 'home_controller.dart';
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
          await Future.wait([
            ref.read(recentlyAddedProvider.future),
            ref.read(recentlyPlayedProvider.future),
            ref.read(mostPlayedProvider.future),
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

/// Personalized "for you" recommendations on Home. Currently surfaces the
/// last opened Instant Mix; designed as a section so future tiles
/// (daily mix, suggested artists, etc.) can sit next to it without
/// restructuring the screen.
class _ForYouSection extends ConsumerWidget {
  const _ForYouSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastMix = ref.watch(lastInstantMixProvider);
    final isOffline = ref.watch(isOfflineProvider);

    final hasContent = lastMix != null && !isOffline;
    if (!hasContent) return const SizedBox.shrink();

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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _LastInstantMixCard(record: lastMix),
        ),
      ],
    );
  }
}

class _LastInstantMixCard extends ConsumerWidget {
  const _LastInstantMixCard({required this.record});

  final LastInstantMixRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openInstantMixPage(
        context,
        ref,
        itemId: record.seedItemId,
        kind: InstantMixSeedKind.fromQuery(record.seedKind) ??
            InstantMixSeedKind.track,
        title: record.seedTitle,
      ),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: LocalOrNetworkImage(
                source: record.artworkUrl,
                placeholderBuilder: (_) => const _InstantMixCardArtFallback(),
                errorBuilder: (_) => const _InstantMixCardArtFallback(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'YOUR LAST INSTANT MIX',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    record.seedTitle?.trim().isNotEmpty == true
                        ? record.seedTitle!.trim()
                        : 'Instant Mix',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    _seedKindLabel(record),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  String _seedKindLabel(LastInstantMixRecord r) => switch (r.seedKind) {
        'album' => 'Mix from album',
        'artist' => 'Mix from artist',
        'playlist' => 'Mix from playlist',
        _ => 'Mix from song',
      };
}

class _InstantMixCardArtFallback extends StatelessWidget {
  const _InstantMixCardArtFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface,
      child: Icon(
        Icons.auto_awesome_rounded,
        color: AppColors.primary,
        size: 32,
      ),
    );
  }
}
