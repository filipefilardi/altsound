import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../data/jellyfin/jellyfin_repository.dart';
import '../data/jellyfin/scrobbler.dart';
import '../data/last_played/last_played_controller.dart';
import '../data/playlists/playlist_backup_repository.dart';
import '../features/auth/auth_controller.dart';
import '../features/player/instant_mix_extender.dart';
import '../features/player/playback_session_persistence.dart';
import '../features/player/player_providers.dart';
import '../features/syncplay/syncplay_controller.dart';
import 'router.dart';

class JellymusicApp extends ConsumerStatefulWidget {
  const JellymusicApp({super.key});

  @override
  ConsumerState<JellymusicApp> createState() => _JellymusicAppState();
}

class _JellymusicAppState extends ConsumerState<JellymusicApp> {
  bool _scrobblerAttached = false;
  bool _instantMixExtenderAttached = false;
  bool _playbackPersistenceAttached = false;
  String? _searchWarmSessionKey;
  String? _playlistBackupSessionKey;

  void _ensureScrobbler() {
    if (_scrobblerAttached) return;
    _scrobblerAttached = true;
    final scrobbler = ref.read(scrobblerProvider);
    final handler = ref.read(audioHandlerProvider);
    scrobbler.attach(
      mediaItemStream: handler.mediaItem.stream,
      playbackStateStream: handler.playbackState.stream,
      position: () => handler.player.position,
      isOffline: () => handler.mediaItem.value?.extras?['isOffline'] == true,
    );
  }

  void _ensureInstantMixExtender() {
    if (_instantMixExtenderAttached) return;
    _instantMixExtenderAttached = true;
    ref.read(instantMixExtenderProvider).attach();
  }

  void _ensureSearchWarmup(AuthAuthenticated auth) {
    final key = '${auth.session.serverId}_${auth.session.userId}';
    if (_searchWarmSessionKey == key) return;
    _searchWarmSessionKey = key;
    unawaited(ref.read(jellyfinRepositoryProvider).warmSearchCatalog());
  }

  void _ensurePlaylistAutoBackup(AuthAuthenticated auth) {
    final now = DateTime.now();
    final key =
        '${auth.session.serverId}_${auth.session.userId}_${now.year}-${now.month}-${now.day}';
    if (_playlistBackupSessionKey == key) return;
    _playlistBackupSessionKey = key;
    unawaited(
      ref
          .read(playlistBackupRepositoryProvider)
          .maybeCreateAutomaticBackup(session: auth.session),
    );
  }

  void _ensurePlaybackPersistence() {
    if (_playbackPersistenceAttached) return;
    _playbackPersistenceAttached = true;
    ref.read(playbackSessionPersistenceProvider).attach();
  }

  @override
  void dispose() {
    unawaited(ref.read(playbackSessionPersistenceProvider).persistNow());
    unawaited(ref.read(playbackSessionPersistenceProvider).close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final auth = ref.watch(authControllerProvider);
    _ensurePlaybackPersistence();

    if (auth is AuthAuthenticated) {
      _ensureScrobbler();
      _ensureInstantMixExtender();
      _ensureSearchWarmup(auth);
      _ensurePlaylistAutoBackup(auth);
      // Eagerly attach the local last-played listener.
      ref.read(lastPlayedProvider);
    } else {
      unawaited(ref.read(syncPlayControllerProvider.notifier).disconnect());
      _searchWarmSessionKey = null;
      _playlistBackupSessionKey = null;
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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
