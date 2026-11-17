// Path helpers for paths the user reads: no `./` or `../` pieces, and files
// under the current folder shown relative to it.
import 'dart:io';

/// Absolute form of [path] with `.` and `..` segments removed and no trailing
/// separator (except for a file system root).
String normalizedAbsolute(String path) {
  final abs = File(path).absolute.path;
  // Uri.normalizePath 가 `.`·`..` 조각을 지운다(`/a/./b/../c` -> `/a/c`).
  var out = Uri.file(abs).normalizePath().toFilePath();
  while (out.length > 1 &&
      (out.endsWith('/') || out.endsWith(r'\')) &&
      !out.endsWith(r':\')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

/// [path] for display: relative to [from] (default: the current folder) when
/// it lies inside it, otherwise the normalized absolute path.
String displayPath(String path, {String? from}) {
  final abs = normalizedAbsolute(path);
  final base = normalizedAbsolute(from ?? Directory.current.path);
  if (abs == base) return '.';
  final sep = Platform.pathSeparator;
  final prefix = base.endsWith(sep) ? base : '$base$sep';
  // 현재 폴더 아래 파일만 상대경로로 줄인다(바깥은 `../..` 대신 절대경로).
  return abs.startsWith(prefix) ? abs.substring(prefix.length) : abs;
}
