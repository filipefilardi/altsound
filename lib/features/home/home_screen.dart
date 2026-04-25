import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'home_controller.dart';
import 'widgets/shelf.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final greeting = state is AuthAuthenticated
        ? 'Hello, ${state.session.username}'
        : 'Hello';

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
            SliverAppBar(
              floating: true,
              title: Text(greeting),
            ),
            SliverList.list(children: [
              Shelf(
                title: 'Recently added',
                items: ref.watch(recentlyAddedProvider),
              ),
              Shelf(
                title: 'Recently played',
                items: ref.watch(recentlyPlayedProvider),
              ),
              Shelf(
                title: 'Most played',
                items: ref.watch(mostPlayedProvider),
              ),
              const SizedBox(height: 96),
            ]),
          ],
        ),
      ),
    );
  }
}
