import 'dart:io';

import 'package:align16/src/cli.dart';
import 'package:align16/src/i18n/i18n.dart';
import 'package:align16/src/i18n/messages_en.dart';
import 'package:align16/src/i18n/messages_ko.dart';
import 'package:align16/src/version.dart';
import 'package:test/test.dart';

Future<String> help(List<String> args, Map<String, String> env) async {
  final out = StringBuffer();
  final code = await runCli(args, env: env, out: out, err: StringBuffer());
  expect(code, 0);
  return out.toString();
}

void main() {
  test('both languages have exactly the same keys and no empty text', () {
    expect(messagesKo.keys.toSet(), messagesEn.keys.toSet());
    for (final e in {...messagesEn, ...messagesKo}.entries) {
      expect(e.value.trim(), isNotEmpty, reason: e.key);
    }
  });

  test('table rows and "Packages to fix" use one label per match kind', () {
    // 표의 owner 열과 고칠 패키지 목록이 같은 귀속 근거를 같은 말로 쓰는지(EN·KO).
    for (final table in [messagesEn, messagesKo]) {
      for (final kind in ['exact', 'name', 'ambiguous', 'none', 'engine']) {
        expect(table['owner.$kind'], contains(table['conf.$kind']!),
            reason: '${table['fix.title']} / $kind');
      }
      expect(table['owner.none_maven'], contains(table['conf.none']!));
      expect(table['owner.app'], contains(table['conf.app']!));
    }
  });

  test('placeholders match between languages', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final k in messagesEn.keys) {
      final en = ph.allMatches(messagesEn[k]!).map((m) => m.group(1)).toSet();
      final ko = ph.allMatches(messagesKo[k]!).map((m) => m.group(1)).toSet();
      expect(ko, en, reason: k);
    }
  });

  group('language order', () {
    test('--lang beats everything', () {
      expect(
        resolveLang(flag: 'en', env: {
          'ALIGN16_LANG': 'ko',
          'LC_ALL': 'ko_KR.UTF-8',
          'LANG': 'ko_KR.UTF-8',
        }),
        Lang.en,
      );
      expect(resolveLang(flag: 'ko', env: {'ALIGN16_LANG': 'en'}), Lang.ko);
    });

    test('ALIGN16_LANG > LC_ALL > LC_MESSAGES > LANG', () {
      expect(
          resolveLang(env: {
            'ALIGN16_LANG': 'ko',
            'LC_ALL': 'en_US.UTF-8',
            'LC_MESSAGES': 'en_US.UTF-8',
            'LANG': 'en_US.UTF-8'
          }),
          Lang.ko);
      expect(
          resolveLang(env: {
            'LC_ALL': 'ko_KR.UTF-8',
            'LC_MESSAGES': 'en_US.UTF-8',
            'LANG': 'en_US.UTF-8'
          }),
          Lang.ko);
      expect(
          resolveLang(env: {
            'LC_ALL': 'en_US.UTF-8',
            'LC_MESSAGES': 'ko_KR.UTF-8',
            'LANG': 'ko_KR.UTF-8'
          }),
          Lang.en);
      expect(
          resolveLang(
              env: {'LC_MESSAGES': 'ko_KR.UTF-8', 'LANG': 'en_US.UTF-8'}),
          Lang.ko);
      expect(resolveLang(env: {'LANG': 'ko_KR.UTF-8'}), Lang.ko);
    });

    test('empty values are skipped, anything not ko is English', () {
      expect(resolveLang(env: {'ALIGN16_LANG': '', 'LANG': 'ko_KR.UTF-8'}),
          Lang.ko);
      expect(resolveLang(env: {'LANG': 'fr_FR.UTF-8'}), Lang.en);
      expect(resolveLang(env: {'LANG': 'C'}), Lang.en);
      expect(resolveLang(env: {}), Lang.en);
    });
  });

  group('help text follows the language', () {
    test('English', () async {
      final h = await help(['--help'], {'LANG': 'en_US.UTF-8'});
      expect(h, contains('Usage: align16 <command>'));
      expect(h, contains('Check an APK, AAB'));
    });

    test('Korean via --lang, even when LANG says English', () async {
      final h = await help(['--lang', 'ko', '--help'], {'LANG': 'en_US.UTF-8'});
      expect(h, contains('사용법: align16 <명령>'));
      expect(h, contains('APK, AAB, .so 파일 또는 폴더를 검사합니다.'));
      expect(h, isNot(contains('Check an APK')));
    });

    test('check --help is localized, including option text', () async {
      final ko = await help(['check', '--help', '--lang=ko'], {});
      expect(ko, contains('--project'));
      expect(ko, contains('Flutter 앱 폴더'));
      final en = await help(['check', '--help'], {'ALIGN16_LANG': 'en'});
      expect(en, contains('Flutter app folder'));
    });

    test('ALIGN16_LANG picks Korean for the version-less top help', () async {
      final h = await help(['--help'], {'ALIGN16_LANG': 'ko'});
      expect(h, contains('명령:'));
    });
  });

  test('--version prints the pubspec version', () async {
    expect(await help(['--version'], {}), 'align16 $packageVersion\n');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
        RegExp(r'^version: (\S+)', multiLine: true)
            .firstMatch(pubspec)!
            .group(1),
        packageVersion);
  });

  test('unsupported --lang value is a usage error', () async {
    final err = StringBuffer();
    final code = await runCli(['--lang', 'fr', 'check', 'x'],
        env: {}, out: StringBuffer(), err: err);
    expect(code, 2);
    expect(err.toString(), contains('fr'));
  });
}
