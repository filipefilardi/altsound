import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';

/// One row of the Playback Reporting plugin's `GetItems` report. The plugin
/// aggregates per-`itemId` server-side, so each row already represents a
/// single track with a play-frequency rank — we don't count occurrences.
class PlaybackReportingPlay {
  const PlaybackReportingPlay({required this.itemId, required this.rank});
  final String itemId;
  final int rank;
}

final playbackReportingApiProvider = Provider<PlaybackReportingApi>((ref) {
  return PlaybackReportingApi(ref.watch(jellyfinApiProvider));
});

/// Wraps the Jellyfin Playback Reporting plugin's HTTP API.
///
/// Plugin presence is inferred from the per-user endpoint itself (a 404 means
/// the route isn't installed) rather than `GET /Plugins`, which requires
/// admin and would always 403 for regular users.
class PlaybackReportingApi {
  PlaybackReportingApi(this._api);

  final JellyfinApi _api;
  bool? _missingCache;

  /// Audio plays recorded in the last [days] days for the current user.
  ///
  /// Returns `null` if the plugin route isn't installed (404). Returns an
  /// empty list when the plugin is reachable but the response had no usable
  /// rows. Sorted by [PlaybackReportingPlay.rank] descending.
  Future<List<PlaybackReportingPlay>?> recentAudioPlays({int days = 7}) async {
    if (_missingCache == true) return null;
    final session = _api.session;
    if (session == null) return null;
    final path = '/user_usage_stats/${session.userId}/$days/GetItems';
    try {
      // Don't send `EndDate` (some plugin versions choke on the ISO format
      // and 500) or `filter` (older versions split it inside SQL and crash on
      // certain values). The plugin defaults EndDate to "now" and we filter
      // by track type later via `IncludeItemTypes=Audio` in `tracksByIds`.
      final res = await _api.dio.get<dynamic>(path);
      _missingCache = false;
      final raw = res.data;
      // Plugin versions vary: older returns a bare list, newer wraps in
      // `{ "Items": [...] }`. Accept both, plus a few less-common variants.
      List<dynamic> list = const [];
      if (raw is List) {
        list = raw;
      } else if (raw is Map<String, dynamic>) {
        for (final k in const ['Items', 'items', 'data', 'Data']) {
          final v = raw[k];
          if (v is List) {
            list = v;
            break;
          }
        }
      }
      final dictRows =
          list.whereType<Map<String, dynamic>>().toList(growable: false);
      final plays = dictRows
          .map(_parsePlay)
          .whereType<PlaybackReportingPlay>()
          .toList()
        ..sort((a, b) => b.rank.compareTo(a.rank));

      if (kDebugMode) {
        debugPrint(
            '[PlaybackReporting] GET $path → ${dictRows.length} rows, ${plays.length} parsed');
        if (dictRows.isNotEmpty && plays.isEmpty) {
          debugPrint(
              '[PlaybackReporting] sample row keys: ${dictRows.first.keys.toList()}');
          debugPrint(
              '[PlaybackReporting] sample row: ${dictRows.first}');
        }
      }
      return plays;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        if (kDebugMode) {
          debugPrint(
              '[PlaybackReporting] $path 404 — plugin not installed');
        }
        _missingCache = true;
        return null;
      }
      if (kDebugMode) {
        final body = e.response?.data;
        final preview = body == null
            ? '(no body)'
            : body.toString().substring(0, body.toString().length.clamp(0, 500));
        debugPrint(
            '[PlaybackReporting] $path failed: ${e.response?.statusCode} ${e.message}\nbody: $preview');
      }
      // Transient — don't cache, let the next call retry.
      return const [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlaybackReporting] $path threw: $e');
      }
      return const [];
    }
  }

  /// Parse a row defensively. The plugin's response keys vary across versions
  /// (`Id` vs `ItemId`, capitalisation), so match case-insensitively and try
  /// several fields for both the id and the rank.
  PlaybackReportingPlay? _parsePlay(Map<String, dynamic> e) {
    String? id;
    int? playCount;
    int? duration;
    e.forEach((key, value) {
      final k = key.toLowerCase();
      if (id == null && (k == 'id' || k == 'itemid')) {
        final v = value?.toString();
        if (v != null && v.isNotEmpty && v != 'null') id = v;
      } else if (playCount == null && (k == 'playcount' || k == 'plays')) {
        playCount = _toInt(value);
      } else if (duration == null &&
          (k == 'totalplayduration' ||
              k == 'playduration' ||
              k == 'duration')) {
        duration = _toInt(value);
      }
    });
    final actualId = id;
    if (actualId == null) return null;
    final rank = (playCount != null && playCount! > 0)
        ? playCount!
        : (duration != null && duration! > 0 ? duration! : 1);
    return PlaybackReportingPlay(itemId: actualId, rank: rank);
  }

  /// The plugin returns numbers as strings (`Dictionary<string, string>`),
  /// so parse defensively.
  static int? _toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
