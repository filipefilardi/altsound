import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';

final albumProvider =
    FutureProvider.autoDispose.family<Album, String>((ref, id) {
  return ref.watch(jellyfinRepositoryProvider).album(id);
});
