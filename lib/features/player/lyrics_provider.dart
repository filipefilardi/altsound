import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/lyrics.dart';
import 'package:altsound/data/local/connectivity_provider.dart';

final lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, String>((
  ref,
  trackId,
) async {
  if (ref.watch(isOfflineProvider)) return null;
  return ref.watch(jellyfinRepositoryProvider).lyrics(trackId);
});
