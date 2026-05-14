import 'package:flutter_test/flutter_test.dart';
import 'package:altsound/core/utils/format.dart';

void main() {
  group('formatDuration', () {
    test('uses m:ss when under an hour', () {
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(
        formatDuration(const Duration(minutes: 3, seconds: 7)),
        '3:07',
      );
      expect(formatDuration(Duration.zero), '0:00');
    });

    test('uses h:mm:ss with zero-padded minutes and seconds at >= 1h', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(formatDuration(const Duration(hours: 2)), '2:00:00');
    });
  });

  group('formatLongDuration', () {
    test('drops the hour segment under an hour', () {
      expect(formatLongDuration(const Duration(minutes: 42)), '42min');
      expect(formatLongDuration(Duration.zero), '0min');
    });

    test('renders hours and minutes when >= 1h', () {
      expect(
        formatLongDuration(const Duration(hours: 1, minutes: 5)),
        '1h 5min',
      );
    });
  });

  group('formatBytes', () {
    test('switches unit at each 1024 boundary', () {
      expect(formatBytes(0), '0B');
      expect(formatBytes(1023), '1023B');
      expect(formatBytes(1024), '1KB');
      expect(formatBytes(1024 * 1024), '1.0MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.00GB');
    });

    test('rounds MB to one decimal and GB to two', () {
      expect(formatBytes((1.3 * 1024 * 1024).round()), '1.3MB');
      expect(formatBytes((8.45 * 1024 * 1024 * 1024).round()), '8.45GB');
    });
  });
}
