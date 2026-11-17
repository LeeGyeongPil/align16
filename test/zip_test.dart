import 'dart:io';
import 'dart:typed_data';

import 'package:align16/src/artifact.dart';
import 'package:align16/src/checker.dart';
import 'package:align16/src/sample/synth_elf.dart';
import 'package:align16/src/sample/zip_writer.dart';
import 'package:align16/src/verdict.dart';
import 'package:align16/src/zip_reader.dart';
import 'package:archive/archive.dart';
import 'package:test/test.dart';

import 'helpers.dart';

late Directory tmp;

String zipFile(String name, List<ZipFileSpec> files, {bool zip64 = false}) {
  final p = '${tmp.path}/$name';
  writeBytes(p, buildZip(files, zip64: zip64));
  return p;
}

void main() {
  setUp(() => tmp = makeTemp('zip'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final good = simpleElf(align: 0x4000, seed: 1);
  final bad = simpleElf(align: 0x1000, seed: 2);

  test('STORED offset multiple of 16384 is ok, otherwise FAIL zip-align', () {
    final p = zipFile('a.apk', [
      ZipFileSpec('lib/arm64-v8a/liba.so', good, alignTo: 0x4000),
      ZipFileSpec('lib/arm64-v8a/libb.so', good,
          alignTo: 0x4000, residue: 0x1000),
    ]);
    final r = checkArtifact(p);
    final a = r.libraries.firstWhere((l) => l.name == 'liba.so');
    final b = r.libraries.firstWhere((l) => l.name == 'libb.so');
    expect(checkOf(a, CheckId.zipAlign).status, Status.ok);
    expect(a.status, Status.ok);
    expect(checkOf(b, CheckId.zipAlign).status, Status.fail);
    expect(
        (checkOf(b, CheckId.zipAlign).args['offset']! as int) % 0x4000, 0x1000);
    expect(r.exitCode, 1);
  });

  test('DEFLATE entry: zip-align n/a but ELF checks still run', () {
    final p = zipFile('d.apk', [
      ZipFileSpec('lib/arm64-v8a/libgood.so', good, stored: false),
      ZipFileSpec('lib/arm64-v8a/libbad.so', bad, stored: false),
    ]);
    final r = checkArtifact(p);
    final g = r.libraries.firstWhere((l) => l.name == 'libgood.so');
    final b = r.libraries.firstWhere((l) => l.name == 'libbad.so');
    expect(checkOf(g, CheckId.zipAlign).status, Status.na);
    expect(checkOf(g, CheckId.zipAlign).code, 'deflated');
    expect(g.status, Status.ok);
    expect(checkOf(b, CheckId.zipAlign).status, Status.na);
    expect(checkOf(b, CheckId.loadAlign).status, Status.fail);
  });

  test('offset comes from the local header (extra differs from central)', () {
    final p = zipFile('l.apk', [
      ZipFileSpec('lib/arm64-v8a/liba.so', good, alignTo: 0x4000),
    ]);
    final z = ZipReader.open(p);
    addTearDown(z.close);
    final e = z.entries.single;
    final off = z.dataOffsetOf(e);
    expect(off % 0x4000, 0);
    // The writer pads only the local extra field; the central one is empty,
    // so a reader that trusted the central lengths would be off.
    expect(off, greaterThan(e.localHeaderOffset + 30 + e.name.length));
    expect(z.readEntry(e), good);
  });

  test('forced ZIP64 archive is readable', () {
    final p = zipFile(
      'z.apk',
      [
        ZipFileSpec('lib/arm64-v8a/liba.so', good, alignTo: 0x4000),
        ZipFileSpec('lib/arm64-v8a/libb.so', bad, stored: false),
        ZipFileSpec('assets/readme.txt', Uint8List.fromList(utf('hello'))),
      ],
      zip64: true,
    );
    final z = ZipReader.open(p);
    addTearDown(z.close);
    expect(z.entries.map((e) => e.name), [
      'lib/arm64-v8a/liba.so',
      'lib/arm64-v8a/libb.so',
      'assets/readme.txt'
    ]);
    expect(z.readEntry(z.entries[0]), good);
    expect(z.readEntry(z.entries[1]), bad);
    final r = checkArtifact(p);
    expect(r.libraries.map((l) => l.status), [Status.ok, Status.fail]);
  });

  test('names, sizes and contents equal package:archive 4.6.0', () {
    for (final zip64 in [false, true]) {
      final p = zipFile(
          'c$zip64.zip',
          [
            ZipFileSpec('a/one.bin', good, alignTo: 0x4000),
            ZipFileSpec('b/two.bin', bad, stored: false),
            ZipFileSpec('c/three.txt', Uint8List.fromList(utf('x' * 5000)),
                stored: false),
            ZipFileSpec('empty.txt', Uint8List(0)),
          ],
          zip64: zip64);
      final bytes = File(p).readAsBytesSync();
      final theirs = ZipDecoder().decodeBytes(bytes);
      final z = ZipReader.open(p);
      addTearDown(z.close);
      final ours = {for (final e in z.entries) e.name: e};
      final names =
          theirs.files.where((f) => f.isFile).map((f) => f.name).toSet();
      expect(ours.keys.toSet(), names, reason: 'zip64=$zip64');
      for (final f in theirs.files.where((f) => f.isFile)) {
        final e = ours[f.name]!;
        expect(e.size, f.size, reason: f.name);
        expect(z.readEntry(e), f.content as List<int>, reason: f.name);
      }
    }
  });

  test('EOCD is found before a trailing ZIP comment', () {
    final raw =
        buildZip([ZipFileSpec('lib/arm64-v8a/liba.so', good, alignTo: 0x4000)]);
    // append a ZIP comment: EOCD is no longer the last 22 bytes
    final b = BytesBuilder()..add(raw);
    final bd = ByteData.sublistView(raw);
    final eocd = raw.length - 22;
    expect(bd.getUint32(eocd, Endian.little), 0x06054b50);
    b.add(utf('trailing comment'));
    final patched = b.toBytes();
    ByteData.sublistView(patched).setUint16(eocd + 20, 16, Endian.little);
    final p = '${tmp.path}/comment.apk';
    writeBytes(p, patched);
    final r = checkArtifact(p);
    expect(r.libraries.single.status, Status.ok);
  });

  test('not a ZIP and truncated ZIP are input errors', () {
    writeBytes('${tmp.path}/x.apk', [
      0x50,
      0x4b,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22
    ]);
    expect(() => openArtifact('${tmp.path}/x.apk'),
        throwsA(isA<InputError>().having((e) => e.key, 'key', 'err.bad_zip')));
    writeText('${tmp.path}/t.txt', 'hello world');
    expect(() => openArtifact('${tmp.path}/t.txt'),
        throwsA(isA<InputError>().having((e) => e.key, 'key', 'err.not_zip')));
  });
}
