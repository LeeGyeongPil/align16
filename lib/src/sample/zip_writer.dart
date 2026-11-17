// Minimal ZIP writer for the `sample` command and the tests.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One file to put in the archive.
class ZipFileSpec {
  const ZipFileSpec(
    this.name,
    this.data, {
    this.stored = true,
    this.alignTo = 0,
    this.residue = 0,
  });

  final String name;
  final Uint8List data;

  /// STORED (true) or DEFLATE (false).
  final bool stored;

  /// When > 0, pad the local extra field so that
  /// `dataOffset % alignTo == residue` (what zipalign does with residue 0).
  final int alignTo;
  final int residue;
}

final List<int> _crcTable = () {
  final t = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

/// CRC-32 of [data].
int crc32(List<int> data) {
  var c = 0xffffffff;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return c ^ 0xffffffff;
}

/// Builds a ZIP archive. With [zip64] the central directory uses ZIP64
/// fields and records (even though the archive is small), to exercise
/// readers.
Uint8List buildZip(List<ZipFileSpec> files, {bool zip64 = false}) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var count = 0;
  for (final f in files) {
    final name = utf8.encode(f.name);
    final compressed = f.stored
        ? f.data
        : Uint8List.fromList(ZLibEncoder(raw: true).convert(f.data));
    final crc = crc32(f.data);
    final localOffset = out.length;
    var pad = 0;
    if (f.alignTo > 0) {
      final dataStart = localOffset + 30 + name.length;
      pad = (f.residue - dataStart) % f.alignTo;
      if (pad < 0) pad += f.alignTo;
    }
    final local = ByteData(30);
    local.setUint32(0, 0x04034b50, Endian.little);
    local.setUint16(4, 20, Endian.little);
    local.setUint16(6, 0x0800, Endian.little);
    local.setUint16(8, f.stored ? 0 : 8, Endian.little);
    local.setUint16(10, 0, Endian.little);
    local.setUint16(12, 0x21, Endian.little);
    local.setUint32(14, crc, Endian.little);
    local.setUint32(18, compressed.length, Endian.little);
    local.setUint32(22, f.data.length, Endian.little);
    local.setUint16(26, name.length, Endian.little);
    local.setUint16(28, pad, Endian.little);
    out.add(local.buffer.asUint8List());
    out.add(name);
    out.add(Uint8List(pad));
    out.add(compressed);

    final cd = ByteData(46);
    cd.setUint32(0, 0x02014b50, Endian.little);
    cd.setUint16(4, zip64 ? 45 : 20, Endian.little);
    cd.setUint16(6, zip64 ? 45 : 20, Endian.little);
    cd.setUint16(8, 0x0800, Endian.little);
    cd.setUint16(10, f.stored ? 0 : 8, Endian.little);
    cd.setUint16(14, 0x21, Endian.little);
    cd.setUint32(16, crc, Endian.little);
    cd.setUint32(20, zip64 ? 0xFFFFFFFF : compressed.length, Endian.little);
    cd.setUint32(24, zip64 ? 0xFFFFFFFF : f.data.length, Endian.little);
    cd.setUint16(28, name.length, Endian.little);
    cd.setUint16(30, zip64 ? 28 : 0, Endian.little);
    cd.setUint32(42, zip64 ? 0xFFFFFFFF : localOffset, Endian.little);
    central.add(cd.buffer.asUint8List());
    central.add(name);
    if (zip64) {
      final x = ByteData(28);
      x.setUint16(0, 0x0001, Endian.little);
      x.setUint16(2, 24, Endian.little);
      x.setUint64(4, f.data.length, Endian.little);
      x.setUint64(12, compressed.length, Endian.little);
      x.setUint64(20, localOffset, Endian.little);
      central.add(x.buffer.asUint8List());
    }
    count++;
  }

  final cdOffset = out.length;
  final cdBytes = central.toBytes();
  out.add(cdBytes);
  if (zip64) {
    final rec = ByteData(56);
    rec.setUint32(0, 0x06064b50, Endian.little);
    rec.setUint64(4, 44, Endian.little);
    rec.setUint16(12, 45, Endian.little);
    rec.setUint16(14, 45, Endian.little);
    rec.setUint64(24, count, Endian.little);
    rec.setUint64(32, count, Endian.little);
    rec.setUint64(40, cdBytes.length, Endian.little);
    rec.setUint64(48, cdOffset, Endian.little);
    final recOffset = out.length;
    out.add(rec.buffer.asUint8List());
    final loc = ByteData(20);
    loc.setUint32(0, 0x07064b50, Endian.little);
    loc.setUint32(4, 0, Endian.little);
    loc.setUint64(8, recOffset, Endian.little);
    loc.setUint32(16, 1, Endian.little);
    out.add(loc.buffer.asUint8List());
  }
  final eocd = ByteData(22);
  eocd.setUint32(0, 0x06054b50, Endian.little);
  eocd.setUint16(8, zip64 ? 0xFFFF : count, Endian.little);
  eocd.setUint16(10, zip64 ? 0xFFFF : count, Endian.little);
  eocd.setUint32(12, zip64 ? 0xFFFFFFFF : cdBytes.length, Endian.little);
  eocd.setUint32(16, zip64 ? 0xFFFFFFFF : cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.toBytes();
}
