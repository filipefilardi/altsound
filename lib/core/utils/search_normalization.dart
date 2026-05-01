String normalizeForSearch(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();

  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final mapped = _foldedCharacters[char] ?? char;
    for (final mappedRune in mapped.runes) {
      if (_isAsciiLetterOrDigit(mappedRune)) {
        buffer.writeCharCode(mappedRune);
      } else if (_isCombiningMark(mappedRune)) {
        continue;
      } else {
        buffer.write(' ');
      }
    }
  }

  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

bool searchMatches(String query, Iterable<String?> fields) {
  final normalizedQuery = normalizeForSearch(query);
  if (normalizedQuery.isEmpty) return false;

  final normalizedTarget = normalizeForSearch(
    fields.whereType<String>().join(' '),
  );
  if (normalizedTarget.isEmpty) return false;

  final queryTokens = normalizedQuery.split(' ');
  final compactQuery = normalizedQuery.replaceAll(' ', '');
  final compactTarget = normalizedTarget.replaceAll(' ', '');

  if (compactQuery.isNotEmpty && compactTarget.contains(compactQuery)) {
    return true;
  }

  return queryTokens.every(normalizedTarget.contains);
}

int searchRelevance(String query, Iterable<String?> fields) {
  final normalizedQuery = normalizeForSearch(query);
  if (normalizedQuery.isEmpty) return 0;

  final normalizedFields = fields
      .whereType<String>()
      .map(normalizeForSearch)
      .where((field) => field.isNotEmpty)
      .toList();
  if (normalizedFields.isEmpty) return 0;

  final compactQuery = normalizedQuery.replaceAll(' ', '');
  var score = 0;
  for (var i = 0; i < normalizedFields.length; i++) {
    final field = normalizedFields[i];
    final compactField = field.replaceAll(' ', '');
    final weight = normalizedFields.length - i;
    if (field == normalizedQuery || compactField == compactQuery) {
      score += 100 * weight;
    } else if (field.startsWith(normalizedQuery) ||
        compactField.startsWith(compactQuery)) {
      score += 50 * weight;
    } else if (field.contains(normalizedQuery) ||
        compactField.contains(compactQuery)) {
      score += 20 * weight;
    }
  }
  return score;
}

bool _isAsciiLetterOrDigit(int rune) =>
    (rune >= 0x30 && rune <= 0x39) || (rune >= 0x61 && rune <= 0x7a);

bool _isCombiningMark(int rune) => rune >= 0x0300 && rune <= 0x036f;

const _foldedCharacters = <String, String>{
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'æ': 'ae',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ď': 'd',
  'ð': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'į': 'i',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'œ': 'oe',
  'ŕ': 'r',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ß': 'ss',
  'ť': 't',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
};
