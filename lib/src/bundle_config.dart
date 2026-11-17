// Minimal protobuf reader for `BundleConfig.pb` inside an AAB.
//
// Only the path BundleConfig(2) -> Optimizations(2) -> UncompressNativeLibraries
// { enabled(1), alignment(2) } is read. Field numbers and enum values come
// from https://github.com/google/bundletool/blob/master/src/main/proto/config.proto
// (checked 2026-11-18): PAGE_ALIGNMENT_UNSPECIFIED=0, _4K=1, _16K=2, _64K=3.
import 'dart:typed_data';

/// What the bundle asks bundletool to do with native libraries.
class BundleNativeConfig {
  const BundleNativeConfig({required this.enabled, required this.alignment});

  /// `uncompress_native_libraries.enabled`.
  final bool enabled;

  /// `unspecified`, `4k`, `16k` or `64k`.
  final String alignment;
}

const _alignmentNames = {0: 'unspecified', 1: '4k', 2: '16k', 3: '64k'};

/// Parses [bytes]; returns null when there is no readable
/// `uncompress_native_libraries` message.
BundleNativeConfig? parseBundleConfig(Uint8List bytes) {
  final optimizations = _field(bytes, 2);
  if (optimizations == null) return null;
  final uncompress = _field(optimizations, 2);
  if (uncompress == null) return null;
  final enabled = _varintField(uncompress, 1) ?? 0;
  final alignment = _varintField(uncompress, 2) ?? 0;
  return BundleNativeConfig(
    enabled: enabled != 0,
    alignment: _alignmentNames[alignment] ?? 'unspecified',
  );
}

/// Iterates the fields of one message. Calls [visit] with the field number,
/// wire type and either the varint value or the payload. Returns false when
/// the data is malformed.
bool _walk(Uint8List b,
    bool Function(int field, int wire, int value, Uint8List? data) visit) {
  var p = 0;
  int? readVarint() {
    var result = 0;
    var shift = 0;
    while (p < b.length && shift < 64) {
      final byte = b[p++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
    return null;
  }

  while (p < b.length) {
    final tag = readVarint();
    if (tag == null) return false;
    final field = tag >> 3;
    final wire = tag & 7;
    switch (wire) {
      case 0:
        final v = readVarint();
        if (v == null) return false;
        if (!visit(field, wire, v, null)) return true;
      case 1:
        if (p + 8 > b.length) return false;
        p += 8;
      case 5:
        if (p + 4 > b.length) return false;
        p += 4;
      case 2:
        final len = readVarint();
        if (len == null || p + len > b.length) return false;
        final data = Uint8List.sublistView(b, p, p + len);
        p += len;
        if (!visit(field, wire, len, data)) return true;
      default:
        return false;
    }
  }
  return true;
}

Uint8List? _field(Uint8List b, int number) {
  Uint8List? found;
  _walk(b, (field, wire, value, data) {
    if (field == number && wire == 2) found = data;
    return true;
  });
  return found;
}

int? _varintField(Uint8List b, int number) {
  int? found;
  _walk(b, (field, wire, value, data) {
    if (field == number && wire == 0) found = value;
    return true;
  });
  return found;
}
