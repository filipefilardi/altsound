import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app/app.dart';
import 'data/jellyfin/auth_repository.dart';
import 'data/jellyfin/client_metadata.dart';
import 'data/jellyfin/jellyfin_api.dart';
import 'features/player/audio_player_handler.dart';
import 'features/player/playback_session_persistence.dart';
import 'features/player/player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Audio handler is created before ProviderScope, so we read the gapless
  // preference directly from secure storage to apply it at construction time.
  // Toggling gapless from settings persists immediately but only takes effect
  // on the next launch.
  final gapless = await _readGaplessPreference();
  final metadata = await loadClientMetadata();
  final api = JellyfinApi(
    deviceName: metadata.deviceName,
    appVersion: metadata.appVersion,
  );

  final handler = await AudioService.init(
    builder: () => JellymusicAudioHandler(gaplessPlayback: gapless),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.silent_summit.jellymusic.audio',
      androidNotificationChannelName: 'AltSound playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  final snapshot = await readPlaybackSessionSnapshot();
  if (snapshot != null) {
    try {
      await handler
          .restorePersistenceSnapshot(snapshot)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Best effort restore: never block boot on a stale/corrupt session.
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        jellyfinApiProvider.overrideWithValue(api),
      ],
      child: const JellymusicApp(),
    ),
  );
}

Future<bool> _readGaplessPreference() async {
  try {
    const storage = FlutterSecureStorage(
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    final raw = await storage.read(key: 'playback_gapless_v1');
    return raw != 'false';
  } catch (_) {
    return true;
  }
}
