// M2 regression tests: --format markdown, `explain`, --gradle-cache with
// Maven hints, and the AAB BundleConfig.pb PAGE_ALIGNMENT reader.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:align16/src/bundle_config.dart';
import 'package:align16/src/cli.dart';
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

Future<Run> cli(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(args,
      env: {'ALIGN16_LANG': 'en'}, out: out, err: err, isTerminal: false);
  return Run(code, out.toString(), err.toString());
}

Map<String, dynamic> json(Run r) => jsonDecode(r.out) as Map<String, dynamic>;

// ---- protobuf bytes for BundleConfig.pb (bundletool config.proto) ----

List<int> varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

/// Field [number] with wire type 2 (length-delimited) holding [payload].
List<int> lenField(int number, List<int> payload) =>
    [...varint(number << 3 | 2), ...varint(payload.length), ...payload];

/// Field [number] with wire type 0 (varint).
List<int> varField(int number, int value) =>
    [...varint(number << 3), ...varint(value)];

/// BundleConfig { bundletool{version} optimizations{ uncompress_native_libraries
/// { enabled, alignment } } }. [alignment]: 0 unspecified, 1 4K, 2 16K, 3 64K.
Uint8List bundleConfig({required bool enabled, required int alignment}) {
  final uncompress = [
    ...varField(1, enabled ? 1 : 0),
    ...varField(2, alignment),
  ];
  return Uint8List.fromList([
    // field 1: Bundletool { version = "1.17.2" } (must be skipped)
    ...lenField(1, lenField(1, utf8.encode('1.17.2'))),
    // field 2: Optimizations, with an unrelated fixed64 field 9 first
    ...lenField(2, [
      ...varint(9 << 3 | 1),
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      ...lenField(2, uncompress),
    ]),
  ]);
}

void main() {
  setUp(() => tmp = makeTemp('m2'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final good = simpleElf(align: 0x10000, seed: 11);
  final bad = simpleElf(align: 0x1000, seed: 12);

  group('markdown', () {
    test('sample: table, packages section, result line, exit 1', () async {
      final s = writeSample('${tmp.path}/s');
      final r = await cli(
          ['check', s.apk, '--project', s.project, '--format', 'markdown']);
      expect(r.code, 1);
      expect(r.out, startsWith('## align16 - Android 16 KB page-size check'));
      expect(r.out,
          contains('| ABI | Library | Status | Details | Packages to fix |'));
      expect(r.out, contains('|---|---|---|---|---|'));
      expect(r.out, contains('| arm64-v8a | `libfancy_anim.so` | **FAIL** |'));
      expect(r.out, contains('### Packages to fix'));
      expect(
          r.out,
          contains('- **[fancy_anim](https://pub.dev/packages/fancy_anim)** '
              '(direct, match: identical bytes)'));
      expect(r.out,
          contains('`my_app -> clip_kit -> clip_native -> clip_engine_ctx`'));
      expect(
          r.out.trimRight(),
          endsWith(
              '**RESULT: FAIL - fix the libraries marked FAIL or ERROR.**'));
    });

    test('clean APK without --project: no owner column, PASS, exit 0',
        () async {
      final p = '${tmp.path}/ok.apk';
      writeBytes(
          p,
          buildZip([
            ZipFileSpec('lib/arm64-v8a/libok.so', good, alignTo: 0x4000),
          ]));
      final r = await cli(['check', p, '--format', 'markdown']);
      expect(r.code, 0);
      expect(r.out, contains('| ABI | Library | Status | Details |\n'));
      expect(r.out, isNot(contains('### Packages to fix')));
      expect(r.out, contains('**RESULT: PASS'));
    });

    test('Korean markdown and format errors', () async {
      final s = writeSample('${tmp.path}/s');
      final ko = await cli([
        'check', s.apk, '--project', s.project, //
        '--format', 'markdown', '--lang', 'ko',
      ]);
      expect(ko.out, contains('| ABI | 라이브러리 | 상태 | 상세 | 고칠 패키지 |'));
      expect(ko.out, contains('### 고칠 패키지'));
      final bad = await cli(['check', s.apk, '--format', 'xml']);
      expect(bad.code, 2);
      expect(bad.err, contains('Unknown format "xml"'));
      final both =
          await cli(['check', s.apk, '--format', 'markdown', '--json']);
      expect(both.code, 2);
      expect(both.err, contains('--json cannot be combined'));
    });
  });

  group('explain', () {
    test('found: both packages that ship libc++_shared.so, exit 0', () async {
      final s = writeSample('${tmp.path}/s');
      final r =
          await cli(['explain', 'libc++_shared.so', '--project', s.project]);
      expect(r.code, 0, reason: r.err);
      expect(r.out, contains('Explain: libc++_shared.so'));
      expect(r.out,
          contains('arm64-v8a  fancy_anim (direct)  my_app -> fancy_anim'));
      expect(r.out,
          contains('arm64-v8a  media_box (direct)  my_app -> media_box'));
      expect(r.out, contains('Several packages ship this file name'));
      final j = json(await cli(
          ['explain', 'libc++_shared.so', '--project', s.project, '--json']));
      expect(j['schema'], 1);
      expect((j['candidates'] as List).map((c) => c['package']),
          ['fancy_anim', 'media_box']);
      expect(j['maven_hints'], isEmpty);
    });

    test('transitive path and engine library', () async {
      final s = writeSample('${tmp.path}/s');
      final t = await cli(
          ['explain', 'libclip_engine_ctx.so', '--project', s.project]);
      expect(t.code, 0);
      expect(t.out, contains('clip_engine_ctx (transitive)'));
      expect(t.out,
          contains('my_app -> clip_kit -> clip_native -> clip_engine_ctx'));
      final e = await cli(['explain', 'libflutter.so', '--project', s.project]);
      expect(e.code, 0);
      expect(e.out, contains('Flutter engine library'));
    });

    test('not found: exit 1 with a Gradle cache hint', () async {
      final s = writeSample('${tmp.path}/s');
      final r = await cli(['explain', 'libnope.so', '--project', s.project]);
      expect(r.code, 1);
      expect(r.out, contains('No package in this project ships libnope.so'));
      expect(r.out, contains('try --gradle-cache'));
      // --abi restricts candidates: libc++_shared.so exists only for arm64.
      final x = await cli([
        'explain', 'libc++_shared.so', '--project', s.project, //
        '--abi', 'x86_64',
      ]);
      expect(x.code, 1);
    });

    test('Korean output and usage errors', () async {
      final s = writeSample('${tmp.path}/s');
      final ko = await cli(
          ['explain', 'libnope.so', '--project', s.project, '--lang', 'ko']);
      expect(ko.code, 1);
      expect(ko.out, contains('설명: libnope.so'));
      expect(ko.out, contains('싣고 있지 않습니다'));
      final noProject = await cli(['explain', 'libx.so']);
      expect(noProject.code, 2);
      expect(noProject.err, contains('explain needs --project'));
      final noName = await cli(['explain', '--project', s.project]);
      expect(noName.code, 2);
      expect(noName.err, contains('Missing library name'));
    });

    test('explain accepts --no-color like check and sample (QA r4 Q-2)',
        () async {
      final s = writeSample('${tmp.path}/s');
      final plain =
          await cli(['explain', 'libc++_shared.so', '--project', s.project]);
      final noColor = await cli([
        'explain', 'libc++_shared.so', '--project', s.project, //
        '--no-color',
      ]);
      expect(noColor.code, 0, reason: noColor.err);
      expect(noColor.err, isEmpty);
      // explain never colors, so the flag changes nothing in the text.
      expect(noColor.out, plain.out);
      expect(noColor.out, isNot(contains('\x1b[')));
      final help = await cli(['explain', '--help']);
      expect(help.out, contains('--no-color'));
    });

    test('every command accepts the shared options --lang and --no-color',
        () async {
      final s = writeSample('${tmp.path}/s');
      final shared = ['--lang', 'en', '--no-color'];
      final check = await cli([
        'check', s.apk, '--project', s.project, //
        ...shared
      ]);
      expect(check.code, isNot(2), reason: check.err);
      final explain = await cli([
        'explain', 'libc++_shared.so', '--project', s.project, //
        ...shared,
      ]);
      expect(explain.code, 0, reason: explain.err);
      final sample = await cli([
        'sample', '--out', '${tmp.path}/s2', //
        ...shared
      ]);
      expect(sample.code, 0, reason: sample.err);
    });
  });

  group('gradle cache', () {
    late SampleFiles s;
    late String cache;

    // clip_native 이 Maven 아티팩트 vidcore 를 선언하고, 캐시에는 vidcore 와
    // 아무도 선언하지 않은 other 가 풀려 있다.
    setUp(() {
      s = writeSample('${tmp.path}/s');
      writeText('${s.dir}/pkgs/clip_native/android/build.gradle', '''
dependencies {
    implementation 'com.example.video:vidcore:2.1.0'
}
''');
      writeText('${s.dir}/pkgs/fancy_anim/android/build.gradle.kts', '''
dependencies {
    implementation("com.example.fx:fxcore:1.0.0")
}
''');
      cache = '${tmp.path}/gc';
      writeBytes(
          '$cache/transforms-4/abc/transformed/vidcore-2.1.0/jni/arm64-v8a/libvid.so',
          bad);
      writeBytes(
          '$cache/transforms-4/abd/transformed/other-1.0/jni/arm64-v8a/libother.so',
          bad);
      writeBytes(
          '$cache/transforms-3/abe/transformed/jetified-fxcore-1.0.0/jni/x86_64/libfx.so',
          bad);
      writeBytes(
          '$cache/transforms-4/abf/transformed/vidcore-extra-1.0/jni/arm64-v8a/libextra.so',
          bad);
    });

    String apkWith(String name) {
      final p = '${tmp.path}/$name.apk';
      writeBytes(
          p,
          buildZip([
            ZipFileSpec('lib/arm64-v8a/$name', bad, alignTo: 0x4000),
          ]));
      return p;
    }

    test('check maps an extracted AAR to the plugin that declares it',
        () async {
      final apk = apkWith('libvid.so');
      final r = await cli([
        'check', apk, '--project', s.project, '--gradle-cache', cache, //
      ]);
      expect(r.code, 1);
      expect(
          r.out,
          contains('<- clip_native [identical bytes] '
              '(my_app -> clip_kit -> clip_native)'));
      expect(r.out, contains('clip_native (transitive)'));
      final j = json(await cli([
        'check', apk, '--project', s.project, '--gradle-cache', cache, //
        '--json',
      ]));
      final owner = (j['libraries'] as List).single['owner'] as Map;
      expect(owner['package'], 'clip_native');
      expect(owner['confidence'], 'exact');
      expect((owner['candidates'] as List).single['maven'], 'vidcore-2.1.0');
    });

    test('without --gradle-cache the same library is unattributed', () async {
      final r =
          await cli(['check', apkWith('libvid.so'), '--project', s.project]);
      expect(r.out, contains('<- unattributed'));
      expect(r.out, contains('Add --gradle-cache'));
    });

    test('an artifact no plugin declares becomes a Maven hint', () async {
      final apk = apkWith('libother.so');
      final r = await cli([
        'check', apk, '--project', s.project, '--gradle-cache', cache, //
      ]);
      expect(r.code, 1);
      expect(r.out,
          contains('<- unattributed (possible Maven artifact: other-1.0)'));
      // 이미 --gradle-cache 를 줬으니 다시 권하지 않는다.
      expect(r.out, isNot(contains('Add --gradle-cache')));
      final j = json(await cli([
        'check', apk, '--project', s.project, '--gradle-cache', cache, //
        '--json',
      ]));
      final owner = (j['libraries'] as List).single['owner'] as Map;
      expect(owner['confidence'], 'none');
      expect(owner['maven_hints'], ['other-1.0']);
    });

    test('jetified- prefix and .kts coordinates match; other names do not',
        () async {
      final fx = await cli([
        'explain',
        'libfx.so',
        '--project',
        s.project,
        '--gradle-cache',
        cache,
      ]);
      expect(fx.code, 0);
      expect(fx.out, contains('x86_64  fancy_anim (direct)'));
      expect(fx.out, contains('Gradle cache artifact: jetified-fxcore-1.0.0'));
      // vidcore-extra-1.0 is not vidcore: stays an unmapped hint.
      final extra = await cli([
        'explain', 'libextra.so', '--project', s.project, //
        '--gradle-cache', cache,
      ]);
      expect(extra.code, 1);
      expect(extra.out, contains('Gradle artifact: vidcore-extra-1.0'));
      expect(extra.out, isNot(contains('clip_native')));
    });

    test('explain shows the mapped package and its artifact', () async {
      final r = await cli([
        'explain',
        'libvid.so',
        '--project',
        s.project,
        '--gradle-cache',
        cache,
      ]);
      expect(r.code, 0);
      expect(r.out, contains('arm64-v8a  clip_native (transitive)'));
      expect(r.out, contains('Gradle cache artifact: vidcore-2.1.0'));
      final j = json(await cli([
        'explain', 'libvid.so', '--project', s.project, //
        '--gradle-cache', cache, '--json',
      ]));
      expect((j['candidates'] as List).single['maven'], 'vidcore-2.1.0');
      expect(j['gradle_cache'], cache);
    });

    test('explain shows unmapped artifacts instead of suggesting the option',
        () async {
      final r = await cli([
        'explain', 'libother.so', '--project', s.project, //
        '--gradle-cache', cache,
      ]);
      expect(r.code, 1);
      expect(r.out, contains('No pub package in this project declares'));
      expect(r.out, contains('arm64-v8a  Gradle artifact: other-1.0'));
      expect(r.out, contains('./gradlew :app:dependencies'));
      expect(r.out, isNot(contains('try --gradle-cache')));
      final j = json(await cli([
        'explain', 'libother.so', '--project', s.project, //
        '--gradle-cache', cache, '--json',
      ]));
      expect(j['candidates'], isEmpty);
      expect(j['maven_hints'], [
        {'artifact': 'other-1.0', 'abi': 'arm64-v8a'},
      ]);
      final ko = await cli([
        'explain', 'libother.so', '--project', s.project, //
        '--gradle-cache', cache, '--lang', 'ko',
      ]);
      expect(ko.out, contains('Gradle 아티팩트: other-1.0'));
    });

    test('explain: not in the project nor in the cache', () async {
      final r = await cli([
        'explain', 'libnope.so', '--project', s.project, //
        '--gradle-cache', cache,
      ]);
      expect(r.code, 1);
      expect(r.out, contains('no extracted AAR in the Gradle cache'));
      expect(r.out, isNot(contains('try --gradle-cache')));
    });

    test('a missing cache folder is an input error (exit 2), EN and KO',
        () async {
      final missing = '${tmp.path}/gc-typo';
      final c = await cli([
        'check', apkWith('libvid.so'), '--project', s.project, //
        '--gradle-cache', missing,
      ]);
      expect(c.code, 2);
      expect(c.err, contains('Gradle cache folder not found: $missing'));
      expect(c.out, isEmpty);
      // --project 없이도 오타를 알린다.
      final noProject =
          await cli(['check', apkWith('libvid.so'), '--gradle-cache', missing]);
      expect(noProject.code, 2);
      final e = await cli([
        'explain', 'libvid.so', '--project', s.project, //
        '--gradle-cache', missing, '--lang', 'ko',
      ]);
      expect(e.code, 2);
      expect(e.err, contains('Gradle 캐시 폴더를 찾을 수 없습니다'));
    });
  });

  group('BundleConfig', () {
    test('parser reads 16K, 64K, 4K, unspecified and enabled=false', () {
      final c16 = parseBundleConfig(bundleConfig(enabled: true, alignment: 2))!;
      expect(c16.enabled, isTrue);
      expect(c16.alignment, '16k');
      expect(
          parseBundleConfig(bundleConfig(enabled: true, alignment: 3))!
              .alignment,
          '64k');
      expect(
          parseBundleConfig(bundleConfig(enabled: true, alignment: 1))!
              .alignment,
          '4k');
      expect(
          parseBundleConfig(bundleConfig(enabled: true, alignment: 0))!
              .alignment,
          'unspecified');
      expect(
          parseBundleConfig(bundleConfig(enabled: false, alignment: 2))!
              .enabled,
          isFalse);
    });

    test('parser returns null for missing, truncated or garbled data', () {
      final full = bundleConfig(enabled: true, alignment: 2);
      expect(parseBundleConfig(Uint8List(0)), isNull);
      // no optimizations message at all
      expect(
          parseBundleConfig(Uint8List.fromList(
              lenField(1, lenField(1, utf8.encode('1.17.2'))))),
          isNull);
      for (var cut = 1; cut < full.length; cut++) {
        final part = Uint8List.sublistView(full, 0, full.length - cut);
        expect(() => parseBundleConfig(part), returnsNormally,
            reason: 'cut $cut');
      }
      expect(parseBundleConfig(Uint8List.sublistView(full, 0, full.length - 3)),
          isNull);
      expect(
          parseBundleConfig(Uint8List.fromList(List.filled(32, 0xff))), isNull);
      // wire type 7 does not exist
      expect(parseBundleConfig(Uint8List.fromList([0x17, 0x00])), isNull);
    });

    String aab(Uint8List? config) {
      final p = '${tmp.path}/a${config?.length ?? 0}.aab';
      writeBytes(
          p,
          buildZip([
            if (config != null) ZipFileSpec('BundleConfig.pb', config),
            ZipFileSpec('base/lib/arm64-v8a/libok.so', good, stored: false),
          ]));
      return p;
    }

    for (final (value, label) in [(2, '16K'), (3, '64K')]) {
      test('$label alignment: zip-align ok, no AAB note, exit 0', () async {
        final p = aab(bundleConfig(enabled: true, alignment: value));
        final r = await cli(['check', p]);
        expect(r.code, 0, reason: r.out);
        // 표 행은 LOAD 정렬만 보이므로 번들 설정은 참고 한 줄로 알린다.
        expect(r.out, contains('arm64-v8a  libok.so  OK'));
        expect(
            'BundleConfig.pb) sets $label native library alignment'
                .allMatches(r.out)
                .length,
            1);
        expect(r.out, isNot(contains('bundletool rebuilds')));
        final md = await cli(['check', p, '--format', 'markdown']);
        expect(md.out, contains('> Note: the bundle config'));
        final ko = await cli(['check', p, '--lang', 'ko']);
        expect(ko.out, contains('네이티브 라이브러리 정렬을 $label 로 지정'));
        final j = json(await cli(['check', p, '--json']));
        final zip = ((j['libraries'] as List).single['checks'] as List)
            .firstWhere((c) => c['id'] == 'zip-align') as Map;
        expect(zip['status'], 'ok');
        expect(zip['code'], 'aab_config_ok');
        expect(zip['alignment'], label);
      });
    }

    test('enabled=false, truncated or no config: zip-align n/a, exit 0',
        () async {
      final full = bundleConfig(enabled: true, alignment: 2);
      for (final config in [
        bundleConfig(enabled: false, alignment: 2),
        Uint8List.sublistView(full, 0, full.length - 3),
        null,
      ]) {
        final p = aab(config);
        final r = await cli(['check', p]);
        expect(r.code, 0, reason: r.out);
        expect(r.out, contains('bundletool rebuilds'));
        final j = json(await cli(['check', p, '--json']));
        final zip = ((j['libraries'] as List).single['checks'] as List)
            .firstWhere((c) => c['id'] == 'zip-align') as Map;
        expect(zip['status'], 'na');
        expect(zip['code'], 'aab');
      }
    });
  });
}
