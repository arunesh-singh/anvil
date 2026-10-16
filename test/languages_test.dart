import 'package:anvil/core/languages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the picker offers every ML Kit translation language by name', () {
    expect(translateLanguages, hasLength(59));
    expect(translateLanguages['es'], 'Spanish');
    expect(
      translateLanguages.values.toList(),
      [...translateLanguages.values]..sort(),
      reason: 'listed alphabetically by name',
    );
  });

  test('identification spellings fold onto translation codes', () {
    expect(canonicalLanguageCode('fil'), 'tl');
    expect(canonicalLanguageCode('iw'), 'he');
    expect(canonicalLanguageCode(' ES '), 'es');
    expect(isTranslatable('fil'), isTrue);
  });

  test('romanized scripts are named but not translatable', () {
    expect(isTranslatable('hi-Latn'), isFalse);
    expect(languageName('hi-Latn'), 'Hindi (romanized)');
  });

  test('identify-only languages are named; unknown codes echo back', () {
    expect(isTranslatable('am'), isFalse);
    expect(languageName('am'), 'Amharic');
    expect(languageName('xx'), 'xx');
  });
}
