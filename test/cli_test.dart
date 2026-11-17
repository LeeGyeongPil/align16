import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:align16/src/cli.dart';
import 'package:align16/src/report/text_report.dart' show displayWidth;
import 'package:align16/src/sample/sample_project.dart';
import 'package:align16/src/sample/synth_elf.dart';
import 'package:align16/src/sample/zip_writer.dart';
import 'package:test/test.dart';

import 'helpers.dart';

late Directory tmp;

class Run {
  Run(this.code, this.out, this.err);
  final int code;
  final String out;
  final String err;
}

Future<Run> cli(List<String> args, {Map<String, String>? env}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(args,
      env: env ?? {'ALIGN16_LANG': 'en'},
      out: out,
      err: err,
      isTerminal: false);
  return Run(code, out.toString(), err.toString());
}

String apk(String name, List<ZipFileSpec> files) {
  final p = '${tmp.path}/$name';
  writeBytes(p, buildZip(files));
  return p;
}

ZipFileSpec lib(String abi, String name, Uint8List b, {bool stored = true}) =>
    ZipFileSpec('lib/$abi/$name', b,
        stored: stored, alignTo: stored ? 0x4000 : 0);

void main() {
  setUp(() => tmp = makeTemp('cli'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final good = simpleElf(align: 0x10000, seed: 1);
  final bad = simpleElf(align: 0x1000, seed: 2);

  group('exit codes', () {
    test('clean APK -> 0', () async {
      final p = apk('ok.apk', [lib('arm64-v8a', 'libok.so', good)]);
      final r = await cli(['check', p]);
      expect(r.code, 0, reason: r.out + r.err);
      expect(r.out, contains('RESULT: PASS'));
    });

    test('4 KB library -> 1, with the reason in the table', () async {
      final p = apk('bad.apk', [
        lib('arm64-v8a', 'libok.so', good),
        lib('arm64-v8a', 'libbad.so', bad),
      ]);
      final r = await cli(['check', p]);
      expect(r.code, 1);
      expect(r.out, contains('libbad.so'));
      expect(r.out, contains('FAIL'));
      expect(r.out, contains('LOAD align 0x1000 < 0x4000'));
      expect(r.out, contains('--project'));
    });

    test('--allow turns the failure into ALLOWED and exit 0', () async {
      final p = apk('bad.apk', [lib('arm64-v8a', 'libbad.so', bad)]);
      final allow = '${tmp.path}/allow.txt';
      writeText(allow,
          '# known upstream issue\nlibother.so\narm64-v8a/libbad.so  # fix pending\n');
      final r = await cli(['check', p, '--allow', allow]);
      expect(r.code, 0, reason: r.out);
      expect(r.out, contains('ALLOWED'));
      expect(r.out, contains('allowed by --allow'));
    });

    test('allow entry for another ABI does not match', () async {
      final p = apk('bad.apk', [lib('arm64-v8a', 'libbad.so', bad)]);
      final allow = '${tmp.path}/allow.txt';
      writeText(allow, 'x86_64/libbad.so\n');
      expect((await cli(['check', p, '--allow', allow])).code, 1);
    });

    test('missing file -> 2', () async {
      final r = await cli(['check', '${tmp.path}/nope.apk']);
      expect(r.code, 2);
      expect(r.err, contains('Input not found'));
    });

    test('not a ZIP or ELF -> 2', () async {
      writeText('${tmp.path}/notes.txt', 'hello');
      final r = await cli(['check', '${tmp.path}/notes.txt']);
      expect(r.code, 2);
      expect(r.err, contains('Not a ZIP'));
    });

    test('--project without pubspec.yaml -> 2', () async {
      final p = apk('ok.apk', [lib('arm64-v8a', 'libok.so', good)]);
      Directory('${tmp.path}/proj').createSync();
      final r = await cli(['check', p, '--project', '${tmp.path}/proj']);
      expect(r.code, 2);
      expect(r.err, contains('pubspec.yaml'));
    });

    test('usage errors -> 2', () async {
      expect((await cli(['check'])).code, 2);
      expect((await cli(['check', 'a', 'b'])).code, 2);
      expect((await cli(['check', 'a', '--bogus'])).code, 2);
      expect((await cli(['frobnicate'])).code, 2);
      expect((await cli([])).code, 2);
      final r = await cli(['check', 'a', '--abi', 'mips']);
      expect(r.code, 2);
      expect(r.err, contains('Unknown ABI'));
      final missingAllow = await cli(
          ['check', apk('a.apk', []), '--allow', '${tmp.path}/none.txt']);
      expect(missingAllow.code, 2);
    });

    test('--strict makes the congruence warning fail', () async {
      final patched = simpleElf(align: 0x4000, dataVaddrSkew: 0x1000);
      final p = apk('p.apk', [lib('arm64-v8a', 'libp.so', patched)]);
      final lax = await cli(['check', p]);
      expect(lax.code, 0);
      expect(lax.out, contains('WARN'));
      expect((await cli(['check', p, '--strict'])).code, 1);
    });

    test('broken .so in the APK -> ERROR and exit 1', () async {
      final p = apk('e.apk', [lib('arm64-v8a', 'libjunk.so', Uint8List(300))]);
      final r = await cli(['check', p]);
      expect(r.code, 1);
      expect(r.out, contains('ERROR'));
      expect(r.out, contains('not an ELF file'));
    });
  });

  group('inputs', () {
    test('--abi restricts the targets', () async {
      final p = apk('multi.apk', [
        lib('arm64-v8a', 'libbad.so', bad),
        lib('x86_64', 'libgood.so', simpleElf(align: 0x4000, machine: 62)),
      ]);
      expect((await cli(['check', p])).code, 1);
      final x = await cli(['check', p, '--abi', 'x86_64']);
      expect(x.code, 0);
      expect(x.out, isNot(contains('libbad.so')));
      expect(x.out, contains('libgood.so'));
      final both = await cli(['check', p, '--abi', 'x86_64,arm64-v8a']);
      expect(both.code, 1);
    });

    test('32-bit libraries are N/A and never fail', () async {
      final p = apk('v7.apk', [
        lib('armeabi-v7a', 'libold.so',
            simpleElf(align: 0x1000, is64: false, machine: 40)),
      ]);
      final r = await cli(['check', p]);
      expect(r.code, 0);
      expect(r.out, contains('N/A'));
      expect(r.out, contains('1 32-bit skipped'));
    });

    test('AAB: base and feature module, ELF checks + zip-align note', () async {
      final p = apk('app.aab', [
        ZipFileSpec('base/manifest/AndroidManifest.xml',
            Uint8List.fromList(utf('<m/>'))),
        ZipFileSpec('base/lib/arm64-v8a/libbase.so', good, stored: false),
        ZipFileSpec('feature_x/lib/arm64-v8a/libfeat.so', bad, stored: false),
      ]);
      final r = await cli(['check', p, '--json']);
      expect(r.code, 1);
      final j = jsonDecode(r.out) as Map<String, dynamic>;
      expect(j['kind'], 'aab');
      final libs = (j['libraries'] as List).cast<Map<String, dynamic>>();
      expect(libs.map((l) => l['path']), [
        'base/lib/arm64-v8a/libbase.so',
        'feature_x/lib/arm64-v8a/libfeat.so'
      ]);
      expect(libs[1]['module'], 'feature_x');
      expect(libs[1]['status'], 'fail');
      for (final l in libs) {
        final z =
            (l['checks'] as List).firstWhere((c) => c['id'] == 'zip-align');
        expect(z['status'], 'na');
        expect(z['code'], 'aab');
      }
      final text = await cli(['check', p]);
      expect(text.out, contains('feature_x:libfeat.so'));
      expect(text.out, contains('bundletool'));
    });

    test('a single .so file and a folder', () async {
      writeBytes('${tmp.path}/one/libsolo.so', bad);
      final one = await cli(['check', '${tmp.path}/one/libsolo.so']);
      expect(one.code, 1);
      expect(one.out, contains('libsolo.so'));
      writeBytes('${tmp.path}/dir/arm64-v8a/liba.so', good);
      writeBytes('${tmp.path}/dir/other/libb.so',
          simpleElf(align: 0x4000, machine: 62));
      final dir = await cli(['check', '${tmp.path}/dir', '--json']);
      expect(dir.code, 0, reason: dir.out);
      final libs = (jsonDecode(dir.out)['libraries'] as List)
          .cast<Map<String, dynamic>>();
      expect(libs.map((l) => l['abi']).toSet(), {'arm64-v8a', 'x86_64'});
    });

    test('an APK without native libraries says so', () async {
      final r = await cli([
        'check',
        apk('none.apk', [ZipFileSpec('classes.dex', Uint8List(8))])
      ]);
      expect(r.code, 0);
      expect(r.out, contains('No native libraries'));
    });
  });

  group('json', () {
    test('one valid document with the documented fields', () async {
      final s = writeSample('${tmp.path}/s');
      final r = await cli(['check', s.apk, '--project', s.project, '--json']);
      expect(r.code, 1);
      final j = jsonDecode(r.out) as Map<String, dynamic>;
      expect(j['schema'], 1);
      final libs = (j['libraries'] as List).cast<Map<String, dynamic>>();
      expect(libs, isNotEmpty);
      for (final l in libs) {
        expect(
            l.keys,
            containsAll([
              'abi',
              'path',
              'status',
              'checks',
              'min_load_align',
              'owner'
            ]));
      }
      final ctx = libs.firstWhere((l) => l['name'] == 'libclip_engine_ctx.so');
      expect(ctx['status'], 'fail');
      expect(ctx['min_load_align'], 0x1000);
      expect(ctx['owner']['package'], 'clip_engine_ctx');
      expect(ctx['owner']['confidence'], 'name');
      expect(ctx['owner']['path'],
          ['my_app', 'clip_kit', 'clip_native', 'clip_engine_ctx']);
      expect(ctx['owner']['candidates'], isNotEmpty);
      final pkgs = (j['packages'] as List).cast<Map<String, dynamic>>();
      expect(pkgs.map((p) => p['name']), ['clip_engine_ctx', 'fancy_anim']);
      final fancy = pkgs.firstWhere((p) => p['name'] == 'fancy_anim');
      expect(fancy['direct'], isTrue);
      expect(fancy['libraries'],
          ['arm64-v8a/libfancy_anim.so', 'arm64-v8a/libc++_shared.so']);
      expect(j['summary'], {
        'checked': 7,
        'failed': 4,
        'allowed': 0,
        'warnings': 0,
        'known': 0,
        'skipped_32bit': 1,
        'errors': 0,
      });
    });

    test('--lang does not change the JSON', () async {
      final s = writeSample('${tmp.path}/s');
      final en = await cli(
          ['check', s.apk, '--project', s.project, '--json', '--lang', 'en']);
      final ko = await cli(
          ['check', s.apk, '--project', s.project, '--json', '--lang', 'ko']);
      expect(ko.out, en.out);
    });

    test('stdout holds only JSON; errors go to stderr', () async {
      final r = await cli(['check', '${tmp.path}/nope', '--json']);
      expect(r.out, isEmpty);
      expect(r.code, 2);
    });
  });

  group('packaging-only failures (zip offset, bundle config)', () {
    // A fine 16 KB ELF stored at a 4 KB zip offset: only the app build is at fault.
    String misaligned() {
      final p = '${tmp.path}/pk.apk';
      writeBytes(
          p,
          buildZip([
            ZipFileSpec('lib/arm64-v8a/libmedia_box.so', good,
                stored: true, alignTo: 0x1000),
          ]));
      return p;
    }

    String project() => makeProject(tmp, {'media_box': <String>[]},
        rootDeps: ['media_box'], withPlugins: true);

    test('sample: media_box is not blamed, a packaging note is printed',
        () async {
      final s = writeSample('${tmp.path}/s');
      final r = await cli(['check', s.apk, '--project', s.project]);
      final fix = r.out.split('Packages to fix:').last.split('RESULT').first;
      expect(fix, isNot(contains('media_box (')));
      expect(fix, isNot(contains('libmedia_box.so')));
      expect(r.out, contains('Packaging issue in your app build'));
      expect(r.out, contains('AGP 8.5.1'));
      final j = jsonDecode(
          (await cli(['check', s.apk, '--project', s.project, '--json']))
              .out) as Map<String, dynamic>;
      expect(j['packaging_issue'], isTrue);
      expect((j['packages'] as List).map((p) => p['name']),
          isNot(contains('media_box')));
    });

    test('zip-only failure: no packages section, note in EN and KO', () async {
      final apkPath = misaligned();
      final proj = project();
      final en = await cli(['check', apkPath, '--project', proj]);
      expect(en.code, 1);
      expect(en.out, contains('is not 16 KB aligned'));
      expect(en.out, isNot(contains('Packages to fix')));
      expect(en.out, contains('Packaging issue in your app build'));
      // zipalign 은 서명 전에 돌려야 한다(서명된 APK 를 다시 정렬하면 서명이 깨짐).
      expect(en.out, contains('zipalign -P 16 before signing with apksigner'));
      final ko =
          await cli(['check', apkPath, '--project', proj, '--lang', 'ko']);
      expect(ko.out, isNot(contains('고칠 패키지')));
      expect(ko.out, contains('앱 빌드(패키징)의 문제'));
      expect(ko.out, contains('apksigner 로 서명하기 전에 zipalign -P 16'));
      final md = await cli(
          ['check', apkPath, '--project', proj, '--format', 'markdown']);
      expect(md.out, isNot(contains('### Packages to fix')));
      expect(md.out, contains('> Packaging issue'));
    });

    test('a 4 KB BundleConfig gives one app-level note, no package blame',
        () async {
      final p = '${tmp.path}/b.aab';
      writeBytes(
          p,
          buildZip([
            ZipFileSpec('BundleConfig.pb',
                Uint8List.fromList([0x12, 6, 0x12, 4, 0x08, 1, 0x10, 1])),
            ZipFileSpec('base/lib/arm64-v8a/libmedia_box.so', good,
                stored: false),
            ZipFileSpec('base/lib/arm64-v8a/libflutter.so', good,
                stored: false),
          ]));
      final r = await cli(['check', p, '--project', project()]);
      expect(r.code, 1);
      expect('PAGE_ALIGNMENT_4K'.allMatches(r.out).length,
          greaterThanOrEqualTo(1));
      expect(r.out, isNot(contains('Packages to fix')));
      expect('App-level setting'.allMatches(r.out).length, 1);
    });

    test('an ELF failure is still blamed on the package', () async {
      final proj = project();
      writeBytes(
          '${tmp.path}/pkgs/media_box/android/src/main/jniLibs/arm64-v8a/libmedia_box.so',
          bad);
      final p = '${tmp.path}/e.apk';
      writeBytes(
          p,
          buildZip([
            ZipFileSpec('lib/arm64-v8a/libmedia_box.so', bad,
                stored: true, alignTo: 0x4000),
          ]));
      final r = await cli(['check', p, '--project', proj]);
      expect(r.out, contains('Packages to fix'));
      expect(r.out, contains('media_box'));
      expect(r.out, isNot(contains('Packaging issue')));
    });
  });

  group('confidence labels and layout', () {
    test('no raw confidence codes in Korean text or markdown', () async {
      final s = writeSample('${tmp.path}/s');
      final raw = RegExp(r'귀속 근거: (name|exact|ambiguous|none|engine|app)');
      for (final extra in [
        <String>[],
        ['--format', 'markdown']
      ]) {
        final r = await cli(
            ['check', s.apk, '--project', s.project, '--lang', 'ko', ...extra]);
        expect(raw.hasMatch(r.out), isFalse, reason: r.out);
        expect(r.out, contains('귀속 근거: '));
      }
      final en = await cli(['check', s.apk, '--project', s.project]);
      expect(en.out, contains('[match: identical bytes]'));
      expect(en.out, contains('[match: name only]'));
      expect(en.out, isNot(contains('match: name]')));
      // 영어 요약에서 "match" 가 두 번 겹치지 않는다.
      expect(RegExp(r'match: [^\]]*match').hasMatch(en.out), isFalse);
    });

    test('a row and its "Packages to fix" entry use the same words', () async {
      final s = writeSample('${tmp.path}/s');
      for (final lang in ['en', 'ko']) {
        final r =
            await cli(['check', s.apk, '--project', s.project, '--lang', lang]);
        final lines = r.out.split('\n');
        // 표 행: `<- fancy_anim [identical bytes] (...)` 의 괄호 안 낱말
        String rowLabel(String pkg) =>
            RegExp('<- $pkg \\[([^\\]]+)\\]').firstMatch(r.out)!.group(1)!;
        // 목록: `fancy_anim (direct)  [match: identical bytes]` 의 근거 낱말
        String fixLabel(String pkg) {
          final line = lines.firstWhere((l) => l.startsWith('  $pkg ('));
          return RegExp(r'\[[^:\]]+: ([^\]]+)\]').firstMatch(line)!.group(1)!;
        }

        for (final pkg in ['fancy_anim', 'clip_engine_ctx']) {
          expect(rowLabel(pkg), fixLabel(pkg), reason: '$lang $pkg\n${r.out}');
        }
        if (lang == 'en') {
          expect(rowLabel('fancy_anim'), 'identical bytes');
          expect(rowLabel('clip_engine_ctx'), 'name only');
          expect(r.out, isNot(contains('[exact]')));
          expect(r.out, isNot(contains('[name match]')));
        }
      }
    });

    test('Korean table columns line up by display width', () async {
      final s = writeSample('${tmp.path}/s');
      final r = await cli(['check', s.apk, '--lang', 'ko']);
      final lines = r.out.split('\n');
      final head = lines.firstWhere((l) => l.startsWith('ABI'));
      final row = lines
          .firstWhere((l) => l.startsWith('arm64-v8a') && l.contains('FAIL'));
      int col(String l, String marker) =>
          displayWidth(l.substring(0, l.indexOf(marker)));
      expect(col(head, '상태'), col(row, 'FAIL'));
    });

    test('an empty folder is an input error, not a pass', () async {
      Directory('${tmp.path}/empty').createSync();
      final r = await cli(['check', '${tmp.path}/empty']);
      expect(r.code, 2);
      expect(r.err, contains('No native libraries'));
    });
  });

  group('sample', () {
    test('creates files and shows the attributed report', () async {
      final r = await cli(['sample', '--out', '${tmp.path}/sample']);
      expect(r.code, 0, reason: r.err);
      expect(r.out.split('\n').first.toLowerCase(), contains('synthetic'));
      expect(r.out,
          contains('my_app -> clip_kit -> clip_native -> clip_engine_ctx'));
      expect(r.out, contains('fancy_anim (direct)'));
      expect(r.out, contains('libc++_shared.so'));
      expect(r.out, contains('fancy_anim [identical bytes]'));
      expect(r.out, contains('N/A'));
      expect(File('${tmp.path}/sample/app-release.apk').existsSync(), isTrue);
      expect(File('${tmp.path}/sample/app-release.aab').existsSync(), isTrue);
      expect(
          File('${tmp.path}/sample/my_app/pubspec.yaml').existsSync(), isTrue);
    });

    test('writes the allow list of the README example, and it passes',
        () async {
      // README "Known leftovers" 예제를 샘플 폴더에서 그대로 따라 할 수 있어야 한다.
      final r = await cli(['sample', '--out', '${tmp.path}/sample']);
      expect(r.code, 0, reason: r.err);
      final allow = File('${tmp.path}/sample/align16-allow.txt');
      expect(allow.existsSync(), isTrue);
      expect(r.out, contains('Created: ${allow.path}'));
      expect(r.out, contains('--allow ${allow.path}'));
      final body = allow.readAsStringSync();
      for (final e in sampleAllowEntries) {
        expect(body, contains('$e\n'));
      }
      final a = await cli([
        'check', '${tmp.path}/sample/app-release.apk', //
        '--project', '${tmp.path}/sample/my_app', '--allow', allow.path,
      ]);
      expect(a.code, 0, reason: a.out);
      expect(
          a.out,
          contains(
              '7 checked, 0 failed, 4 allowed, 0 warnings, 1 32-bit skipped'));
      expect('ALLOWED  '.allMatches(a.out).length, 4);
      expect(a.out, contains('RESULT: PASS'));
      // 32비트 라이브러리는 허용 목록에 이름이 있어도 N/A 로 남는다.
      expect(a.out, contains('armeabi-v7a  libfancy_anim.so       N/A'));
    });

    test('the Korean allow list has Korean comments and the same entries',
        () async {
      final r =
          await cli(['sample', '--out', '${tmp.path}/sample', '--lang', 'ko']);
      expect(r.code, 0);
      final body =
          File('${tmp.path}/sample/align16-allow.txt').readAsStringSync();
      expect(body, contains('# 연습용 샘플의 align16 허용 목록'));
      for (final e in sampleAllowEntries) {
        expect(body, contains('$e\n'));
      }
      expect(r.out, contains('알려진 잔여 문제 허용하기'));
    });

    test('the Korean sample is Korean and still exits 0', () async {
      final r =
          await cli(['sample', '--out', '${tmp.path}/sample', '--lang', 'ko']);
      expect(r.code, 0);
      expect(r.out.split('\n').first, contains('연습용 합성 샘플'));
      expect(r.out, contains('고칠 패키지'));
    });

    test('the generated AAB is checkable', () async {
      final s = writeSample('${tmp.path}/sample');
      final r = await cli(['check', s.aab, '--project', s.project]);
      expect(r.code, 1);
      expect(r.out, contains('clip_engine_ctx'));
    });

    test('runs fast', () async {
      final sw = Stopwatch()..start();
      await cli(['sample', '--out', '${tmp.path}/sample']);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });

  group('output', () {
    test('color only on a terminal and without NO_COLOR', () async {
      final p = apk('bad.apk', [lib('arm64-v8a', 'libbad.so', bad)]);
      Future<String> run(bool tty, Map<String, String> env,
          [List<String> extra = const []]) async {
        final out = StringBuffer();
        await runCli(['check', p, ...extra],
            env: env, out: out, err: StringBuffer(), isTerminal: tty);
        return out.toString();
      }

      expect(await run(false, {}), isNot(contains('\x1b[')));
      expect(await run(true, {}), contains('\x1b['));
      expect(await run(true, {'NO_COLOR': '1'}), isNot(contains('\x1b[')));
      expect(await run(true, {}, ['--no-color']), isNot(contains('\x1b[')));
    });

    test('Korean table headers and summary', () async {
      final p = apk('bad.apk', [lib('arm64-v8a', 'libbad.so', bad)]);
      final r = await cli(['check', p], env: {'LANG': 'ko_KR.UTF-8'});
      expect(r.out, contains('라이브러리'));
      expect(r.out, contains('검사 1개, 실패 1개'));
      final en =
          await cli(['check', p, '--lang', 'en'], env: {'LANG': 'ko_KR.UTF-8'});
      expect(en.out, contains('Library'));
      expect(en.out, contains('1 checked, 1 failed'));
    });
  });

  test('real engine library from a local Flutter SDK (optional)', () async {
    final root = Platform.environment['ALIGN16_FLUTTER_ROOT'];
    if (root == null || root.isEmpty) {
      markTestSkipped('ALIGN16_FLUTTER_ROOT is not set');
      return;
    }
    final jars = Directory('$root/bin/cache/artifacts/engine')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('flutter.jar') && f.path.contains('android-arm64'))
        .toList();
    if (jars.isEmpty) {
      markTestSkipped('no android-arm64 flutter.jar in the SDK cache');
      return;
    }
    final r = await cli(['check', jars.first.path, '--abi', 'arm64-v8a']);
    expect(r.out, contains('libflutter.so'));
    expect(r.code, 0, reason: r.out);
  });
}
