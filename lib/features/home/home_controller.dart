import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';

final recentlyAddedProvider = FutureProvider.autoDispose<List<BrowseItem>>(
  (ref) => ref.watch(jellyfinRepositoryProvider).recentlyAddedAlbums(),
);

final recentlyPlayedProvider = FutureProvider.autoDispose<List<BrowseItem>>(
  (ref) => ref.watch(jellyfinRepositoryProvider).recentlyPlayedAlbums(),
);

final mostPlayedProvider = FutureProvider.autoDispose<List<BrowseItem>>(
  (ref) => ref.watch(jellyfinRepositoryProvider).mostPlayedAlbums(),
);
