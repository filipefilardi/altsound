import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/layout/adaptive_breakpoints.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/jellyfin/auth_repository.dart';
import 'package:altsound/data/local/connectivity_provider.dart';
import 'package:altsound/features/auth/auth_controller.dart';
import 'package:altsound/features/downloads/offline_library_view.dart';
import 'package:altsound/features/home/home_controller.dart';
import 'package:altsound/features/home/recommendations_cache.dart';
import 'package:altsound/features/home/recommendations_provider.dart';
import 'package:altsound/features/home/widgets/for_you_section.dart';
import 'package:altsound/features/home/widgets/home_greeting.dart';
import 'package:altsound/features/home/widgets/resume_card.dart';
import 'package:altsound/features/home/widgets/shelf.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(body: HomeContent());
  }
}

class HomeContent extends ConsumerWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final username = state is AuthAuthenticated ? state.session.username : '';
    final isOffline = ref.watch(isOfflineProvider);
    final desktop = isDesktopLayout(context);

    if (isOffline) {
      return CustomScrollView(
        slivers: [
          if (!desktop)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: HomeGreeting(username: username),
              ),
            ),
          if (!desktop)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(child: ResumeCard()),
            ),
          const SliverToBoxAdapter(child: ForYouSection()),
          const SliverFillRemaining(child: OfflineLibraryView()),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Bust today's For You cache so the user can force a fresh fetch
        // instead of waiting until tomorrow.
        final session = ref.read(jellyfinApiProvider).session;
        if (session != null) {
          await ref
              .read(recommendationsCacheProvider)
              .clear(session.serverId, session.userId);
        }
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
          if (!desktop)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: HomeGreeting(username: username),
              ),
            ),
          if (!desktop)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(child: ResumeCard()),
            ),
          const SliverToBoxAdapter(child: ForYouSection()),
          SliverList.list(
            children: [
              const SizedBox(height: AppSpacing.sm),
              Shelf(
                title: 'Recently added',
                items: ref.watch(recentlyAddedProvider),
                onSeeAll: () => context.push('/recently-added'),
              ),
              Shelf(
                title: 'Most played this week',
                items: ref.watch(mostPlayedProvider),
              ),
              Shelf(
                title: 'Recently played',
                items: ref.watch(recentlyPlayedProvider),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ],
      ),
    );
  }
}
