// Direct ZIP reader: EOCD -> (ZIP64) -> central directory -> local header.
//
// The data offset of an entry is computed from its *local* header, because
// zipalign pads the local extra field and the central copy can differ.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Thrown when the file is not a readable ZIP archive.
class ZipFormatException implements Exception {
  ZipFormatException(this.message);

  final String message;

  @override
  String toString() => 'ZipFormatException: $message';
}

/// One central directory entry.
class ZipEntry {
  ZipEntry({
    required this.name,
    required this.method,
    required this.flags,
    required this.compressedSize,
    required this.size,
    required this.localHeaderOffset,
  });

  final String name;

  /// 0 = STORED, 8 = DEFLATE.
  final int method;
  final int flags;
  final int compressedSize;
  final int size;
  final int localHeaderOffset;

  bool get isStored => method == 0;
}

/// Random-access ZIP reader that never loads the whole archive.
class ZipReader {
  ZipReader._(this._raf, this._length, this.entries);

  final RandomAccessFile _raf;
  final int _length;
  final Map<String, int> _dataOffsets = {};

  /// Entries in central directory order.
  final List<ZipEntry> entries;

  /// Opens [path]; throws [ZipFormatException] when it is not a ZIP file.
  static ZipReader open(String path) {
    final raf = File(path).openSync();
    try {
      final length = raf.lengthSync();
      final entries = _readDirectory(raf, length);
      return ZipReader._(raf, length, entries);
    } catch (_) {
      raf.closeSync();
      rethrow;
    }
  }

  /// Closes the underlying file.
  void close() => _raf.closeSync();

  /// Absolute file offset where the (possibly compressed) data of [e] starts.
  int dataOffsetOf(ZipEntry e) {
    return _dataOffsets.putIfAbsent(e.name, () {
      final h = _read(e.localHeaderOffset, 30);
      final bd = ByteData.sublistView(h);
      if (bd.getUint32(0, Endian.little) != 0x04034b50) {
        throw ZipFormatException('bad local header signature for "${e.name}"');
      }
      final n = bd.getUint16(26, Endian.little);
      final x = bd.getUint16(28, Endian.little);
      return e.localHeaderOffset + 30 + n + x;
    });
  }

  /// Returns the uncompressed bytes of [e].
  Uint8List readEntry(ZipEntry e) {
    if (e.flags & 1 != 0) {
      throw ZipFormatException('entry "${e.name}" is encrypted');
    }
    final raw = _read(dataOffsetOf(e), e.compressedSize);
    if (e.method == 0) return raw;
    if (e.method == 8) {
      try {
        final out = ZLibDecoder(raw: true).convert(raw);
        return out is Uint8List ? out : Uint8List.fromList(out);
      } on FormatException catch (err) {
        throw ZipFormatException('cannot inflate "${e.name}": ${err.message}');
      }
    }
    throw ZipFormatException(
        'entry "${e.name}" uses unsupported method ${e.method}');
  }

  Uint8List _read(int offset, int n) {
    if (offset < 0 || n < 0 || offset + n > _length) {
      throw ZipFormatException('read beyond end of file');
    }
    _raf.setPositionSync(offset);
    final b = _raf.readSync(n);
    if (b.length != n) throw ZipFormatException('short read');
    return b;
  }

  static List<ZipEntry> _readDirectory(RandomAccessFile raf, int length) {
    if (length < 22) throw ZipFormatException('file too small for a ZIP');
    final tailLen = length < 22 + 0xFFFF ? length : 22 + 0xFFFF;
    final tailStart = length - tailLen;
    raf.setPositionSync(tailStart);
    final tail = raf.readSync(tailLen);
    final tbd = ByteData.sublistView(tail);

    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tbd.getUint32(i, Endian.little) == 0x06054b50) {
        final commentLen = tbd.getUint16(i + 20, Endian.little);
        if (i + 22 + commentLen == tail.length) {
          eocd = i;
          break;
        }
        if (eocd < 0) eocd = i;
      }
    }
    if (eocd < 0)
      throw ZipFormatException('end of central directory not found');

    var count = tbd.getUint16(eocd + 10, Endian.little);
    var cdSize = tbd.getUint32(eocd + 12, Endian.little);
    var cdOffset = tbd.getUint32(eocd + 16, Endian.little);

    final needs64 =
        count == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF;
    final locatorAbs = tailStart + eocd - 20;
    if (locatorAbs >= 0) {
      raf.setPositionSync(locatorAbs);
      final loc = raf.readSync(20);
      final lbd = ByteData.sublistView(loc);
      if (loc.length == 20 && lbd.getUint32(0, Endian.little) == 0x07064b50) {
        final recOffset = lbd.getUint64(8, Endian.little);
        if (recOffset < 0 || recOffset + 56 > length) {
          throw ZipFormatException('bad ZIP64 end record offset');
        }
        raf.setPositionSync(recOffset);
        final rec = raf.readSync(56);
        final rbd = ByteData.sublistView(rec);
        if (rec.length != 56 || rbd.getUint32(0, Endian.little) != 0x06064b50) {
          throw ZipFormatException('bad ZIP64 end record');
        }
        count = rbd.getUint64(32, Endian.little);
        cdSize = rbd.getUint64(40, Endian.little);
        cdOffset = rbd.getUint64(48, Endian.little);
      } else if (needs64) {
        throw ZipFormatException('ZIP64 locator missing');
      }
    } else if (needs64) {
      throw ZipFormatException('ZIP64 locator missing');
    }

    if (cdOffset < 0 || cdSize < 0 || cdOffset + cdSize > length) {
      throw ZipFormatException('central directory out of range');
    }
    raf.setPositionSync(cdOffset);
    final cd = raf.readSync(cdSize);
    if (cd.length != cdSize)
      throw ZipFormatException('short central directory');
    final bd = ByteData.sublistView(cd);

    final out = <ZipEntry>[];
    var p = 0;
    for (var i = 0; i < count; i++) {
      if (p + 46 > cd.length || bd.getUint32(p, Endian.little) != 0x02014b50) {
        throw ZipFormatException('bad central directory entry #$i');
      }
      final flags = bd.getUint16(p + 8, Endian.little);
      final method = bd.getUint16(p + 10, Endian.little);
      var comp = bd.getUint32(p + 20, Endian.little);
      var size = bd.getUint32(p + 24, Endian.little);
      final n = bd.getUint16(p + 28, Endian.little);
      final x = bd.getUint16(p + 30, Endian.little);
      final c = bd.getUint16(p + 32, Endian.little);
      var lho = bd.getUint32(p + 42, Endian.little);
      if (p + 46 + n + x + c > cd.length) {
        throw ZipFormatException('truncated central directory entry #$i');
      }
      final name =
          utf8.decode(cd.sublist(p + 46, p + 46 + n), allowMalformed: true);
      // ZIP64 extra field (id 0x0001): values appear only for maxed fields.
      var q = p + 46 + n;
      final extraEnd = q + x;
      while (q + 4 <= extraEnd) {
        final id = bd.getUint16(q, Endian.little);
        final len = bd.getUint16(q + 2, Endian.little);
        if (id == 0x0001) {
          var r = q + 4;
          if (size == 0xFFFFFFFF && r + 8 <= q + 4 + len) {
            size = bd.getUint64(r, Endian.little);
            r += 8;
          }
          if (comp == 0xFFFFFFFF && r + 8 <= q + 4 + len) {
            comp = bd.getUint64(r, Endian.little);
            r += 8;
          }
          if (lho == 0xFFFFFFFF && r + 8 <= q + 4 + len) {
            lho = bd.getUint64(r, Endian.little);
          }
        }
        q += 4 + len;
      }
      out.add(ZipEntry(
        name: name,
        method: method,
        flags: flags,
        compressedSize: comp,
        size: size,
        localHeaderOffset: lho,
      ));
      p += 46 + n + x + c;
    }
    return out;
  }
}
