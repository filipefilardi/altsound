import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/widgets/app_snackbar.dart';
import 'package:altsound/data/local/connectivity_provider.dart';

enum InstantMixSeedKind {
  album('album'),
  artist('artist'),
  playlist('playlist'),
  track('track');

  const InstantMixSeedKind(this.queryValue);

  final String queryValue;

  static InstantMixSeedKind? fromQuery(String? value) {
    for (final kind in values) {
      if (kind.queryValue == value) return kind;
    }
    return null;
  }
}

/// Stable [MediaItem.extras] `contextId` for a given Instant Mix seed.
/// Used to detect "current playback belongs to this mix" and to label the
/// queue context. Mirrors the `instant-mix:` prefix consumed by
/// [InstantMixExtender].
String instantMixContextId(String seedItemId) => 'instant-mix:$seedItemId';

void openInstantMixPage(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
  required InstantMixSeedKind kind,
  String? title,
}) {
  if (ref.read(isOfflineProvider)) {
    showAppSnackBar(context, 'Instant Mix needs the server.');
    return;
  }

  final uri = Uri(
    path: '/instant-mix/${Uri.encodeComponent(itemId)}',
    queryParameters: {
      'kind': kind.queryValue,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
    },
  );
  context.push(uri.toString());
}
