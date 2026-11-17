// Minimal ELF reader: only what the 16 KB page-size checks need.
//
// Rules implemented (source: https://developer.android.com/guide/practices/page-sizes,
// checked 2026-11-18):
//  * every PT_LOAD segment must have p_align >= 0x4000 (16 KB);
//  * a PT_GNU_RELRO segment must end on a 16 KB boundary, or end where its
//    containing PT_LOAD ends;
//  * (extra) p_offset % p_align == p_vaddr % p_align for every PT_LOAD, which
//    catches files whose p_align was edited without relinking.
import 'dart:typed_data';

/// 16 KB, the page size the checks are written for.
const int pageSize16k = 0x4000;

const int _ptLoad = 1;
const int _ptGnuRelro = 0x6474e552;

/// Thrown by [parseElf] when the bytes are not a usable ELF file.
class ElfFormatException implements Exception {
  ElfFormatException(this.code);

  /// `not_elf` or `truncated`.
  final String code;

  @override
  String toString() => 'ElfFormatException($code)';
}

/// One entry of the ELF program header table.
class ProgramHeader {
  const ProgramHeader({
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

  int get end => vaddr + memsz;
}

/// Parsed ELF header facts.
class ElfInfo {
  const ElfInfo({
    required this.is64,
    required this.bigEndian,
    required this.machine,
    required this.headers,
  });

  final bool is64;
  final bool bigEndian;
  final int machine;

  /// Empty for 32-bit files (they are not examined).
  final List<ProgramHeader> headers;

  List<ProgramHeader> get loads =>
      headers.where((h) => h.type == _ptLoad).toList();

  ProgramHeader? get relro {
    for (final h in headers) {
      if (h.type == _ptGnuRelro) return h;
    }
    return null;
  }

  /// Smallest p_align among PT_LOAD segments, or null when there is none.
  int? get minLoadAlign {
    int? min;
    for (final h in loads) {
      if (min == null || h.align < min) min = h.align;
    }
    return min;
  }

  /// Android ABI name derived from `e_machine`, or null when unknown.
  String? get abi => abiForMachine(machine, is64);

  /// PT_LOAD segments whose file offset and address disagree modulo p_align.
  List<ProgramHeader> get incongruentLoads => [
        for (final h in loads)
          if (h.align > 1 && h.offset % h.align != h.vaddr % h.align) h,
      ];

  /// Null when there is no RELRO segment; otherwise whether it satisfies the
  /// 16 KB rule.
  bool? get relroAligned {
    final r = relro;
    if (r == null) return null;
    if (r.end % pageSize16k == 0) return true;
    for (final l in loads) {
      if (l.vaddr <= r.vaddr && r.vaddr < l.end) return l.end == r.end;
    }
    return false;
  }
}

/// Maps `e_machine` to the Android ABI directory name.
String? abiForMachine(int machine, bool is64) {
  switch (machine) {
    case 183:
      return 'arm64-v8a';
    case 62:
      return 'x86_64';
    case 243:
      return 'riscv64';
    case 40:
      return 'armeabi-v7a';
    case 3:
      return 'x86';
  }
  return null;
}

/// Parses the ELF header and, for 64-bit files, the program header table.
///
/// Throws [ElfFormatException] for non-ELF or truncated input; never throws
/// anything else.
ElfInfo parseElf(Uint8List b) {
  if (b.length < 20 ||
      b[0] != 0x7f ||
      b[1] != 0x45 ||
      b[2] != 0x4c ||
      b[3] != 0x46) {
    throw ElfFormatException('not_elf');
  }
  final cls = b[4];
  final data = b[5];
  if ((cls != 1 && cls != 2) || (data != 1 && data != 2)) {
    throw ElfFormatException('not_elf');
  }
  final is64 = cls == 2;
  final endian = data == 1 ? Endian.little : Endian.big;
  final bd = ByteData.sublistView(b);
  final machine = bd.getUint16(18, endian);
  if (!is64) {
    return ElfInfo(
      is64: false,
      bigEndian: endian == Endian.big,
      machine: machine,
      headers: const [],
    );
  }
  if (b.length < 64) throw ElfFormatException('truncated');
  final phoff = bd.getUint64(32, endian);
  final phentsize = bd.getUint16(54, endian);
  final phnum = bd.getUint16(56, endian);
  if (phentsize < 56 || phoff < 0 || phoff + phnum * phentsize > b.length) {
    throw ElfFormatException('truncated');
  }
  final headers = <ProgramHeader>[];
  for (var i = 0; i < phnum; i++) {
    final o = phoff + i * phentsize;
    headers.add(ProgramHeader(
      type: bd.getUint32(o, endian),
      offset: bd.getUint64(o + 8, endian),
      vaddr: bd.getUint64(o + 16, endian),
      filesz: bd.getUint64(o + 32, endian),
      memsz: bd.getUint64(o + 40, endian),
      align: bd.getUint64(o + 48, endian),
    ));
  }
  return ElfInfo(
    is64: true,
    bigEndian: endian == Endian.big,
    machine: machine,
    headers: headers,
  );
}
