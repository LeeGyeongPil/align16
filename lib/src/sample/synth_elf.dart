// Tiny ELF generator for the `sample` command and the tests.
//
// It writes only an ELF header and a program header table plus filler bytes,
// which is exactly what align16 reads. The result is NOT a loadable library.
import 'dart:typed_data';

/// One program header to write.
class SynthSegment {
  const SynthSegment({
    required this.type,
    required this.offset,
    required this.vaddr,
    required this.filesz,
    required this.memsz,
    required this.align,
  });

  final int type;
  final int offset;
  final int vaddr;
  final int filesz;
  final int memsz;
  final int align;
}

/// PT_LOAD.
const int synthPtLoad = 1;

/// PT_GNU_RELRO.
const int synthPtGnuRelro = 0x6474e552;

/// Builds an ELF file with exactly the given program headers.
///
/// The file is long enough to contain every segment's file range; filler bytes
/// derive from [seed] so equal seeds give equal bytes.
Uint8List buildElf({
  bool is64 = true,
  bool bigEndian = false,
  int machine = 183,
  List<SynthSegment> segments = const [],
  int seed = 0,
}) {
  final endian = bigEndian ? Endian.big : Endian.little;
  final ehsize = is64 ? 64 : 52;
  final phentsize = is64 ? 56 : 32;
  var size = ehsize + segments.length * phentsize;
  for (final s in segments) {
    if (s.offset + s.filesz > size) size = s.offset + s.filesz;
  }
  final out = Uint8List(size);
  // deterministic filler
  var x = seed * 2654435761 + 12345;
  for (var i = ehsize; i < size; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    out[i] = (x >> 16) & 0xff;
  }
  final bd = ByteData.sublistView(out);
  out.setAll(0, [0x7f, 0x45, 0x4c, 0x46, is64 ? 2 : 1, bigEndian ? 2 : 1, 1]);
  for (var i = 7; i < 16; i++) {
    out[i] = 0;
  }
  bd.setUint16(16, 3, endian); // ET_DYN
  bd.setUint16(18, machine, endian);
  bd.setUint32(20, 1, endian);
  if (is64) {
    bd.setUint64(24, 0, endian);
    bd.setUint64(32, ehsize, endian); // e_phoff
    bd.setUint64(40, 0, endian);
    bd.setUint32(48, 0, endian);
    bd.setUint16(52, ehsize, endian);
    bd.setUint16(54, phentsize, endian);
    bd.setUint16(56, segments.length, endian);
  } else {
    bd.setUint32(24, 0, endian);
    bd.setUint32(28, ehsize, endian); // e_phoff
    bd.setUint32(32, 0, endian);
    bd.setUint32(36, 0, endian);
    bd.setUint16(40, ehsize, endian);
    bd.setUint16(42, phentsize, endian);
    bd.setUint16(44, segments.length, endian);
  }
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    final o = ehsize + i * phentsize;
    if (is64) {
      bd.setUint32(o, s.type, endian);
      bd.setUint32(o + 4, 4, endian); // flags: R
      bd.setUint64(o + 8, s.offset, endian);
      bd.setUint64(o + 16, s.vaddr, endian);
      bd.setUint64(o + 24, s.vaddr, endian);
      bd.setUint64(o + 32, s.filesz, endian);
      bd.setUint64(o + 40, s.memsz, endian);
      bd.setUint64(o + 48, s.align, endian);
    } else {
      bd.setUint32(o, s.type, endian);
      bd.setUint32(o + 4, s.offset, endian);
      bd.setUint32(o + 8, s.vaddr, endian);
      bd.setUint32(o + 12, s.vaddr, endian);
      bd.setUint32(o + 16, s.filesz, endian);
      bd.setUint32(o + 20, s.memsz, endian);
      bd.setUint32(o + 24, 4, endian);
      bd.setUint32(o + 28, s.align, endian);
    }
  }
  return out;
}

/// A typical two-segment library with an optional RELRO segment.
///
/// Layout: LOAD #1 covers the headers at offset/vaddr 0; LOAD #2 starts at
/// [align] and is [dataFilesz] bytes in the file and [dataMemsz] in memory.
/// RELRO (when [relroMemsz] is not null) starts at LOAD #2 and is
/// [relroMemsz] bytes long. [dataVaddrSkew] shifts only the virtual
/// addresses of LOAD #2 and RELRO, which breaks offset/vaddr congruence the
/// way a patched p_align does.
Uint8List simpleElf({
  int align = 0x4000,
  int machine = 183,
  bool is64 = true,
  bool bigEndian = false,
  int seed = 0,
  int dataFilesz = 0x400,
  int? dataMemsz,
  int? relroMemsz = 0x400,
  int dataVaddrSkew = 0,
}) {
  final memsz = dataMemsz ?? dataFilesz;
  final vaddr2 = align + dataVaddrSkew;
  return buildElf(
    is64: is64,
    bigEndian: bigEndian,
    machine: machine,
    seed: seed,
    segments: [
      SynthSegment(
          type: synthPtLoad,
          offset: 0,
          vaddr: 0,
          filesz: 0x200,
          memsz: 0x200,
          align: align),
      SynthSegment(
          type: synthPtLoad,
          offset: align,
          vaddr: vaddr2,
          filesz: dataFilesz,
          memsz: memsz,
          align: align),
      if (relroMemsz != null)
        SynthSegment(
            type: synthPtGnuRelro,
            offset: align,
            vaddr: vaddr2,
            filesz: relroMemsz < dataFilesz ? relroMemsz : dataFilesz,
            memsz: relroMemsz,
            align: 1),
    ],
  );
}
