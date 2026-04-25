import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/player/audio_player_handler.dart';
import 'features/player/player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final handler = await AudioService.init(
    builder: JellymusicAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.silent_summit.jellymusic.audio',
      androidNotificationChannelName: 'Jellymusic playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [audioHandlerProvider.overrideWithValue(handler)],
      child: const JellymusicApp(),
    ),
  );
}
