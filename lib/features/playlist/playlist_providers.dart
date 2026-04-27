import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';

final playlistProvider =
    FutureProvider.autoDispose.family<PlaylistDetail, String>((ref, playlistId) {
  return ref.read(jellyfinRepositoryProvider).playlist(playlistId);
});
