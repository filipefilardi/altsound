import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/layout/adaptive_breakpoints.dart';
import 'package:altsound/features/album/album_screen.dart';
import 'package:altsound/features/home/recently_added_screen.dart';
import 'package:altsound/features/artist/artist_discography_screen.dart';
import 'package:altsound/features/artist/artist_screen.dart';
import 'package:altsound/features/auth/auth_controller.dart';
import 'package:altsound/features/auth/login_screen.dart';
import 'package:altsound/features/downloads/downloads_screen.dart';
import 'package:altsound/features/downloads/downloads_settings_screen.dart';
import 'package:altsound/features/home/home_screen.dart';
import 'package:altsound/features/library/library_collection_screen.dart';
import 'package:altsound/features/library/library_screen.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/instant_mix_screen.dart';
import 'package:altsound/features/player/lyrics_screen.dart';
import 'package:altsound/features/player/now_playing_screen.dart';
import 'package:altsound/features/playlist/playlist_screen.dart';
import 'package:altsound/features/search/search_screen.dart';
import 'package:altsound/features/settings/playlist_backup_screen.dart';
import 'package:altsound/features/settings/settings_screen.dart';
import 'package:altsound/features/shell/app_shell.dart';
import 'package:altsound/features/shell/desktop_shell.dart';

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

  Page<void> desktopAwarePage({
    required BuildContext context,
    required GoRouterState state,
    required Widget child,
  }) {
    if (isDesktopLayout(context)) {
      return NoTransitionPage<void>(key: state.pageKey, child: child);
    }
    return MaterialPage<void>(key: state.pageKey, child: child);
  }

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
      GoRoute(
        path: '/lyrics',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, st) => CustomTransitionPage(
          key: st.pageKey,
          fullscreenDialog: true,
          opaque: true,
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(curved);
            final scale = Tween<double>(begin: 0.98, end: 1).animate(curved);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: slide,
                child: ScaleTransition(scale: scale, child: child),
              ),
            );
          },
          child: const LyricsScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state, shell) => desktopAwarePage(
          context: context,
          state: state,
          child: DesktopRouteFrame(child: AppShell(navigationShell: shell)),
        ),
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
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: const DesktopRouteFrame(child: DownloadsScreen()),
        ),
      ),
      GoRoute(
        path: '/recently-added',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: const DesktopRouteFrame(child: RecentlyAddedScreen()),
        ),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: const DesktopRouteFrame(child: SettingsScreen()),
        ),
      ),
      GoRoute(
        path: '/library/albums',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: const DesktopRouteFrame(
            child: LibraryCollectionScreen(kind: LibraryCollectionKind.albums),
          ),
        ),
      ),
      GoRoute(
        path: '/library/artists',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: const DesktopRouteFrame(
            child: LibraryCollectionScreen(kind: LibraryCollectionKind.artists),
          ),
        ),
      ),
      GoRoute(
        path: '/settings/downloads',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: const DesktopRouteFrame(child: DownloadsSettingsScreen()),
        ),
      ),
      GoRoute(
        path: '/settings/playlist-backups',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: const DesktopRouteFrame(child: PlaylistBackupScreen()),
        ),
      ),
      GoRoute(
        path: '/artist/:id',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: DesktopRouteFrame(
            child: ArtistScreen(artistId: state.pathParameters['id']!),
          ),
        ),
      ),
      GoRoute(
        path: '/artist/:id/discography',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: DesktopRouteFrame(
            child: ArtistDiscographyScreen(
              artistId: state.pathParameters['id']!,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/album/:id',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: DesktopRouteFrame(
            child: AlbumScreen(albumId: state.pathParameters['id']!),
          ),
        ),
      ),
      GoRoute(
        path: '/playlist/:id',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: DesktopRouteFrame(
            child: PlaylistScreen(playlistId: state.pathParameters['id']!),
          ),
        ),
      ),
      GoRoute(
        path: '/instant-mix/:id',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => desktopAwarePage(
          context: context,
          state: state,
          child: DesktopRouteFrame(
            child: InstantMixScreen(
              seedItemId: state.pathParameters['id']!,
              seedKind: InstantMixSeedKind.fromQuery(
                state.uri.queryParameters['kind'],
              ),
              seedTitle: state.uri.queryParameters['title'],
            ),
          ),
        ),
      ),
    ],
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('Route not found: ${state.uri}'))),
  );
});
