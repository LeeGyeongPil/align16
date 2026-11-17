// Language selection and message lookup. All user-facing text lives in
// messages_en.dart and messages_ko.dart (same keys in both).
import 'messages_en.dart';
import 'messages_ko.dart';

/// Supported display languages.
enum Lang { en, ko }

/// Environment variables consulted after `--lang`, in order.
const List<String> langEnvOrder = [
  'ALIGN16_LANG',
  'LC_ALL',
  'LC_MESSAGES',
  'LANG',
];

/// Picks the language: `--lang` > ALIGN16_LANG > LC_ALL > LC_MESSAGES > LANG.
///
/// The first non-empty value decides; anything not starting with `ko` is
/// English.
Lang resolveLang({String? flag, required Map<String, String> env}) {
  final candidates = [flag, for (final k in langEnvOrder) env[k]];
  for (final c in candidates) {
    if (c == null || c.trim().isEmpty) continue;
    return c.trim().toLowerCase().startsWith('ko') ? Lang.ko : Lang.en;
  }
  return Lang.en;
}

/// Looks up messages for one language.
class Messages {
  const Messages(this.lang);

  final Lang lang;

  Map<String, String> get table => lang == Lang.ko ? messagesKo : messagesEn;

  /// Returns the message for [key] with `{name}` placeholders replaced.
  String t(String key, [Map<String, Object?> args = const {}]) {
    var s = table[key] ?? messagesEn[key] ?? key;
    args.forEach((k, v) {
      s = s.replaceAll('{$k}', '$v');
    });
    return s;
  }
}
