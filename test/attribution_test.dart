import 'dart:io';
import 'dart:typed_data';

import 'package:align16/src/attribution.dart';
import 'package:align16/src/project/package_graph.dart';
import 'package:align16/src/project/plugin_index.dart';
import 'package:align16/src/sample/synth_elf.dart';
import 'package:test/test.dart';

import 'helpers.dart';

late Directory tmp;

const inter = 'intermediates/merged_native_libs/release/out/lib';

Owner own(String project, String name, Uint8List bytes,
    {String abi = 'arm64-v8a'}) {
  final g = PackageGraph.load(project);
  return attribute(
    name: name,
    abi: abi,
    bytes: bytes,
    index: PluginIndex.build(project, g),
    graph: g,
  );
}

void main() {
  setUp(() => tmp = makeTemp('attr'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final apkBytes = simpleElf(align: 0x1000, seed: 1);
  final other = simpleElf(align: 0x1000, seed: 2);

  test('build/<plugin>/intermediates/**/<abi>/*.so -> that plugin', () {
    final p = makeProject(tmp, chain);
    writeBytes('$p/build/clip_engine_ctx/$inter/arm64-v8a/libclip.so', other);
    final o = own(p, 'libclip.so', apkBytes);
    expect(o.confidence, Confidence.name);
    expect(o.package, 'clip_engine_ctx');
    expect(o.path, ['my_app', 'clip_kit', 'clip_native', 'clip_engine_ctx']);
  });

  test('plugin jniLibs -> that plugin', () {
    final p = makeProject(tmp, chain);
    writeBytes(
        '${tmp.path}/pkgs/fancy_anim/android/src/main/jniLibs/arm64-v8a/libfancy.so',
        other);
    final o = own(p, 'libfancy.so', apkBytes);
    expect(o.confidence, Confidence.name);
    expect(o.package, 'fancy_anim');
    expect(o.path, ['my_app', 'fancy_anim']);
  });

  test('plugin android/build output is searched too', () {
    final p = makeProject(tmp, chain);
    writeBytes(
        '${tmp.path}/pkgs/clip_native/android/build/$inter/arm64-v8a/libn.so',
        other);
    expect(own(p, 'libn.so', apkBytes).package, 'clip_native');
  });

  test('same name in several packages: identical bytes -> exact', () {
    final p = makeProject(tmp, chain);
    writeBytes(
        '$p/build/fancy_anim/$inter/arm64-v8a/libc++_shared.so', apkBytes);
    writeBytes('$p/build/clip_native/$inter/arm64-v8a/libc++_shared.so', other);
    final o = own(p, 'libc++_shared.so', apkBytes);
    expect(o.confidence, Confidence.exact);
    expect(o.package, 'fancy_anim');
    expect(o.candidates.map((c) => c.package), ['fancy_anim']);
  });

  test('no byte match among several packages -> ambiguous with all candidates',
      () {
    final p = makeProject(tmp, chain);
    writeBytes('$p/build/fancy_anim/$inter/arm64-v8a/libc++_shared.so', other);
    writeBytes('$p/build/clip_native/$inter/arm64-v8a/libc++_shared.so',
        simpleElf(seed: 9));
    writeBytes('$p/build/clip_kit/$inter/arm64-v8a/libc++_shared.so',
        simpleElf(seed: 10));
    final o = own(p, 'libc++_shared.so', apkBytes);
    expect(o.confidence, Confidence.ambiguous);
    expect(o.package, isNull);
    expect(o.packages, ['clip_kit', 'clip_native', 'fancy_anim']);
    expect(o.candidates, hasLength(3));
  });

  test('identical bytes in several packages stay ambiguous (no guessing)', () {
    final p = makeProject(tmp, chain);
    writeBytes(
        '$p/build/fancy_anim/$inter/arm64-v8a/libc++_shared.so', apkBytes);
    writeBytes('$p/build/clip_kit/$inter/arm64-v8a/libc++_shared.so', apkBytes);
    final o = own(p, 'libc++_shared.so', apkBytes);
    expect(o.confidence, Confidence.ambiguous);
    expect(o.packages, ['clip_kit', 'fancy_anim']);
  });

  test('only candidates for the same ABI count', () {
    final p = makeProject(tmp, chain);
    writeBytes('$p/build/fancy_anim/$inter/x86_64/libfancy.so', other);
    expect(own(p, 'libfancy.so', apkBytes).confidence, Confidence.none);
    expect(
        own(p, 'libfancy.so', apkBytes, abi: 'x86_64').package, 'fancy_anim');
  });

  test('no candidate -> none', () {
    final p = makeProject(tmp, chain);
    final o = own(p, 'libunknown.so', apkBytes);
    expect(o.confidence, Confidence.none);
    expect(o.package, isNull);
    expect(o.candidates, isEmpty);
  });

  test('libflutter.so and libapp.so are labelled specially', () {
    final p = makeProject(tmp, chain);
    expect(own(p, 'libflutter.so', apkBytes).confidence, Confidence.engine);
    expect(own(p, 'libapp.so', apkBytes).confidence, Confidence.app);
  });

  test('build folders of unknown names (e.g. app) are ignored', () {
    final p = makeProject(tmp, chain);
    writeBytes('$p/build/app/$inter/arm64-v8a/libmine.so', other);
    expect(own(p, 'libmine.so', apkBytes).confidence, Confidence.none);
  });
}
