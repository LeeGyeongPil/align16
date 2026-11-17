// Paths the user reads: no `./` pieces (sample, explain) and explain's
// `file:` lines relative to the current folder.
import 'dart:convert';
import 'dart:io';

import 'package:align16/src/cli.dart';
import 'package:align16/src/explain.dart';
import 'package:align16/src/i18n/i18n.dart';
import 'package:align16/src/paths.dart';
import 'package:align16/src/report/explain_report.dart';
import 'package:align16/src/sample/sample_project.dart';
import 'package:test/test.dart';

import 'helpers.dart';

late Directory tmp;

void main() {
  setUp(() => tmp = makeTemp('paths'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final sep = Platform.pathSeparator;

  group('normalizedAbsolute / displayPath', () {
    test('removes . and .. segments and the trailing separator', () {
      final base = normalizedAbsolute(tmp.path);
      expect(normalizedAbsolute('${tmp.path}/./a/../b/'), '$base${sep}b');
      expect(normalizedAbsolute('${tmp.path}/.'), base);
      expect(base, isNot(contains('$sep.$sep')));
    });

    test('relative inside the folder, absolute outside', () {
      final inside = '${tmp.path}/s/my_app/build/x.so';
      expect(displayPath(inside, from: '${tmp.path}/s'),
          'my_app${sep}build${sep}x.so');
      expect(displayPath('${tmp.path}/./s', from: '${tmp.path}/s'), '.');
      final other = '${tmp.path}/other/x.so';
      expect(
          displayPath(other, from: '${tmp.path}/s'), normalizedAbsolute(other));
      // 이름이 접두로만 겹치는 형제 폴더는 "안" 이 아니다.
      expect(displayPath('${tmp.path}/s2/x.so', from: '${tmp.path}/s'),
          normalizedAbsolute('${tmp.path}/s2/x.so'));
    });
  });

  group('sample paths', () {
    test('writeSample keeps no ./ in the paths it returns', () {
      final s = writeSample('${tmp.path}/./out/');
      for (final p in [s.dir, s.apk, s.aab, s.project, s.allow]) {
        expect(p, isNot(contains('$sep.$sep')), reason: p);
        expect(p, isNot(contains('$sep$sep')), reason: p);
      }
      expect(
          s.apk,
          '${normalizedAbsolute('${tmp.path}/out')}${sep}'
          'app-release.apk');
      expect(File(s.apk).existsSync(), isTrue);
    });

    test('align16 sample --out ./x prints clean paths', () async {
      final out = StringBuffer();
      final code = await runCli(['sample', '--out', '${tmp.path}/./x'],
          env: {'ALIGN16_LANG': 'en'},
          out: out,
          err: StringBuffer(),
          isTerminal: false);
      expect(code, 0);
      final created = out
          .toString()
          .split('\n')
          .where((l) =>
              l.startsWith('Created: ') ||
              l.startsWith('Running: ') ||
              l.startsWith('Input: ') ||
              l.startsWith('Project: '))
          .toList();
      expect(created.length, greaterThanOrEqualTo(7));
      for (final l in created) {
        expect(l, isNot(contains('$sep.$sep')), reason: l);
      }
    });
  });

  group('explain file paths', () {
    test('text output is relative to the current folder', () {
      final s = writeSample('${tmp.path}/s');
      final r = explainLibrary('libc++_shared.so', s.project);
      const m = Messages(Lang.en);
      final text = renderExplainText(r, m, cwd: s.dir);
      expect(
          text,
          contains('file: my_app${sep}build${sep}fancy_anim$sep'
              'intermediates'));
      // `Project:` 줄은 입력 그대로라 file: 줄만 본다.
      final fileLines = text.split('\n').where((l) => l.contains('file: '));
      expect(fileLines.length, 2);
      for (final l in fileLines) {
        expect(l, isNot(contains(s.dir)), reason: l);
      }
      // 현재 폴더 밖이면 절대경로 그대로.
      final outside = renderExplainText(r, m, cwd: '${tmp.path}/elsewhere');
      expect(outside, contains('file: ${s.dir}${sep}my_app'));
    });

    test('--project with ./ gives clean candidate files (text and JSON)',
        () async {
      final s = writeSample('${tmp.path}/s');
      final out = StringBuffer();
      final code = await runCli([
        'explain',
        'libc++_shared.so',
        '--project',
        '${tmp.path}/./s/my_app'
      ], env: {
        'ALIGN16_LANG': 'en'
      }, out: out, err: StringBuffer(), isTerminal: false);
      expect(code, 0);
      // `Project:` 줄은 입력한 그대로, 후보 `file:` 줄만 정리된 경로.
      final fileLines =
          out.toString().split('\n').where((l) => l.contains('file: '));
      expect(fileLines.length, 2);
      for (final l in fileLines) {
        expect(l, isNot(contains('$sep.$sep')), reason: l);
      }
      final jOut = StringBuffer();
      await runCli([
        'explain', 'libc++_shared.so', '--project', '${tmp.path}/./s/my_app', //
        '--json',
      ], env: {
        'ALIGN16_LANG': 'en'
      }, out: jOut, err: StringBuffer(), isTerminal: false);
      final j = jsonDecode(jOut.toString()) as Map<String, dynamic>;
      for (final c in j['candidates'] as List) {
        final file = c['file'] as String;
        expect(file, isNot(contains('$sep.$sep')));
        expect(file, startsWith(s.dir));
      }
    });
  });
}
