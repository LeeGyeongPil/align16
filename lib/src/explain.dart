// `align16 explain`: which package could ship a library name, without any
// APK or AAB. Uses the same candidate index as attribution.
import 'artifact.dart';
import 'project/package_graph.dart';
import 'project/plugin_index.dart';

/// One package that has a file with the requested name.
class ExplainCandidate {
  const ExplainCandidate({
    required this.package,
    required this.abi,
    required this.file,
    required this.path,
    this.maven,
  });

  final String package;
  final String abi;
  final String file;

  /// Dependency path from the app, or null when unreachable.
  final List<String>? path;
  final String? maven;

  bool get direct => path != null && path!.length == 2;
}

/// Result of [explainLibrary].
class ExplainResult {
  const ExplainResult({
    required this.name,
    required this.project,
    required this.candidates,
    this.special,
    this.gradleCache,
    this.unmapped = const [],
  });

  final String name;
  final String project;
  final List<ExplainCandidate> candidates;

  /// The `--gradle-cache` folder that was searched, or null.
  final String? gradleCache;

  /// Gradle cache artifacts holding this file name that no plugin declares
  /// (hints only; they do not count as a found package).
  final List<({String artifact, String abi})> unmapped;

  /// `engine` for libflutter.so, `app` for libapp.so, otherwise null.
  final String? special;

  /// 0 when a package (or the engine / app) was found, 1 otherwise.
  /// Unmapped Gradle cache artifacts alone do not name a package, so they
  /// keep the exit code at 1.
  int get exitCode => special != null || candidates.isNotEmpty ? 0 : 1;
}

/// Looks [name] up in the project (restricted to [abis] when given).
///
/// Throws [InputError] when the project has no readable pubspec.yaml.
ExplainResult explainLibrary(
  String name,
  String projectDir, {
  Set<String>? abis,
  String? gradleCache,
}) {
  final graph = PackageGraph.load(projectDir);
  final index = PluginIndex.build(projectDir, graph, gradleCache: gradleCache);
  final special = switch (name) {
    'libflutter.so' => 'engine',
    'libapp.so' => 'app',
    _ => null,
  };
  final out = [
    for (final c in index.lookupAny(name))
      if (abis == null || abis.contains(c.abi))
        ExplainCandidate(
          package: c.package,
          abi: c.abi,
          file: c.file,
          path: graph.pathTo(c.package),
          maven: c.maven,
        ),
  ]..sort((a, b) {
      final k = a.package.compareTo(b.package);
      return k != 0 ? k : a.abi.compareTo(b.abi);
    });
  // 플러그인이 선언하지 않은 Gradle 캐시 아티팩트도 힌트로 함께 돌려준다.
  final unmapped = [
    for (final u in index.unmappedFor(name))
      if (abis == null || abis.contains(u.abi)) u,
  ];
  return ExplainResult(
    name: name,
    project: projectDir,
    candidates: out,
    special: special,
    gradleCache: gradleCache,
    unmapped: unmapped,
  );
}
