# AltSound

A modern, open-source music client for [Jellyfin](https://jellyfin.org/).

<p align="center">
  <img src="assets/graphics/feature_graphic.png" alt="AltSound" width="720">
</p>

AltSound connects to your Jellyfin server and turns your music library into a focused listening app — streaming, offline downloads, queue management, lyrics, and remote control of other Jellyfin players.

> AltSound is an unofficial, third-party client. It is not affiliated with or endorsed by the Jellyfin project.

## Features

- Stream your Jellyfin music library
- Browse albums, artists, playlists, and liked songs
- Home screen with recently added, most played, and recommendations
- Full-text search across songs, albums, and artists
- Full-screen now playing with queue management and lyrics
- Instant Mix
- Offline downloads with a per-track download manager and cache settings
- Remote control of other Jellyfin player sessions
- SyncPlay for synchronized playback across devices
- Playlist backup and restore

## Tech stack

- [Flutter](https://flutter.dev/) (Dart SDK `^3.8.1`)
- [Riverpod](https://riverpod.dev/) for state management
- [go_router](https://pub.dev/packages/go_router) for navigation
- [just_audio](https://pub.dev/packages/just_audio) + [audio_service](https://pub.dev/packages/audio_service) for playback and background audio
- [Dio](https://pub.dev/packages/dio) for the Jellyfin HTTP API
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) for credentials

## Supported platforms

| Platform | Minimum version |
| -------- | --------------- |
| iOS      | 13.0            |
| Android  | API 24 (Android 7.0) |
| macOS    | 10.15           |

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) with Dart `^3.8.1`
- A running [Jellyfin server](https://jellyfin.org/docs/general/installation/) with a music library
- A device or simulator/emulator for your target platform
- Xcode (for iOS/macOS builds) or Android Studio / Android SDK (for Android builds)

### Run

```bash
git clone https://github.com/filipefilardi/altsound.git
cd altsound
flutter pub get
flutter run
```

On first launch, AltSound asks for:

- **Server URL** — e.g. `https://jellyfin.example.com`
- **Username**
- **Password**

Credentials are stored in the platform's secure storage; only the access token is sent on subsequent requests.

### Build a release

```bash
# iOS
flutter build ipa

# Android
flutter build apk --release
# or
flutter build appbundle --release

# macOS
flutter build macos --release
```

### Useful commands

```bash
flutter analyze        # static analysis
flutter test           # run tests
flutter pub outdated   # check for dependency updates
```

## Contributing

Issues and pull requests are welcome. Please:

1. Open an issue before starting non-trivial work so we can align on the approach.
2. Run `flutter analyze` and `flutter test` before submitting.
3. Keep changes focused — one feature or fix per PR.

All contributors are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

AltSound is released under the [GNU General Public License v3.0](LICENSE). If you distribute a modified version, you must publish your source under the same license.
