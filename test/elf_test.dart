import 'dart:typed_data';

import 'package:align16/src/elf.dart';
import 'package:align16/src/sample/synth_elf.dart';
import 'package:align16/src/verdict.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('load alignment', () {
    test('0x1000 fails', () {
      final v = eval(simpleElf(align: 0x1000));
      expect(v.status, Status.fail);
      final c = checkOf(v, CheckId.loadAlign);
      expect(c.status, Status.fail);
      expect(c.args['align'], 0x1000);
      expect(v.minLoadAlign, 0x1000);
    });

    test('0x4000 and 0x10000 pass', () {
      for (final a in [0x4000, 0x10000]) {
        final v = eval(simpleElf(align: a));
        expect(v.status, Status.ok, reason: 'align $a');
        expect(checkOf(v, CheckId.loadAlign).status, Status.ok);
        expect(v.minLoadAlign, a);
      }
    });

    test('the smallest LOAD alignment decides', () {
      final bytes = buildElf(segments: [
        const SynthSegment(
            type: synthPtLoad,
            offset: 0,
            vaddr: 0,
            filesz: 0x100,
            memsz: 0x100,
            align: 0x10000),
        const SynthSegment(
            type: synthPtLoad,
            offset: 0x10000,
            vaddr: 0x10000,
            filesz: 0x100,
            memsz: 0x100,
            align: 0x1000),
      ]);
      expect(checkOf(eval(bytes), CheckId.loadAlign).status, Status.fail);
    });

    test('32-bit ELF is N/A', () {
      final v = eval(simpleElf(align: 0x1000, is64: false, machine: 40),
          abi: 'armeabi-v7a');
      expect(v.status, Status.na);
      expect(v.is64, isFalse);
      expect(v.checks.single.code, 'elf32');
    });

    test('big-endian 64-bit ELF is parsed', () {
      final bad = eval(simpleElf(align: 0x1000, bigEndian: true));
      expect(bad.status, Status.fail);
      expect(bad.minLoadAlign, 0x1000);
      final ok = eval(simpleElf(align: 0x4000, bigEndian: true));
      expect(ok.status, Status.ok);
    });

    test('ABI comes from e_machine when there is no folder hint', () {
      expect(parseElf(simpleElf(machine: 183)).abi, 'arm64-v8a');
      expect(parseElf(simpleElf(machine: 62)).abi, 'x86_64');
      expect(parseElf(simpleElf(machine: 243)).abi, 'riscv64');
      expect(parseElf(simpleElf(machine: 40, is64: false)).abi, 'armeabi-v7a');
      expect(parseElf(simpleElf(machine: 3, is64: false)).abi, 'x86');
    });
  });

  group('broken input never throws', () {
    test('not an ELF', () {
      final v = eval(Uint8List.fromList(List.filled(200, 0x41)));
      expect(v.status, Status.error);
      expect(v.checks.single.code, 'not_elf');
    });

    test('empty and tiny files', () {
      expect(eval(Uint8List(0)).status, Status.error);
      expect(eval(Uint8List.fromList([0x7f, 0x45, 0x4c, 0x46])).status,
          Status.error);
    });

    test('truncated program header table', () {
      final full = simpleElf();
      final cut = Uint8List.sublistView(full, 0, 100);
      final v = eval(cut);
      expect(v.status, Status.error);
      expect(v.checks.single.code, 'truncated');
    });

    test('header cut before 64 bytes', () {
      final full = simpleElf();
      final v = eval(Uint8List.sublistView(full, 0, 40));
      expect(v.status, Status.error);
      expect(v.checks.single.code, 'truncated');
    });

    test('bad class byte', () {
      final b = simpleElf();
      b[4] = 9;
      expect(eval(b).status, Status.error);
    });
  });
}
