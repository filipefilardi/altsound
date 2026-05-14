import 'package:flutter_test/flutter_test.dart';
import 'package:altsound/features/player/instant_mix.dart';

void main() {
  group('InstantMixSeedKind.fromQuery', () {
    test('maps every known query value to its kind', () {
      for (final kind in InstantMixSeedKind.values) {
        expect(InstantMixSeedKind.fromQuery(kind.queryValue), kind);
      }
    });

    test('returns null for unknown or empty values', () {
      expect(InstantMixSeedKind.fromQuery(null), isNull);
      expect(InstantMixSeedKind.fromQuery(''), isNull);
      expect(InstantMixSeedKind.fromQuery('podcast'), isNull);
    });
  });

  test('instantMixContextId prefixes the seed id', () {
    expect(instantMixContextId('abc-123'), 'instant-mix:abc-123');
  });
}
