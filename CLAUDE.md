# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get        # Install dependencies
flutter run            # Run on connected device/simulator
flutter analyze        # Lint
```

## Architecture

AltSound is a Flutter music player that streams from a **Jellyfin** server with optional **Lidarr** integration for music discovery.

### Entry point & bootstrapping

`main.dart` initialises `AudioService` (which wraps `JellymusicAudioHandler`) **before** `ProviderScope`, so the audio handler exists outside the Riverpod graph and is injected via `audioHandlerProvider`. `app.dart` attaches the scrobbler once the user authenticates.

### Data layer (`lib/data/`)

- **`jellyfin/`** — All Jellyfin API calls. `JellyfinApi` is the raw Dio client (session token in header); `JellyfinRepository` is the business-logic layer (search, album/artist/track fetch, stream URL building, playlist management). `AuthRepository` handles login and persists the session via `flutter_secure_storage`. `Scrobbler` listens to audio handler streams and posts playback progress to Jellyfin every 10 s.
- **`lidarr/`** — Optional integration; `lidarrRepositoryProvider` returns `null` when Lidarr is not configured. `LidarrRepository` handles artist search and per-album requests (`addAlbum` with `monitor: 'specificAlbum'`). Never request a whole artist discography — always use `addAlbum`.
- **`downloads/`** — `DownloadManager` maintains a download queue and persists a manifest to `documents/downloads/manifest.json`. `PlayerController` checks for a local file path before building a Jellyfin stream URL.
- **`local/secure_storage.dart`** — Thin wrapper around `flutter_secure_storage`; used for Jellyfin credentials, session, and Lidarr config.

### Player (`lib/features/player/`)

`JellymusicAudioHandler` extends `BaseAudioHandler` and owns the `just_audio` player. It syncs queue and playback state back to `audio_service` (for OS media controls / lock screen). `PlayerController` (Riverpod `NotifierProvider`) is the **only** entry point for all playback actions — `playTracks`, `addTrackToQueue`, `togglePlay`, `seek`, etc.

Key stream providers: `currentMediaItemProvider`, `playbackStateProvider`, `queueProvider`, `positionProvider` — all backed by `audio_service` streams.

### State management (Riverpod)

| Pattern | Used for |
|---|---|
| `Provider` | Singletons — `jellyfinRepositoryProvider`, `routerProvider` |
| `NotifierProvider` | Mutable state — `authControllerProvider`, `playerControllerProvider`, `downloadManagerProvider` |
| `FutureProvider.autoDispose.family` | Per-screen async data — `albumProvider(id)`, `artistProvider(id)`, `lidarrArtistAlbumsProvider(artist)` |
| `StreamProvider` | Audio playback state from `audio_service` |

### Routing (`lib/app/router.dart`)

GoRouter with an auth redirect guard (`authControllerProvider`). The bottom nav (Home / Search / Library) uses `StatefulShellRoute.indexedStack`. Modal routes (Now Playing, Discover, Downloads) are pushed on the root navigator. Lidarr artist extra payload is passed via `GoRouteState.extra` as `LidarrArtistResult`.

### UI conventions

- Theme is defined in `AppTheme.dark()` (`lib/core/theme/`). Always use `AppColors` constants — never hardcode colours. Notable tokens: `AppColors.onAccent` (foreground on the accent gradient, e.g. play-pill icon) and `AppColors.like` (heart/favorite red — distinct from `AppColors.error`).
- Typography uses Inter (body) and Fraunces (display/headlines) via `google_fonts`.
- Bottom sheets use `showDragHandle: true`; the theme sets `surfaceElevated` background and 24 px top radius automatically.
- Section headers in lists use `Theme.of(context).textTheme.labelLarge` (11 px, 700 weight, 1.4 letter-spacing, uppercased).
- Skeleton loading uses `Skeleton.group` / `Skeleton.line` from `lib/core/widgets/skeleton.dart`.
- Empty / error states use `EmptyState` and `ErrorStateView` from `lib/core/widgets/`.
- Spacing: **16 px** is the default horizontal padding for cards, list tiles, and inner layouts. **20 px** is used for top-level/tab-root horizontal padding (home, settings, sheet content). **32 px** is reserved for empty-state padding (`EdgeInsets.all(32)`). Avoid mixing 24 px horizontal — it's reserved for section vertical breaks.
- Back buttons use `BackButton(onPressed: () => context.pop())` — never a raw `IconButton(Icons.arrow_back)`. `BackButton` resolves to the iOS chevron on Apple platforms automatically.
- Artwork that may be local (downloaded) or remote uses `LocalOrNetworkImage` from `lib/core/widgets/`.
- Accent play/pause circle uses the shared `PlayPill` widget (`lib/core/widgets/play_pill.dart`).
- Album / artist / playlist download buttons share `CollectionDownloadButton` (`lib/features/downloads/widgets/`); the WiFi-required prompt is `showWifiRequiredDialog(context)` from the same folder.
- Detail screens (album / artist / playlist) wrap their scrollable in a `RefreshIndicator` whose `onRefresh` calls `ref.refresh(provider(id).future)`.

### Search results ordering

Artists → Songs → Albums → Playlists.
