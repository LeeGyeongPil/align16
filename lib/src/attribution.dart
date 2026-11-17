// Decides which package most likely brought a library in, and says how sure
// it is. It never guesses: no candidate means `none`.
import 'dart:io';
import 'dart:typed_data';

import 'project/package_graph.dart';
import 'project/plugin_index.dart';

/// How the owner was determined.
enum Confidence {
  /// Bytes in the artifact equal the bytes of exactly one package's file.
  exact('exact'),

  /// Only one package has a file with this name (bytes differ or unknown).
  name('name'),

  /// Several packages have the name and no byte match; all are listed.
  ambiguous('ambiguous'),

  /// No candidate file found.
  none('none'),

  /// `libflutter.so`.
  engine('engine'),

  /// `libapp.so`.
  app('app');

  const Confidence(this.json);
  final String json;
}

/// A candidate package for display.
class OwnerCandidate {
  const OwnerCandidate(this.package, this.file, [this.maven]);

  final String package;
  final String file;

  /// Gradle cache artifact the file came from, when applicable.
  final String? maven;
}

/// Attribution result for one library.
class Owner {
  const Owner({
    required this.confidence,
    this.package,
    this.path,
    this.candidates = const [],
    this.mavenHints = const [],
  });

  final Confidence confidence;

  /// Package name for exact/name; null otherwise.
  final String? package;

  /// Dependency path root -> package (null when unreachable or not applicable).
  final List<String>? path;
  final List<OwnerCandidate> candidates;

  /// Gradle cache artifacts that carry this library but that no pub package
  /// claims (only for [Confidence.none]).
  final List<String> mavenHints;

  /// Packages to blame: the owner, or every candidate when ambiguous.
  List<String> get packages {
    if (package != null) return [package!];
    if (confidence == Confidence.ambiguous) {
      return {for (final c in candidates) c.package}.toList()..sort();
    }
    return const [];
  }
}

/// Attributes one library named [name] for [abi] whose bytes are [bytes].
Owner attribute({
  required String name,
  required String abi,
  required Uint8List bytes,
  required PluginIndex index,
  required PackageGraph graph,
}) {
  if (name == 'libflutter.so')
    return const Owner(confidence: Confidence.engine);
  if (name == 'libapp.so') return const Owner(confidence: Confidence.app);

  final cands = index.lookup(name, abi);
  if (cands.isEmpty) {
    final hints = [
      for (final h in index.unmappedMaven[name] ?? const <String>{})
        if (h.endsWith('|$abi')) h.substring(0, h.length - abi.length - 1),
    ]..sort();
    return Owner(confidence: Confidence.none, mavenHints: hints);
  }

  final all = [
    for (final c in cands) OwnerCandidate(c.package, c.file, c.maven),
  ];

  final exact = <Candidate>[
    for (final c in cands)
      if (_sameBytes(c.file, bytes)) c,
  ];
  final exactPkgs = {for (final c in exact) c.package};
  if (exactPkgs.length == 1) {
    final p = exactPkgs.first;
    return Owner(
      confidence: Confidence.exact,
      package: p,
      path: graph.pathTo(p),
      candidates: [
        for (final c in exact) OwnerCandidate(c.package, c.file, c.maven),
      ],
    );
  }
  if (exactPkgs.length > 1) {
    return Owner(
      confidence: Confidence.ambiguous,
      candidates: [
        for (final c in exact) OwnerCandidate(c.package, c.file, c.maven),
      ],
    );
  }

  final pkgs = {for (final c in cands) c.package};
  if (pkgs.length == 1) {
    final p = pkgs.first;
    return Owner(
      confidence: Confidence.name,
      package: p,
      path: graph.pathTo(p),
      candidates: all,
    );
  }
  return Owner(confidence: Confidence.ambiguous, candidates: all);
}

bool _sameBytes(String file, Uint8List bytes) {
  try {
    final f = File(file);
    if (f.lengthSync() != bytes.length) return false;
    final other = f.readAsBytesSync();
    for (var i = 0; i < bytes.length; i++) {
      if (other[i] != bytes[i]) return false;
    }
    return true;
  } on FileSystemException {
    return false;
  }
}
