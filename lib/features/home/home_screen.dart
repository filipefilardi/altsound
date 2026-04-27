import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
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
              sliver: SliverToBoxAdapter(
                child: _Greeting(username: username),
              ),
            ),
            const SliverFillRemaining(
              child: OfflineLibraryView(),
            ),
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
              sliver: SliverToBoxAdapter(
                child: _Greeting(username: username),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              sliver: SliverToBoxAdapter(
                child: _ResumeCard(
                  recents: ref.watch(recentlyPlayedProvider),
                ),
              ),
            ),
            SliverList.list(children: [
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
            ]),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.username});
  final String username;

  String _timeOfDay() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Late night';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

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
                _timeOfDay(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                username.isEmpty ? 'Welcome back' : username,
                style: Theme.of(context).textTheme.headlineLarge,
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
            backgroundColor: AppColors.surfaceElevated,
            foregroundColor: AppColors.textPrimary,
          ),
          tooltip: 'Settings',
        ),
      ],
    );
  }
}

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.recents});
  final AsyncValue<List<BrowseItem>> recents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = recents.value?.firstOrNull;
    if (item == null) return const SizedBox.shrink();

    final repo = ref.read(jellyfinRepositoryProvider);
    final imageUrl = repo.imageUrl(item.id, imageTag: item.imageTag, size: 300);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/album/${item.id}'),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surfaceElevated,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: AppColors.surface,
                  child: Icon(Icons.album,
                      color: AppColors.textTertiary, size: 32),
                ),
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
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
