// Input handling: APK, AAB, a single .so, or a folder of .so files.
import 'dart:io';
import 'dart:typed_data';

import 'bundle_config.dart';
import 'zip_reader.dart';

/// ABI directory names Android knows about.
const List<String> knownAbis = [
  'arm64-v8a',
  'x86_64',
  'riscv64',
  'armeabi-v7a',
  'x86',
];

/// Kind of input handed to `align16 check`.
enum ArtifactKind { apk, aab, so, dir }

/// An input problem the user can fix (exit code 2). The message is looked up
/// by [key] in the message table.
class InputError implements Exception {
  InputError(this.key, [this.args = const {}]);

  final String key;
  final Map<String, Object?> args;

  @override
  String toString() => 'InputError($key, $args)';
}

/// A native library found inside an input.
class LibraryFile {
  LibraryFile({
    required this.path,
    required this.name,
    required this.read,
    this.abiHint,
    this.module,
    this.inZip = false,
    this.stored = false,
    this.zipDataOffset,
    this.isAab = false,
    this.bundle,
  });

  /// In-memory library, used by tests and the sample generator.
  LibraryFile.memory(
    String path,
    Uint8List bytes, {
    String? abiHint,
  }) : this(
          path: path,
          name: path.split('/').last,
          read: () => bytes,
          abiHint: abiHint,
        );

  /// Path shown to the user (entry name inside the archive or relative path).
  final String path;

  /// File name, e.g. `libfoo.so`.
  final String name;

  /// Loads the (uncompressed) file bytes.
  final Uint8List Function() read;

  /// ABI taken from the folder name, when it is a known ABI.
  final String? abiHint;

  /// AAB module name (`base`, a feature module), when applicable.
  final String? module;

  final bool inZip;
  final bool stored;
  final int? zipDataOffset;
  final bool isAab;

  /// `uncompress_native_libraries` settings from `BundleConfig.pb` (AAB only).
  final BundleNativeConfig? bundle;
}

/// An opened input with its libraries listed (bytes are read lazily).
class Artifact {
  Artifact({
    required this.kind,
    required this.path,
    required this.libraries,
    ZipReader? zip,
  }) : _zip = zip;

  final ArtifactKind kind;
  final String path;
  final List<LibraryFile> libraries;
  final ZipReader? _zip;

  /// Releases the archive file handle.
  void close() => _zip?.close();
}

final RegExp _apkLib = RegExp(r'^lib/([^/]+)/([^/]+\.so)$');
final RegExp _aabLib = RegExp(r'^(?:(.+)/)?lib/([^/]+)/([^/]+\.so)$');

/// Opens [path] and lists its `.so` files.
///
/// Throws [InputError] for missing files, unsupported formats and broken
/// archives.
Artifact openArtifact(String path) {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.notFound) {
    throw InputError('err.not_found', {'path': path});
  }
  if (type == FileSystemEntityType.directory) return _openDir(path);

  final head = _readHead(path);
  if (head.length >= 4 &&
      head[0] == 0x7f &&
      head[1] == 0x45 &&
      head[2] == 0x4c &&
      head[3] == 0x46) {
    final name = path.split(Platform.pathSeparator).last;
    return Artifact(
      kind: ArtifactKind.so,
      path: path,
      libraries: [
        LibraryFile(
          path: name,
          name: name,
          read: () => File(path).readAsBytesSync(),
        ),
      ],
    );
  }
  if (head.length >= 4 && head[0] == 0x50 && head[1] == 0x4b) {
    return _openZip(path);
  }
  throw InputError('err.not_zip', {'path': path});
}

Uint8List _readHead(String path) {
  final raf = File(path).openSync();
  try {
    return raf.readSync(4);
  } finally {
    raf.closeSync();
  }
}

Artifact _openDir(String path) {
  final files = <File>[];
  try {
    for (final e in Directory(path).listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.so')) files.add(e);
    }
  } on FileSystemException {
    throw InputError('err.not_found', {'path': path});
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  final base = Directory(path).absolute.path;
  final libs = <LibraryFile>[];
  for (final f in files) {
    final abs = f.absolute.path;
    var rel = abs.startsWith(base) ? abs.substring(base.length) : abs;
    rel = rel.replaceAll('\\', '/');
    if (rel.startsWith('/')) rel = rel.substring(1);
    final parts = rel.split('/');
    final parent = parts.length >= 2 ? parts[parts.length - 2] : null;
    libs.add(LibraryFile(
      path: rel,
      name: parts.last,
      read: () => f.readAsBytesSync(),
      abiHint: knownAbis.contains(parent) ? parent : null,
    ));
  }
  return Artifact(kind: ArtifactKind.dir, path: path, libraries: libs);
}

Artifact _openZip(String path) {
  final ZipReader zip;
  try {
    zip = ZipReader.open(path);
  } on ZipFormatException catch (e) {
    throw InputError('err.bad_zip', {'path': path, 'message': e.message});
  }
  final lower = path.toLowerCase();
  final isAab = lower.endsWith('.aab') ||
      (!lower.endsWith('.apk') &&
          zip.entries.any((e) => e.name.startsWith('base/')));
  BundleNativeConfig? bundle;
  if (isAab) {
    for (final e in zip.entries) {
      if (e.name == 'BundleConfig.pb') {
        try {
          bundle = parseBundleConfig(zip.readEntry(e));
        } on ZipFormatException {
          bundle = null;
        }
      }
    }
  }
  final libs = <LibraryFile>[];
  for (final e in zip.entries) {
    String? module;
    String? abi;
    String? name;
    if (isAab) {
      final m = _aabLib.firstMatch(e.name);
      if (m == null) continue;
      module = m.group(1);
      abi = m.group(2);
      name = m.group(3);
    } else {
      final m = _apkLib.firstMatch(e.name);
      if (m == null) continue;
      abi = m.group(1);
      name = m.group(2);
    }
    int? offset;
    try {
      offset = zip.dataOffsetOf(e);
    } on ZipFormatException catch (err) {
      zip.close();
      throw InputError('err.bad_zip', {'path': path, 'message': err.message});
    }
    libs.add(LibraryFile(
      path: e.name,
      name: name!,
      read: () => zip.readEntry(e),
      abiHint: abi,
      module: module,
      inZip: true,
      stored: e.isStored,
      zipDataOffset: offset,
      isAab: isAab,
      bundle: bundle,
    ));
  }
  return Artifact(
    kind: isAab ? ArtifactKind.aab : ArtifactKind.apk,
    path: path,
    libraries: libs,
    zip: zip,
  );
}
