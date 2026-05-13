import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_theme.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/scrobbler.dart';
import 'package:altsound/data/last_played/last_played_controller.dart';
import 'package:altsound/data/playlists/playlist_backup_repository.dart';
import 'package:altsound/features/auth/auth_controller.dart';
import 'package:altsound/features/player/instant_mix_extender.dart';
import 'package:altsound/features/player/playback_session_persistence.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/syncplay/syncplay_controller.dart';
import 'package:altsound/app/router.dart';

class AltsoundApp extends ConsumerStatefulWidget {
  const AltsoundApp({super.key});

  @override
  ConsumerState<AltsoundApp> createState() => _AltsoundAppState();
}

class _AltsoundAppState extends ConsumerState<AltsoundApp> {
  ProviderSubscription<AuthState>? _authSub;
  PlaybackSessionPersistence? _playbackPersistence;
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
    final persistence = ref.read(playbackSessionPersistenceProvider);
    _playbackPersistence = persistence;
    persistence.attach();
  }

  void _handleAuthChange(AuthState? previous, AuthState next) {
    if (next is AuthAuthenticated) {
      _ensureScrobbler();
      _ensureInstantMixExtender();
      _ensureSearchWarmup(next);
      _ensurePlaylistAutoBackup(next);
      // Eagerly attach the local last-played listener once the session exists.
      ref.read(lastPlayedProvider);
      return;
    }

    _searchWarmSessionKey = null;
    _playlistBackupSessionKey = null;

    if (previous is AuthAuthenticated) {
      unawaited(ref.read(syncPlayControllerProvider.notifier).disconnect());
    }
  }

  @override
  void initState() {
    super.initState();
    _ensurePlaybackPersistence();
    _authSub = ref.listenManual<AuthState>(
      authControllerProvider,
      _handleAuthChange,
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _authSub?.close();
    final persistence = _playbackPersistence;
    if (persistence != null) {
      unawaited(persistence.persistNow());
      unawaited(persistence.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final auth = ref.watch(authControllerProvider);

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
