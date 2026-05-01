import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/local_or_network_image.dart';
import '../../data/last_played/last_played_controller.dart';
import '../../data/last_played/last_played_record.dart';
import '../../data/local/connectivity_provider.dart';
import '../auth/auth_controller.dart';
import '../downloads/offline_library_view.dart';
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
        IconButton.filledTonal(
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
          ),
          tooltip: 'Settings',
        ),
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
                  if (albumId != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                      ),
                    ),
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
      child: Icon(Icons.album, color: AppColors.textTertiary, size: 32),
    );
  }
}
