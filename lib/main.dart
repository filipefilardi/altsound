import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:altsound/app/app.dart';
import 'package:altsound/data/jellyfin/auth_repository.dart';
import 'package:altsound/data/jellyfin/client_metadata.dart';
import 'package:altsound/data/jellyfin/jellyfin_api.dart';
import 'package:altsound/features/player/playback_handler.dart';
import 'package:altsound/features/player/playback_session_persistence.dart';
import 'package:altsound/features/player/player_providers.dart';

const _secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);
const _deviceIdKey = 'jellyfin_device_id_v1';
const _gaplessKey = 'playback_gapless_v1';

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
  final deviceId = await _readDeviceId();
  final api = JellyfinApi(
    deviceId: deviceId,
    deviceName: metadata.deviceName,
    appVersion: metadata.appVersion,
  );

  final handler = await AudioService.init(
    builder: () => PlaybackHandler(gaplessPlayback: gapless),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.silent_summit.altsound.audio',
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
      child: const AltsoundApp(),
    ),
  );
}

Future<bool> _readGaplessPreference() async {
  try {
    final raw = await _secureStorage.read(key: _gaplessKey);
    return raw != 'false';
  } catch (_) {
    return true;
  }
}

Future<String> _readDeviceId() async {
  try {
    final existing = await _secureStorage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await _secureStorage.write(key: _deviceIdKey, value: created);
    return created;
  } catch (_) {
    return const Uuid().v4();
  }
}
