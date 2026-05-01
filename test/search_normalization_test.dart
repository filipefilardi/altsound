import 'package:flutter_test/flutter_test.dart';
import 'package:jellymusic/core/utils/search_normalization.dart';

void main() {
  group('search normalization', () {
    test('folds accents and symbols into searchable text', () {
      expect(normalizeForSearch('TÁ OK'), 'ta ok');
      expect(normalizeForSearch('Beyoncé – Déjà Vu'), 'beyonce deja vu');
      expect(normalizeForSearch('rock`n~roll'), 'rock n roll');
    });

    test('matches accents, punctuation, and compact variants', () {
      expect(searchMatches('ta ok', ['TÁ OK']), isTrue);
      expect(searchMatches('táok', ['Tá OK']), isTrue);
      expect(searchMatches('beyonce deja vu', ['Beyoncé - Déjà Vu']), isTrue);
      expect(searchMatches('rock roll', ['rock`n~roll']), isTrue);
    });

    test('matches lightweight typos', () {
      expect(searchMatches('beynce', ['Beyoncé']), isTrue);
      expect(searchMatches('monky business', ['Monkey Business']), isTrue);
    });
  });
}
