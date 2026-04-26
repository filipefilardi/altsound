import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/album/album_screen.dart';
import '../features/home/recently_added_screen.dart';
import '../features/artist/artist_discography_screen.dart';
import '../features/artist/artist_screen.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/downloads/downloads_settings_screen.dart';
import '../features/lidarr/lidarr_artist_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/lidarr/discover_screen.dart';
import '../features/lidarr/lidarr_settings_screen.dart';
import '../features/player/now_playing_screen.dart';
import '../features/playlist/playlist_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../data/lidarr/models/lidarr_models.dart';

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _sub = _ref.listen<AuthState>(
      authControllerProvider,
      (_, __) => notifyListeners(),
      fireImmediately: false,
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: listenable,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      if (auth is AuthInitial) return null;
      final loggedIn = auth is AuthAuthenticated;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn && !atLogin) return '/login';
      if (loggedIn && atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/downloads', builder: (_, __) => const DownloadsScreen()),
      GoRoute(path: '/discover', builder: (_, __) => const DiscoverScreen()),
      GoRoute(
        path: '/discover/artist',
        builder: (_, st) {
          final artist = st.extra;
          if (artist is LidarrArtistResult) {
            return LidarrArtistScreen(artist: artist);
          }
          return const Scaffold(
            body: Center(child: Text('Artist payload missing.')),
          );
        },
      ),
      GoRoute(path: '/recently-added', builder: (_, __) => const RecentlyAddedScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/settings/lidarr',
        builder: (_, __) => const LidarrSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/downloads',
        builder: (_, __) => const DownloadsSettingsScreen(),
      ),
      GoRoute(
        path: '/artist/:id',
        builder: (_, st) => ArtistScreen(artistId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/artist/:id/discography',
        builder: (_, st) =>
            ArtistDiscographyScreen(artistId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/album/:id',
        builder: (_, st) => AlbumScreen(albumId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/playlist/:id',
        builder: (_, st) =>
            PlaylistScreen(playlistId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/now-playing',
        pageBuilder: (_, st) => CustomTransitionPage(
          key: st.pageKey,
          fullscreenDialog: true,
          opaque: true,
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
                reverseCurve: Curves.easeIn,
              ),
              child: child,
            );
          },
          child: const NowPlayingScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (_, __) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (_, __) => const LibraryScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('Route not found: ${state.uri}'))),
  );
});
