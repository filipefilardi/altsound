import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'last_instant_mix_record.dart';

final lastInstantMixProvider =
    NotifierProvider<LastInstantMixController, LastInstantMixRecord?>(
        LastInstantMixController.new);

/// Persists the most recently opened Instant Mix seed so the Home screen
/// can offer a one-tap "jump back into your mix" entry without re-seeding.
class LastInstantMixController extends Notifier<LastInstantMixRecord?> {
  File? _file;

  @override
  LastInstantMixRecord? build() {
    if (kIsWeb) return null;
    unawaited(_bootstrap());
    return null;
  }

  Future<void> _bootstrap() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/last_instant_mix.json');
      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        if (raw.isNotEmpty) {
          state = LastInstantMixRecord.fromJson(
              jsonDecode(raw) as Map<String, dynamic>);
        }
      }
    } catch (_) {
      // Corrupt or unreadable record — ignore and start fresh.
    }
  }

  Future<void> save({
    required String seedItemId,
    required String seedKind,
    required String? seedTitle,
    required String? artworkUrl,
  }) async {
    final record = LastInstantMixRecord(
      seedItemId: seedItemId,
      seedKind: seedKind,
      seedTitle: seedTitle,
      artworkUrl: artworkUrl,
      updatedAt: DateTime.now(),
    );
    state = record;
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(jsonEncode(record.toJson()));
    } catch (_) {
      // Best-effort persistence — never crash the UI over this.
    }
  }

  /// Wipe the local record. Call on logout.
  Future<void> clear() async {
    state = null;
    final file = _file;
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
