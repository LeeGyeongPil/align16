import 'package:align16/src/sample/synth_elf.dart';
import 'package:align16/src/verdict.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('RELRO end on a 16 KB boundary is ok', () {
    // RELRO 0x4000..0x8000, LOAD ends at 0xA000: only the modulo rule can pass.
    final v =
        eval(simpleElf(align: 0x4000, dataMemsz: 0x6000, relroMemsz: 0x4000));
    expect(checkOf(v, CheckId.relro).status, Status.ok);
    expect(v.status, Status.ok);
  });

  test('RELRO ending where its LOAD ends is ok', () {
    // end 0x4400 is not 16 KB aligned but equals the LOAD end.
    final v =
        eval(simpleElf(align: 0x4000, dataMemsz: 0x400, relroMemsz: 0x400));
    expect(checkOf(v, CheckId.relro).status, Status.ok);
  });

  test('RELRO neither aligned nor at LOAD end fails', () {
    final v =
        eval(simpleElf(align: 0x4000, dataMemsz: 0x6000, relroMemsz: 0x1000));
    final c = checkOf(v, CheckId.relro);
    expect(c.status, Status.fail);
    expect(c.args['end'], 0x5000);
    expect(v.status, Status.fail);
  });

  test('no RELRO segment is ok', () {
    final v = eval(simpleElf(align: 0x4000, relroMemsz: null));
    expect(checkOf(v, CheckId.relro).status, Status.ok);
    expect(checkOf(v, CheckId.relro).code, 'no_relro');
  });

  test('RELRO check is independent of load alignment', () {
    final v =
        eval(simpleElf(align: 0x10000, dataMemsz: 0x6000, relroMemsz: 0x1000));
    expect(checkOf(v, CheckId.loadAlign).status, Status.ok);
    expect(checkOf(v, CheckId.relro).status, Status.fail);
  });

  group('congruence', () {
    test('consistent file is ok', () {
      final v = eval(simpleElf(align: 0x4000));
      expect(checkOf(v, CheckId.congruence).status, Status.ok);
    });

    test('p_align patched to 0x4000 without relinking warns', () {
      // vaddr no longer matches the file offset modulo 0x4000.
      final v = eval(simpleElf(align: 0x4000, dataVaddrSkew: 0x1000));
      expect(checkOf(v, CheckId.loadAlign).status, Status.ok);
      expect(checkOf(v, CheckId.congruence).status, Status.warn);
      expect(v.status, Status.warn);
    });

    test('--strict turns the warning into a failure', () {
      final v =
          eval(simpleElf(align: 0x4000, dataVaddrSkew: 0x1000), strict: true);
      expect(checkOf(v, CheckId.congruence).status, Status.fail);
      expect(v.status, Status.fail);
    });
  });
}
