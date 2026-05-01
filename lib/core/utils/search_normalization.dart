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

  final targetTokens = normalizedTarget.split(' ');
  return queryTokens.every(
    (queryToken) => _tokenMatches(queryToken, targetTokens, normalizedTarget),
  );
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
  final queryTokens = normalizedQuery.split(' ');
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
    final targetTokens = field.split(' ');
    final tokenMatches = queryTokens.where(
      (queryToken) => _tokenMatches(queryToken, targetTokens, field),
    );
    score += tokenMatches.length * weight;
  }
  return score;
}

bool _tokenMatches(
  String queryToken,
  List<String> targetTokens,
  String target,
) {
  if (target.contains(queryToken)) return true;
  if (queryToken.length < 3) return false;

  for (final targetToken in targetTokens) {
    if (targetToken.isEmpty) continue;
    if (targetToken == queryToken ||
        targetToken.startsWith(queryToken) ||
        targetToken.contains(queryToken)) {
      return true;
    }
    if (queryToken.length >= 4 &&
        targetToken.length >= 4 &&
        _levenshteinDistance(queryToken, targetToken) <=
            _maxFuzzyDistance(queryToken.length)) {
      return true;
    }
  }
  return false;
}

int _maxFuzzyDistance(int length) => length >= 8 ? 2 : 1;

int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final insertion = current[j] + 1;
      final deletion = previous[j + 1] + 1;
      final substitution =
          previous[j] + (a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1);
      current[j + 1] = insertion < deletion
          ? (insertion < substitution ? insertion : substitution)
          : (deletion < substitution ? deletion : substitution);
    }
    previous = current;
  }
  return previous[b.length];
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
