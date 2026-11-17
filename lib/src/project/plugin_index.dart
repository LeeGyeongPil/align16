// Finds which package could own a `.so` file name.
//
// Candidate sources, in priority order:
//  1. `<project>/build/<plugin>/intermediates/**/<abi>/*.so`
//  2. `<plugin dir>/android/**/<abi>/*.so` (the plugin's own build folder when
//     the build output was not relocated, and bundled `jniLibs`).
//  3. Optional `--gradle-cache <dir>`: extracted AARs under
//     `transforms-*/<hash>/transformed/<artifact-version>/jni/<abi>/*.so`,
//     mapped to pub packages through the Maven coordinates declared in each
//     plugin's `android/build.gradle(.kts)`.
import 'dart:io';

import '../artifact.dart';
import '../paths.dart';
import 'package_graph.dart';

/// One file that a package could have contributed.
class Candidate {
  const Candidate({
    required this.package,
    required this.abi,
    required this.file,
    this.maven,
  });

  final String package;

  /// Gradle cache artifact folder this file came from, when applicable.
  final String? maven;
  final String abi;

  /// Absolute path of the candidate file.
  final String file;
}

/// `.so` file name -> candidates.
class PluginIndex {
  PluginIndex(this.byName, [this.unmappedMaven = const {}]);

  final Map<String, List<Candidate>> byName;

  /// file name -> `<artifact>|<abi>` of Gradle cache files that no pub package
  /// claims (shown as hints only).
  final Map<String, Set<String>> unmappedMaven;

  /// Scans the project once. [gradleCache] enables step 3.
  factory PluginIndex.build(
    String projectDir,
    PackageGraph graph, {
    String? gradleCache,
  }) {
    // 잘못된 캐시 경로를 "AAR 없음" 으로 조용히 넘기지 않는다(CI 오타 방지).
    if (gradleCache != null) requireGradleCache(gradleCache);
    final byName = <String, List<Candidate>>{};
    final seen = <String>{};
    final known = graph.packages;

    void add(String package, File f) {
      final parts = f.path.replaceAll('\\', '/').split('/');
      if (parts.length < 2) return;
      final abi = parts[parts.length - 2];
      if (!knownAbis.contains(abi)) return;
      // `--project ./my_app` 이어도 `/./` 없는 경로로 보관·표시한다.
      final abs = normalizedAbsolute(f.path);
      if (!seen.add('$package|$abs')) return;
      byName
          .putIfAbsent(parts.last, () => [])
          .add(Candidate(package: package, abi: abi, file: abs));
    }

    // 1. project build folder, one sub folder per plugin
    final build = Directory('$projectDir/build');
    if (build.existsSync()) {
      final plugins = _safeList(build).whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final d in plugins) {
        final name = d.path.replaceAll('\\', '/').split('/').last;
        if (!known.contains(name)) continue;
        final inter = Directory('${d.path}/intermediates');
        if (!inter.existsSync()) continue;
        for (final f in _soFiles(inter)) {
          add(name, f);
        }
      }
    }

    // 2. plugin folders (own build output and jniLibs)
    final dirs = {...graph.dirs, ...graph.pluginDirs};
    final names = dirs.keys.toList()..sort();
    for (final n in names) {
      final android = Directory('${dirs[n]}/android');
      if (!android.existsSync()) continue;
      for (final f in _soFiles(android)) {
        add(n, f);
      }
    }

    // 3. Gradle cache (extracted AARs)
    final unmapped = <String, Set<String>>{};
    if (gradleCache != null) {
      final hints = mavenHints(graph);
      for (final root in _gradleRoots(gradleCache)) {
        for (final f in _soFiles(root)) {
          final parts = f.path.replaceAll('\\', '/').split('/');
          if (parts.length < 2 ||
              !knownAbis.contains(parts[parts.length - 2])) {
            continue;
          }
          final artifact = gradleArtifactOf(parts);
          if (artifact == null) continue;
          final pkgs = <String>{};
          hints.forEach((coord, packages) {
            if (_artifactMatches(artifact, coord)) pkgs.addAll(packages);
          });
          if (pkgs.isEmpty) {
            unmapped
                .putIfAbsent(parts.last, () => {})
                .add('$artifact|${parts[parts.length - 2]}');
            continue;
          }
          for (final p in pkgs.toList()..sort()) {
            final abs = normalizedAbsolute(f.path);
            if (!seen.add('$p|$abs')) continue;
            byName.putIfAbsent(parts.last, () => []).add(Candidate(
                package: p,
                abi: parts[parts.length - 2],
                file: abs,
                maven: artifact));
          }
        }
      }
    }
    return PluginIndex(byName, unmapped);
  }

  /// Gradle cache artifacts that contain this file name but that no pub
  /// package declares, as `(artifact, abi)` pairs sorted by artifact then ABI.
  List<({String artifact, String abi})> unmappedFor(String name) {
    final out = [
      for (final h in unmappedMaven[name] ?? const <String>{})
        (
          artifact: h.substring(0, h.lastIndexOf('|')),
          abi: h.substring(h.lastIndexOf('|') + 1),
        ),
    ]..sort((a, b) {
        final k = a.artifact.compareTo(b.artifact);
        return k != 0 ? k : a.abi.compareTo(b.abi);
      });
    return out;
  }

  /// Candidates with this file name in any ABI.
  List<Candidate> lookupAny(String name) => byName[name] ?? const [];

  /// Candidates with this file name in this ABI.
  List<Candidate> lookup(String name, String abi) => [
        for (final c in byName[name] ?? const <Candidate>[])
          if (c.abi == abi) c,
      ];
}

List<FileSystemEntity> _safeList(Directory d) {
  try {
    return d.listSync();
  } on FileSystemException {
    return const [];
  }
}

Iterable<File> _soFiles(Directory root) sync* {
  final List<FileSystemEntity> all;
  try {
    all = root.listSync(recursive: true, followLinks: false);
  } on FileSystemException {
    return;
  }
  final files = all
      .whereType<File>()
      .where((f) => f.path.endsWith('.so'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  yield* files;
}

final RegExp _coordinate = RegExp(
    '[\'"]([A-Za-z0-9_.\\-]+):([A-Za-z0-9_.\\-]+):([^\'":\\s)\$]+)[\'"]');

/// Maven artifact id -> pub packages that declare a dependency on it in
/// `android/build.gradle` or `android/build.gradle.kts`.
Map<String, Set<String>> mavenHints(PackageGraph graph) {
  final out = <String, Set<String>>{};
  final dirs = {...graph.dirs, ...graph.pluginDirs};
  for (final e in dirs.entries) {
    for (final name in ['build.gradle', 'build.gradle.kts']) {
      final f = File('${e.value}/android/$name');
      if (!f.existsSync()) continue;
      String text;
      try {
        text = f.readAsStringSync();
      } on FileSystemException {
        continue;
      }
      for (final m in _coordinate.allMatches(text)) {
        out.putIfAbsent(m.group(2)!, () => {}).add(e.key);
      }
    }
  }
  return out;
}

/// Artifact folder name for a Gradle cache path (`transformed/<artifact>/...`
/// or the folder above `jni`).
String? gradleArtifactOf(List<String> parts) {
  final t = parts.indexOf('transformed');
  if (t >= 0 && t + 1 < parts.length - 1) return parts[t + 1];
  final j = parts.indexOf('jni');
  if (j > 0) return parts[j - 1];
  return null;
}

bool _artifactMatches(String folder, String artifactId) {
  var f = folder;
  if (f.startsWith('jetified-')) f = f.substring(9);
  if (f == artifactId) return true;
  if (!f.startsWith('$artifactId-')) return false;
  final next = f.codeUnitAt(artifactId.length + 1);
  return next >= 0x30 && next <= 0x39;
}

/// Throws [InputError] (`err.gradle_cache`) when [path] is not a folder.
void requireGradleCache(String path) {
  if (!Directory(path).existsSync()) {
    throw InputError('err.gradle_cache', {'path': path});
  }
}

List<Directory> _gradleRoots(String path) {
  final root = Directory(path);
  if (!root.existsSync()) return const [];
  final transforms = _safeList(root)
      .whereType<Directory>()
      .where((d) =>
          d.path.split(Platform.pathSeparator).last.startsWith('transforms'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return transforms.isEmpty ? [root] : transforms;
}
