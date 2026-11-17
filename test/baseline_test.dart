import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:align16/src/baseline.dart';
import 'package:align16/src/cli.dart';
import 'package:align16/src/artifact.dart';
import 'package:align16/src/sample/synth_elf.dart';
import 'package:align16/src/sample/zip_writer.dart';
import 'package:test/test.dart';

import 'helpers.dart';

late Directory tmp;

Future<({int code, String out, String err})> cli(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(args,
      env: {'ALIGN16_LANG': 'en'}, out: out, err: err, isTerminal: false);
  return (code: code, out: out.toString(), err: err.toString());
}

String apk(String name, Map<String, Uint8List> libs) {
  final p = '${tmp.path}/$name';
  writeBytes(
    p,
    buildZip([
      for (final e in libs.entries)
        ZipFileSpec('lib/arm64-v8a/${e.key}', e.value, alignTo: 0x4000),
    ]),
  );
  return p;
}

void main() {
  setUp(() => tmp = makeTemp('baseline'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final bad = simpleElf(align: 0x1000, seed: 1);
  final good = simpleElf(align: 0x4000, seed: 2);

  Future<String> writeBaseline(String apkPath,
      [List<String> extra = const []]) async {
    final r = await cli(['check', apkPath, '--json', ...extra]);
    final f = '${tmp.path}/align16.json';
    writeText(f, r.out);
    return f;
  }

  test('known failures do not fail the run; new ones do', () async {
    final before = apk('before.apk', {'liba.so': bad, 'libok.so': good});
    final baseline = await writeBaseline(before);

    final same = await cli(['check', before, '--baseline', baseline]);
    expect(same.code, 0, reason: same.out);
    expect(same.out, contains('KNOWN'));
    expect(same.out, contains('known failure from the baseline'));
    expect(same.out, contains('Not counted: 1 known failure(s)'));
    expect(same.out, contains('RESULT: PASS'));

    final after =
        apk('after.apk', {'liba.so': bad, 'libb.so': bad, 'libok.so': good});
    final worse = await cli(['check', after, '--baseline', baseline]);
    expect(worse.code, 1);
    expect(worse.out, contains('libb.so'));
    expect(RegExp(r'libb\.so\s+FAIL').hasMatch(worse.out), isTrue);
    expect(RegExp(r'liba\.so\s+KNOWN').hasMatch(worse.out), isTrue);
  });

  test('fixed libraries are reported', () async {
    final before = apk('before.apk', {'liba.so': bad, 'libb.so': bad});
    final baseline = await writeBaseline(before);
    final after = apk('after.apk', {'liba.so': bad, 'libb.so': good});
    final r = await cli(['check', after, '--baseline', baseline]);
    expect(r.code, 0);
    expect(r.out, contains('Fixed since the baseline: arm64-v8a/libb.so'));
    final j = jsonDecode(
        (await cli(['check', after, '--baseline', baseline, '--json'])).out);
    expect(j['baseline_fixed'], ['arm64-v8a/libb.so']);
    expect(j['summary']['known'], 1);
    expect(j['summary']['failed'], 0);
    expect(
        (j['libraries'] as List)
            .firstWhere((dynamic l) => l['name'] == 'liba.so')['status'],
        'known');
  });

  test('a baseline written by a baseline run keeps the known entries',
      () async {
    final before = apk('before.apk', {'liba.so': bad});
    final first = await writeBaseline(before);
    final second = '${tmp.path}/second.json';
    writeText(second,
        (await cli(['check', before, '--json', '--baseline', first])).out);
    expect(Baseline.load(second).keys, {'arm64-v8a/liba.so'});
  });

  test('--allow still wins and --abi hides unchecked ABIs from "fixed"',
      () async {
    final before = apk('before.apk', {'liba.so': bad});
    final baseline = await writeBaseline(before);
    final allow = '${tmp.path}/allow.txt';
    writeText(allow, 'liba.so\n');
    final r =
        await cli(['check', before, '--baseline', baseline, '--allow', allow]);
    expect(r.out, contains('ALLOWED'));
    final x =
        await cli(['check', before, '--baseline', baseline, '--abi', 'x86_64']);
    expect(x.out, isNot(contains('Fixed since')));
  });

  test('unusable baseline files are input errors', () async {
    final before = apk('before.apk', {'liba.so': bad});
    for (final content in [
      'not json',
      '{"schema": 2, "libraries": []}',
      '[]'
    ]) {
      final f = '${tmp.path}/b.json';
      writeText(f, content);
      final r = await cli(['check', before, '--baseline', f]);
      expect(r.code, 2, reason: content);
      expect(r.err, contains('baseline'));
    }
    final missing =
        await cli(['check', before, '--baseline', '${tmp.path}/none.json']);
    expect(missing.code, 2);
    expect(() => Baseline.load('${tmp.path}/none.json'),
        throwsA(isA<InputError>()));
  });

  test('Korean baseline text', () async {
    final before = apk('before.apk', {'liba.so': bad});
    final baseline = await writeBaseline(before);
    final out = StringBuffer();
    final code = await runCli(
        ['check', before, '--baseline', baseline, '--lang', 'ko'],
        env: {}, out: out, err: StringBuffer(), isTerminal: false);
    expect(code, 0);
    expect(out.toString(), contains('기준선'));
  });
}
