/// Language names for the on-device translation flow: the BCP-47 codes ML Kit
/// translation supports (the picker list and the tool's validation) plus names
/// for the extra codes ML Kit language identification can report, so an
/// "unsupported" error still names the language instead of echoing a code.
/// Plugin-free so tools, UI and tests share one table.
library;

/// Every language ML Kit on-device translation supports, code → English name,
/// alphabetical by name (the picker shows them in this order).
const translateLanguages = <String, String>{
  'af': 'Afrikaans',
  'sq': 'Albanian',
  'ar': 'Arabic',
  'be': 'Belarusian',
  'bn': 'Bengali',
  'bg': 'Bulgarian',
  'ca': 'Catalan',
  'zh': 'Chinese',
  'hr': 'Croatian',
  'cs': 'Czech',
  'da': 'Danish',
  'nl': 'Dutch',
  'en': 'English',
  'eo': 'Esperanto',
  'et': 'Estonian',
  'fi': 'Finnish',
  'fr': 'French',
  'gl': 'Galician',
  'ka': 'Georgian',
  'de': 'German',
  'el': 'Greek',
  'gu': 'Gujarati',
  'ht': 'Haitian Creole',
  'he': 'Hebrew',
  'hi': 'Hindi',
  'hu': 'Hungarian',
  'is': 'Icelandic',
  'id': 'Indonesian',
  'ga': 'Irish',
  'it': 'Italian',
  'ja': 'Japanese',
  'kn': 'Kannada',
  'ko': 'Korean',
  'lv': 'Latvian',
  'lt': 'Lithuanian',
  'mk': 'Macedonian',
  'ms': 'Malay',
  'mt': 'Maltese',
  'mr': 'Marathi',
  'no': 'Norwegian',
  'fa': 'Persian',
  'pl': 'Polish',
  'pt': 'Portuguese',
  'ro': 'Romanian',
  'ru': 'Russian',
  'sk': 'Slovak',
  'sl': 'Slovenian',
  'es': 'Spanish',
  'sw': 'Swahili',
  'sv': 'Swedish',
  'tl': 'Tagalog',
  'ta': 'Tamil',
  'te': 'Telugu',
  'th': 'Thai',
  'tr': 'Turkish',
  'uk': 'Ukrainian',
  'ur': 'Urdu',
  'vi': 'Vietnamese',
  'cy': 'Welsh',
};

/// Languages ML Kit language identification can report that translation
/// cannot handle — names only, for error messages.
const _identifyOnlyLanguages = <String, String>{
  'am': 'Amharic',
  'az': 'Azerbaijani',
  'bs': 'Bosnian',
  'ceb': 'Cebuano',
  'co': 'Corsican',
  'eu': 'Basque',
  'fy': 'Frisian',
  'gd': 'Scottish Gaelic',
  'ha': 'Hausa',
  'haw': 'Hawaiian',
  'hmn': 'Hmong',
  'hy': 'Armenian',
  'ig': 'Igbo',
  'jv': 'Javanese',
  'kk': 'Kazakh',
  'km': 'Khmer',
  'ku': 'Kurdish',
  'ky': 'Kyrgyz',
  'la': 'Latin',
  'lb': 'Luxembourgish',
  'lo': 'Lao',
  'mg': 'Malagasy',
  'mi': 'Maori',
  'ml': 'Malayalam',
  'mn': 'Mongolian',
  'my': 'Burmese',
  'ne': 'Nepali',
  'ny': 'Chichewa',
  'pa': 'Punjabi',
  'ps': 'Pashto',
  'sd': 'Sindhi',
  'si': 'Sinhala',
  'sm': 'Samoan',
  'sn': 'Shona',
  'so': 'Somali',
  'sr': 'Serbian',
  'st': 'Sesotho',
  'su': 'Sundanese',
  'tg': 'Tajik',
  'uz': 'Uzbek',
  'xh': 'Xhosa',
  'yi': 'Yiddish',
  'yo': 'Yoruba',
  'zu': 'Zulu',
};

/// Language identification spells a few languages differently from
/// translation (`fil` vs `tl`, legacy `iw`/`in`/`ji`).
const _aliases = <String, String>{
  'fil': 'tl',
  'iw': 'he',
  'in': 'id',
  'ji': 'yi',
  'nb': 'no',
};

/// Canonical lowercase form of [code]: aliases folded, script subtags kept
/// (`hi-Latn` → `hi-latn`, a romanized script translation cannot read).
String canonicalLanguageCode(String code) {
  final lower = code.trim().toLowerCase();
  final dash = lower.indexOf('-');
  final primary = dash < 0 ? lower : lower.substring(0, dash);
  final rest = dash < 0 ? '' : lower.substring(dash);
  return '${_aliases[primary] ?? primary}$rest';
}

/// Whether ML Kit translation supports [code].
bool isTranslatable(String code) =>
    translateLanguages.containsKey(canonicalLanguageCode(code));

/// Human name for [code] (`es` → Spanish, `hi-Latn` → Hindi (romanized));
/// falls back to the code itself for anything unknown.
String languageName(String code) {
  final canonical = canonicalLanguageCode(code);
  final dash = canonical.indexOf('-');
  final primary = dash < 0 ? canonical : canonical.substring(0, dash);
  final name = translateLanguages[primary] ?? _identifyOnlyLanguages[primary];
  if (name == null) return code;
  return canonical.endsWith('-latn') ? '$name (romanized)' : name;
}
