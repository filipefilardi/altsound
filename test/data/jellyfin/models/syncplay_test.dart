import 'package:flutter_test/flutter_test.dart';
import 'package:altsound/data/jellyfin/models/syncplay.dart';

void main() {
  group('ticks <-> Duration', () {
    test('1ms == 10_000 ticks in both directions', () {
      expect(durationFromJellyfinTicks(10000), const Duration(milliseconds: 1));
      expect(durationToJellyfinTicks(const Duration(milliseconds: 1)), 10000);
    });

    test('null ticks decode to zero', () {
      expect(durationFromJellyfinTicks(null), Duration.zero);
    });

    test('accepts numeric (double) ticks', () {
      expect(
        durationFromJellyfinTicks(15000.0),
        const Duration(microseconds: 1500),
      );
    });
  });

  group('SyncPlayQueueUpdate.fromJson', () {
    test('parses canonical PascalCase payload', () {
      final update = SyncPlayQueueUpdate.fromJson({
        'Reason': 'NewPlaylist',
        'PlayingItemIndex': 2,
        'StartPositionTicks': 50000000, // 5s
        'IsPlaying': true,
        'Playlist': [
          {'ItemId': 'i1', 'PlaylistItemId': 'p1'},
          {'ItemId': '', 'PlaylistItemId': 'p2'}, // empty itemId is dropped
          {'ItemId': 'i3', 'PlaylistItemId': 'p3'},
        ],
      });
      expect(update.reason, 'NewPlaylist');
      expect(update.playingItemIndex, 2);
      expect(update.startPosition, const Duration(seconds: 5));
      expect(update.isPlaying, true);
      expect(update.playlist, hasLength(2));
      expect(update.playlist.first.itemId, 'i1');
      expect(update.playlist.last.itemId, 'i3');
    });

    test('tolerates camelCase keys and missing fields', () {
      final update = SyncPlayQueueUpdate.fromJson({
        'playlist': [
          {'itemId': 'i1', 'playlistItemId': 'p1'},
        ],
      });
      expect(update.reason, isNull);
      expect(update.playingItemIndex, 0);
      expect(update.isPlaying, false);
      expect(update.startPosition, Duration.zero);
      expect(update.playlist.single.itemId, 'i1');
    });
  });

  group('SyncPlayCommand.fromJson', () {
    test('parses position when PositionTicks key is present', () {
      final cmd = SyncPlayCommand.fromJson({
        'Command': 'Seek',
        'PlaylistItemId': 'p1',
        'PositionTicks': 100000000, // 10s
        'When': '2024-06-01T12:00:00Z',
      });
      expect(cmd.command, 'Seek');
      expect(cmd.playlistItemId, 'p1');
      expect(cmd.position, const Duration(seconds: 10));
      expect(cmd.when, DateTime.utc(2024, 6, 1, 12));
    });

    test('leaves position null when PositionTicks key absent', () {
      final cmd = SyncPlayCommand.fromJson({'Command': 'Pause'});
      expect(cmd.position, isNull);
      expect(cmd.when, isNull);
    });
  });
}
