import 'package:flutter_test/flutter_test.dart';
import 'package:altsound/features/home/recommendations_cache.dart';

void main() {
  test('todayDateKey returns YYYY-MM-DD with zero-padded month and day', () {
    final key = todayDateKey();
    expect(
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key),
      isTrue,
      reason: 'expected YYYY-MM-DD, got "$key"',
    );

    final now = DateTime.now();
    final expected =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    expect(key, expected);
  });
}
