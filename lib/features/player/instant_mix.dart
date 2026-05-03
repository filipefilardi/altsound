import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/local/connectivity_provider.dart';

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

void openInstantMixPage(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
  required InstantMixSeedKind kind,
  String? title,
}) {
  final messenger = ScaffoldMessenger.of(context);
  if (ref.read(isOfflineProvider)) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Instant Mix needs the server.')),
    );
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
