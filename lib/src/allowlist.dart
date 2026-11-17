import 'dart:io';

import 'artifact.dart';

/// Libraries the user accepts as failing (for example 32-bit-only upstream
/// leftovers). One entry per line: `libname.so` or `<abi>/libname.so`; `#`
/// starts a comment.
class Allowlist {
  Allowlist(this._entries);

  /// Allows nothing.
  Allowlist.empty() : _entries = const {};

  final Set<String> _entries;

  bool get isEmpty => _entries.isEmpty;

  /// Parses the text of an allow-list file.
  factory Allowlist.parse(String text) {
    final entries = <String>{};
    for (var line in text.split('\n')) {
      final hash = line.indexOf('#');
      if (hash >= 0) line = line.substring(0, hash);
      line = line.trim().replaceAll('\\', '/');
      if (line.isEmpty) continue;
      final parts = line.split('/');
      if (parts.length >= 2) {
        entries.add('${parts[parts.length - 2]}/${parts.last}');
      } else {
        entries.add(parts.last);
      }
    }
    return Allowlist(entries);
  }

  /// Reads an allow-list file; throws [InputError] when it cannot be read.
  factory Allowlist.load(String path) {
    try {
      return Allowlist.parse(File(path).readAsStringSync());
    } on FileSystemException {
      throw InputError('err.allow_read', {'path': path});
    }
  }

  /// Whether `<abi>/<name>` or plain `<name>` is allowed.
  bool matches(String abi, String name) =>
      _entries.contains(name) || _entries.contains('$abi/$name');
}
