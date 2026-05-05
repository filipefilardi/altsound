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
import '../features/home/home_screen.dart';
import '../features/library/library_collection_screen.dart';
import '../features/library/library_screen.dart';
import '../features/player/instant_mix.dart';
import '../features/player/instant_mix_screen.dart';
import '../features/player/now_playing_screen.dart';
import '../features/playlist/playlist_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/desktop_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNav');
final _homeBranchNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'homeBranchNav',
);
final _searchBranchNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'searchBranchNav',
);
final _libraryBranchNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'libraryBranchNav',
);

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
    navigatorKey: _rootNavigatorKey,
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
      GoRoute(
        path: '/now-playing',
        parentNavigatorKey: _rootNavigatorKey,
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
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __, shell) =>
            DesktopRouteFrame(child: AppShell(navigationShell: shell)),
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeBranchNavigatorKey,
            routes: [
              GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _searchBranchNavigatorKey,
            routes: [
              GoRoute(
                path: '/search',
                builder: (_, __) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _libraryBranchNavigatorKey,
            routes: [
              GoRoute(
                path: '/library',
                builder: (_, __) => const LibraryScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/downloads',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const DesktopRouteFrame(child: DownloadsScreen()),
      ),
      GoRoute(
        path: '/recently-added',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) =>
            const DesktopRouteFrame(child: RecentlyAddedScreen()),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const DesktopRouteFrame(child: SettingsScreen()),
      ),
      GoRoute(
        path: '/library/albums',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const DesktopRouteFrame(
          child: LibraryCollectionScreen(kind: LibraryCollectionKind.albums),
        ),
      ),
      GoRoute(
        path: '/library/artists',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const DesktopRouteFrame(
          child: LibraryCollectionScreen(kind: LibraryCollectionKind.artists),
        ),
      ),
      GoRoute(
        path: '/settings/downloads',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) =>
            const DesktopRouteFrame(child: DownloadsSettingsScreen()),
      ),
      GoRoute(
        path: '/artist/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, st) => DesktopRouteFrame(
          child: ArtistScreen(artistId: st.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/artist/:id/discography',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, st) => DesktopRouteFrame(
          child: ArtistDiscographyScreen(artistId: st.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/album/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, st) => DesktopRouteFrame(
          child: AlbumScreen(albumId: st.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/playlist/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, st) => DesktopRouteFrame(
          child: PlaylistScreen(playlistId: st.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/instant-mix/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, st) => DesktopRouteFrame(
          child: InstantMixScreen(
            seedItemId: st.pathParameters['id']!,
            seedKind: InstantMixSeedKind.fromQuery(
              st.uri.queryParameters['kind'],
            ),
            seedTitle: st.uri.queryParameters['title'],
          ),
        ),
      ),
    ],
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('Route not found: ${state.uri}'))),
  );
});
