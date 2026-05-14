import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/jellyfin/auth_repository.dart';
import 'package:altsound/data/jellyfin/jellyfin_api.dart';

/// One ranked track built from Playback Reporting `GetItems` rows.
class PlaybackReportingPlay {
  const PlaybackReportingPlay({required this.itemId, required this.rank});
  final String itemId;
  final int rank;
}

/// One aggregate row from Playback Reporting breakdown reports.
class PlaybackReportingBreakdown {
  const PlaybackReportingBreakdown({
    required this.label,
    required this.count,
    required this.timeSeconds,
  });
  final String label;
  final int count;
  final int timeSeconds;
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
  bool _loggedEmptyOnce = false;
  static const int _maxRangeDays = 31;

  /// Audio plays recorded in the last [days] days for the current user.
  ///
  /// Returns `null` if the plugin route isn't installed (404). Returns an
  /// empty list when the plugin is reachable but the response had no usable
  /// rows. Sorted by [PlaybackReportingPlay.rank] descending.
  Future<List<PlaybackReportingPlay>?> recentAudioPlays({int days = 7}) async {
    if (_missingCache == true) return null;
    final session = _api.session;
    if (session == null) return null;
    final safeDays = days < 1 ? 1 : days;
    if (safeDays > _maxRangeDays) {
      // This endpoint is single-day; avoid blasting hundreds of requests.
      if (kDebugMode) {
        debugPrint(
          '[PlaybackReporting] requested $safeDays days; plugin path supports single-day only, skipping and using fallback',
        );
      }
      return const [];
    }

    final rankByItemId = <String, int>{};
    var totalRows = 0;
    var totalParsed = 0;

    for (var dayOffset = 0; dayOffset < safeDays; dayOffset++) {
      final date = _dateParamForDayOffset(dayOffset);
      final path = '/user_usage_stats/${session.userId}/$date/GetItems';
      try {
        // GetItems requires a type filter in plugin SQL (`ItemType IN (...)`).
        final res = await _api.dio.get<dynamic>(
          path,
          queryParameters: const {'filter': 'Audio'},
        );
        _missingCache = false;
        final raw = res.data;
        final dictRows = _extractRows(raw);
        final parsedRows = dictRows
            .map(_parsePlay)
            .whereType<PlaybackReportingPlay>()
            .toList(growable: false);
        totalRows += dictRows.length;
        totalParsed += parsedRows.length;

        for (final row in parsedRows) {
          rankByItemId.update(
            row.itemId,
            (existing) => existing + row.rank,
            ifAbsent: () => row.rank,
          );
        }

        if (kDebugMode && dayOffset == 0) {
          debugPrint(
            '[PlaybackReporting] GET $path?filter=Audio → ${dictRows.length} rows, ${parsedRows.length} parsed',
          );
          if (dictRows.isNotEmpty && parsedRows.isEmpty) {
            debugPrint(
              '[PlaybackReporting] sample row keys: ${dictRows.first.keys.toList()}',
            );
            debugPrint('[PlaybackReporting] sample row: ${dictRows.first}');
          }
          if (dictRows.isEmpty && !_loggedEmptyOnce) {
            _loggedEmptyOnce = true;
            final rawType = raw.runtimeType;
            if (raw is Map) {
              final keys = raw.keys.map((k) => k.toString()).toList();
              debugPrint(
                '[PlaybackReporting] GET $path empty rows (raw type: $rawType, keys: $keys)',
              );
            } else {
              debugPrint(
                '[PlaybackReporting] GET $path empty rows (raw type: $rawType)',
              );
            }
          }
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          if (kDebugMode) {
            debugPrint('[PlaybackReporting] $path 404 — plugin not installed');
          }
          _missingCache = true;
          return null;
        }
        if (kDebugMode) {
          final body = e.response?.data;
          final preview = body == null
              ? '(no body)'
              : body.toString().substring(
                  0,
                  body.toString().length.clamp(0, 500),
                );
          debugPrint(
            '[PlaybackReporting] $path failed: ${e.response?.statusCode} ${e.message}\nbody: $preview',
          );
        }
        // Transient day failure — keep other days and fall back if empty.
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[PlaybackReporting] $path threw: $e');
        }
      }
    }

    final plays =
        rankByItemId.entries
            .map((e) => PlaybackReportingPlay(itemId: e.key, rank: e.value))
            .toList(growable: false)
          ..sort((a, b) => b.rank.compareTo(a.rank));

    if (kDebugMode && safeDays > 1) {
      debugPrint(
        '[PlaybackReporting] aggregated last $safeDays days → $totalRows rows, $totalParsed parsed, ${plays.length} unique items',
      );
    }
    return plays;
  }

  /// Global (all non-ignored users) item-id activity from the plugin over the
  /// last [days] days, sorted by [PlaybackReportingBreakdown.count] descending.
  ///
  /// Returns `null` only when the plugin route is missing (404).
  Future<List<PlaybackReportingBreakdown>?> globalItemBreakdown({
    int days = 7,
    int limit = 400,
  }) async {
    if (_missingCache == true) return null;
    final safeDays = days < 1 ? 1 : days;
    final path = '/user_usage_stats/ItemId/BreakdownReport';
    try {
      final res = await _api.dio.get<dynamic>(
        path,
        queryParameters: {'days': safeDays},
      );
      _missingCache = false;
      final rows = _extractRows(res.data);
      final parsed =
          rows
              .map(_parseBreakdown)
              .whereType<PlaybackReportingBreakdown>()
              .where((r) => r.label.isNotEmpty)
              .toList(growable: false)
            ..sort((a, b) {
              final byCount = b.count.compareTo(a.count);
              return byCount != 0
                  ? byCount
                  : b.timeSeconds.compareTo(a.timeSeconds);
            });
      if (kDebugMode) {
        debugPrint(
          '[PlaybackReporting] GET $path?days=$safeDays → ${rows.length} rows, ${parsed.length} parsed',
        );
      }
      if (parsed.length <= limit) return parsed;
      return parsed.take(limit).toList(growable: false);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _missingCache = true;
        if (kDebugMode) {
          debugPrint('[PlaybackReporting] $path 404 — plugin not installed');
        }
        return null;
      }
      if (kDebugMode) {
        debugPrint(
          '[PlaybackReporting] $path failed: ${e.response?.statusCode} ${e.message}',
        );
      }
      return const [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlaybackReporting] $path threw: $e');
      }
      return const [];
    }
  }

  /// GetItems expects a UTC date-like route segment in `yyyy-MM-dd`.
  static String _dateParamForDayOffset(int dayOffset) {
    final day = DateTime.now().toUtc().subtract(Duration(days: dayOffset));
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static List<Map<String, dynamic>> _extractRows(dynamic raw) {
    List<dynamic> list = const [];

    if (raw is List) {
      list = raw;
    } else if (raw is Map) {
      dynamic match;
      for (final candidate in const [
        'Items',
        'items',
        'Data',
        'data',
        'Results',
        'results',
        'Rows',
        'rows',
      ]) {
        if (raw.containsKey(candidate)) {
          match = raw[candidate];
          break;
        }
      }
      if (match is List) {
        list = match;
      }
    }

    final rows = <Map<String, dynamic>>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      rows.add({
        for (final mapEntry in entry.entries)
          mapEntry.key.toString(): mapEntry.value,
      });
    }
    return rows;
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

  PlaybackReportingBreakdown? _parseBreakdown(Map<String, dynamic> e) {
    String? label;
    int? count;
    int? timeSeconds;
    e.forEach((key, value) {
      final k = key.toLowerCase();
      if (label == null && (k == 'label' || k == 'id' || k == 'itemid')) {
        final v = value?.toString();
        if (v != null && v.isNotEmpty && v != 'null') label = v;
      } else if (count == null && (k == 'count' || k == 'playcount')) {
        count = _toInt(value);
      } else if (timeSeconds == null &&
          (k == 'time' || k == 'timeseconds' || k == 'seconds')) {
        timeSeconds = _toInt(value);
      }
    });
    final actualLabel = label;
    if (actualLabel == null || actualLabel.isEmpty) return null;
    return PlaybackReportingBreakdown(
      label: actualLabel,
      count: (count ?? 0) < 0 ? 0 : (count ?? 0),
      timeSeconds: (timeSeconds ?? 0) < 0 ? 0 : (timeSeconds ?? 0),
    );
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
