// Builds the synthetic practice sample: a fake Flutter project, a fake APK and
// a fake AAB. Package names are invented on purpose so no real package is
// blamed. Shared by the `sample` command and the tests.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../i18n/i18n.dart';
import '../paths.dart';
import 'synth_elf.dart';
import 'zip_writer.dart';

/// Where the sample files were written.
class SampleFiles {
  const SampleFiles({
    required this.dir,
    required this.project,
    required this.apk,
    required this.aab,
    required this.allow,
  });

  final String dir;
  final String project;
  final String apk;
  final String aab;

  /// Allow list used by the README's "Known leftovers" example.
  final String allow;
}

/// Name of the sample allow list (the README example uses this name).
const sampleAllowFile = 'align16-allow.txt';

/// Entries of the sample allow list: the four libraries that fail in the
/// sample APK. Plain names and one `<abi>/name` entry show both forms.
const sampleAllowEntries = [
  'libfancy_anim.so',
  'libclip_engine_ctx.so',
  'arm64-v8a/libc++_shared.so',
  'libmedia_box.so',
];

const _intermediates = 'intermediates/merged_native_libs/release/out/lib';

/// Writes the sample into [outDir] (created when missing). Comments in the
/// generated allow list use the language of [messages].
SampleFiles writeSample(String outDir,
    {Messages messages = const Messages(Lang.en)}) {
  Directory(outDir).createSync(recursive: true);
  // `--out ./align16-sample` 이 `/…/./align16-sample` 로 보이지 않게 정규화한다.
  final base = normalizedAbsolute(outDir);
  final project = '$base/my_app';
  final pkgs = '$base/pkgs';

  // ---- libraries (all deterministic) ----
  final flutterOk = simpleElf(align: 0x10000, seed: 1, relroMemsz: 0x400);
  final appOk = simpleElf(align: 0x4000, seed: 2);
  final fancyBad = simpleElf(align: 0x1000, seed: 3);
  final clipBad = simpleElf(align: 0x1000, seed: 4);
  final clipBuildCopy = simpleElf(align: 0x1000, seed: 40); // unstripped copy
  final cppApk = simpleElf(align: 0x1000, seed: 5);
  final cppMediaCopy = simpleElf(align: 0x1000, seed: 50);
  final mediaOk = simpleElf(align: 0x4000, seed: 6);
  final fancy32 = simpleElf(align: 0x1000, seed: 7, is64: false, machine: 40);
  final flutterX64 = simpleElf(align: 0x10000, seed: 8, machine: 62);

  // ---- project files ----
  void write(String path, List<int> bytes) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
  }

  void text(String path, String s) => write(path, utf8.encode(s));

  text('$project/pubspec.yaml', '''
name: my_app
description: Synthetic align16 sample app.
dependencies:
  flutter:
    sdk: flutter
  fancy_anim: ^1.0.0
  clip_kit: ^2.0.0
  media_box: ^0.5.0
''');
  const deps = {
    'fancy_anim': <String>[],
    'clip_kit': ['clip_native'],
    'clip_native': ['clip_engine_ctx'],
    'clip_engine_ctx': <String>[],
    'media_box': <String>[],
  };
  deps.forEach((name, d) {
    text('$pkgs/$name/pubspec.yaml', '''
name: $name
dependencies:
${[for (final x in d) '  $x: any'].join('\n')}
''');
  });
  text(
    '$project/.dart_tool/package_config.json',
    jsonEncode({
      'configVersion': 2,
      'packages': [
        for (final n in deps.keys)
          {
            'name': n,
            'rootUri': '../../pkgs/$n',
            'packageUri': 'lib/',
            'languageVersion': '3.5',
          },
        {
          'name': 'my_app',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.5',
        },
      ],
    }),
  );
  text(
    '$project/.flutter-plugins-dependencies',
    jsonEncode({
      'plugins': {
        'android': [
          for (final e in deps.entries)
            {
              'name': e.key,
              'path': '$pkgs/${e.key}/',
              'dependencies': e.value,
            },
        ],
      },
    }),
  );

  // Candidate files in the project's build folder (what a Flutter build leaves).
  void candidate(String plugin, String abi, String lib, Uint8List b) =>
      write('$project/build/$plugin/$_intermediates/$abi/$lib', b);
  candidate('fancy_anim', 'arm64-v8a', 'libfancy_anim.so', fancyBad);
  candidate('fancy_anim', 'arm64-v8a', 'libc++_shared.so', cppApk);
  candidate('media_box', 'arm64-v8a', 'libc++_shared.so', cppMediaCopy);
  candidate('media_box', 'arm64-v8a', 'libmedia_box.so', mediaOk);
  candidate(
      'clip_engine_ctx', 'arm64-v8a', 'libclip_engine_ctx.so', clipBuildCopy);

  // ---- APK: STORED libraries aligned to 16 KB, one deliberately not ----
  ZipFileSpec lib(String abi, String name, Uint8List b,
          {bool aligned = true}) =>
      ZipFileSpec('lib/$abi/$name', b,
          alignTo: 0x4000, residue: aligned ? 0 : 0x1000);
  final apk = buildZip([
    ZipFileSpec(
        'AndroidManifest.xml', utf8.encode('<manifest/>').asTypedList()),
    lib('arm64-v8a', 'libflutter.so', flutterOk),
    lib('arm64-v8a', 'libapp.so', appOk),
    lib('arm64-v8a', 'libfancy_anim.so', fancyBad),
    lib('arm64-v8a', 'libclip_engine_ctx.so', clipBad),
    lib('arm64-v8a', 'libc++_shared.so', cppApk),
    lib('arm64-v8a', 'libmedia_box.so', mediaOk, aligned: false),
    lib('x86_64', 'libflutter.so', flutterX64),
    lib('armeabi-v7a', 'libfancy_anim.so', fancy32),
  ]);
  write('$base/app-release.apk', apk);

  // ---- AAB: base module, libraries compressed like bundletool input ----
  final aab = buildZip([
    ZipFileSpec('base/manifest/AndroidManifest.xml',
        utf8.encode('<manifest/>').asTypedList()),
    ZipFileSpec('base/lib/arm64-v8a/libflutter.so', flutterOk, stored: false),
    ZipFileSpec('base/lib/arm64-v8a/libfancy_anim.so', fancyBad, stored: false),
    ZipFileSpec('base/lib/arm64-v8a/libclip_engine_ctx.so', clipBad,
        stored: false),
  ]);
  write('$base/app-release.aab', aab);

  // ---- allow list for the README "Known leftovers" example ----
  // 샘플 APK 에서 실패하는 네 라이브러리를 적는다. 그대로 --allow 로 주면 PASS.
  text(
      '$base/$sampleAllowFile',
      [
        for (final line in messages.t('sample.allow_comment').split('\n'))
          '# $line',
        ...sampleAllowEntries,
        '',
      ].join('\n'));

  return SampleFiles(
    dir: base,
    project: project,
    apk: '$base/app-release.apk',
    aab: '$base/app-release.aab',
    allow: '$base/$sampleAllowFile',
  );
}

extension on List<int> {
  Uint8List asTypedList() => Uint8List.fromList(this);
}
