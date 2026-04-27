import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../data/jellyfin/scrobbler.dart';
import '../data/last_played/last_played_controller.dart';
import '../features/auth/auth_controller.dart';
import '../features/player/player_providers.dart';
import 'router.dart';

class JellymusicApp extends ConsumerStatefulWidget {
  const JellymusicApp({super.key});

  @override
  ConsumerState<JellymusicApp> createState() => _JellymusicAppState();
}

class _JellymusicAppState extends ConsumerState<JellymusicApp> {
  bool _scrobblerAttached = false;

  void _ensureScrobbler() {
    if (_scrobblerAttached) return;
    _scrobblerAttached = true;
    final scrobbler = ref.read(scrobblerProvider);
    final handler = ref.read(audioHandlerProvider);
    scrobbler.attach(
      mediaItemStream: handler.mediaItem.stream,
      playbackStateStream: handler.playbackState.stream,
      position: () => handler.player.position,
      isOffline: () =>
          handler.mediaItem.value?.extras?['isOffline'] == true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final auth = ref.watch(authControllerProvider);

    if (auth is AuthAuthenticated) {
      _ensureScrobbler();
      // Eagerly attach the local last-played listener.
      ref.read(lastPlayedProvider);
    }

    return MaterialApp.router(
      title: 'AltSound',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: router,
      builder: (context, child) {
        if (auth is AuthInitial) {
          return const _SplashScreen();
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
