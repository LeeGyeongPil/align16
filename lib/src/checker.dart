// Orchestration: open the input, check every library, attribute failures.
import 'dart:typed_data';

import 'allowlist.dart';
import 'artifact.dart';
import 'attribution.dart';
import 'baseline.dart';
import 'project/package_graph.dart';
import 'project/plugin_index.dart';
import 'verdict.dart';

/// Options of one check run.
class CheckOptions {
  CheckOptions({
    this.abis,
    Allowlist? allow,
    this.strict = false,
    this.projectDir,
    this.gradleCache,
    this.baseline,
  }) : allow = allow ?? Allowlist.empty();

  /// Restrict to these ABIs; null checks everything found.
  final Set<String>? abis;
  final Allowlist allow;
  final bool strict;

  /// Flutter project root used for attribution.
  final String? projectDir;

  /// Gradle caches folder searched for extracted AAR libraries.
  final String? gradleCache;

  /// Earlier failures that must not fail this run.
  final Baseline? baseline;
}

/// A package blamed for failing libraries.
class PackageFinding {
  PackageFinding({
    required this.name,
    required this.path,
    required this.dev,
    required this.confidence,
  });

  final String name;

  /// Dependency path from the app, or null when unreachable.
  final List<String>? path;

  /// True when the app lists it only under `dev_dependencies`.
  final bool dev;

  /// Strongest confidence among its libraries.
  final Confidence confidence;

  /// `<abi>/<name>` of the failing libraries.
  final List<String> libraries = [];

  bool get direct => path != null && path!.length == 2;
}

/// Counts shown in the summary line and `--json`.
class Summary {
  const Summary({
    required this.checked,
    required this.failed,
    required this.allowed,
    required this.warned,
    this.known = 0,
    required this.skipped32bit,
    required this.errors,
  });

  final int checked;
  final int failed;
  final int allowed;
  final int warned;

  /// Failures present in the baseline (not counted as failed).
  final int known;
  final int skipped32bit;
  final int errors;
}

/// Complete result of a run.
class Report {
  Report({
    required this.kind,
    required this.input,
    required this.project,
    required this.libraries,
    required this.packages,
    this.baselineFixed = const [],
    this.gradleCache,
  });

  /// The `--gradle-cache` folder that was searched, or null.
  final String? gradleCache;

  final ArtifactKind kind;
  final String input;
  final String? project;
  final List<LibraryVerdict> libraries;
  final List<PackageFinding> packages;

  /// `<abi>/<name>` that failed in the baseline but no longer does.
  final List<String> baselineFixed;

  Summary get summary => Summary(
        checked: libraries.where((l) => l.is64).length,
        failed: libraries.where((l) => l.status == Status.fail).length,
        allowed: libraries.where((l) => l.status == Status.allowed).length,
        warned: libraries.where((l) => l.status == Status.warn).length,
        known: libraries.where((l) => l.status == Status.known).length,
        skipped32bit: libraries.where((l) => !l.is64).length,
        errors: libraries.where((l) => l.status == Status.error).length,
      );

  /// 0 when nothing failed, 1 otherwise.
  int get exitCode => summary.failed + summary.errors > 0 ? 1 : 0;
}

/// Checks [path] (APK, AAB, `.so` or folder).
///
/// Throws [InputError] for problems the user must fix (exit code 2).
Report checkArtifact(String path, [CheckOptions? options]) {
  final opts = options ?? CheckOptions();

  // --gradle-cache 경로 오타는 --project 가 없어도 바로 알린다.
  if (opts.gradleCache != null) requireGradleCache(opts.gradleCache!);

  PackageGraph? graph;
  PluginIndex? index;
  final project = opts.projectDir;
  if (project != null) {
    graph = PackageGraph.load(project);
    index = PluginIndex.build(project, graph, gradleCache: opts.gradleCache);
  }

  final artifact = openArtifact(path);
  if (artifact.kind == ArtifactKind.dir && artifact.libraries.isEmpty) {
    artifact.close();
    throw InputError('err.empty_dir', {'path': path});
  }
  final verdicts = <LibraryVerdict>[];
  try {
    for (final lib in artifact.libraries) {
      final hint = lib.abiHint;
      if (opts.abis != null && hint != null && !opts.abis!.contains(hint)) {
        continue;
      }
      LibraryVerdict v;
      Uint8List bytes;
      try {
        bytes = lib.read();
      } on Object catch (e) {
        v = LibraryVerdict(
          path: lib.path,
          name: lib.name,
          module: lib.module,
          abi: hint ?? 'unknown',
          status: Status.error,
          checks: [
            CheckResult(CheckId.loadAlign, Status.error, 'read_failed',
                {'message': '$e'}),
          ],
        );
        _finish(v, opts, null, null, null);
        verdicts.add(v);
        continue;
      }
      v = evaluateLibrary(lib, bytes, strict: opts.strict);
      if (opts.abis != null && !opts.abis!.contains(v.abi)) continue;
      _finish(v, opts, bytes, graph, index);
      verdicts.add(v);
    }
  } finally {
    artifact.close();
  }

  final fixed = <String>[];
  final baseline = opts.baseline;
  if (baseline != null) {
    final current = {
      for (final v in verdicts)
        if (v.status != Status.ok &&
            v.status != Status.na &&
            v.status != Status.warn)
          '${v.abi}/${v.name}',
    };
    for (final k in baseline.keys) {
      if (current.contains(k)) continue;
      final abi = k.substring(0, k.indexOf('/'));
      if (opts.abis != null && !opts.abis!.contains(abi)) continue;
      fixed.add(k);
    }
    fixed.sort();
  }

  return Report(
    kind: artifact.kind,
    input: path,
    project: project,
    libraries: verdicts,
    packages: graph == null ? const [] : _findings(verdicts, graph),
    baselineFixed: fixed,
    gradleCache: opts.gradleCache,
  );
}

void _finish(
  LibraryVerdict v,
  CheckOptions opts,
  Uint8List? bytes,
  PackageGraph? graph,
  PluginIndex? index,
) {
  if ((v.status == Status.fail || v.status == Status.error) &&
      opts.allow.matches(v.abi, v.name)) {
    v.statusBeforeAllow = v.status;
    v.status = Status.allowed;
  } else if ((v.status == Status.fail || v.status == Status.error) &&
      opts.baseline != null &&
      opts.baseline!.contains(v.abi, v.name)) {
    v.statusBeforeAllow = v.status;
    v.status = Status.known;
  }
  if (bytes != null && graph != null && index != null && v.is64) {
    v.owner = attribute(
      name: v.name,
      abi: v.abi,
      bytes: bytes,
      index: index,
      graph: graph,
    );
  }
}

const _rank = {
  Confidence.exact: 0,
  Confidence.name: 1,
  Confidence.ambiguous: 2,
};

List<PackageFinding> _findings(
    List<LibraryVerdict> verdicts, PackageGraph graph) {
  final byName = <String, PackageFinding>{};
  for (final v in verdicts) {
    if (v.status != Status.fail || v.owner == null || !v.elfFailed) continue;
    final owner = v.owner!;
    for (final p in owner.packages) {
      final f = byName.putIfAbsent(
        p,
        () => PackageFinding(
          name: p,
          path: graph.pathTo(p),
          dev: graph.rootDev.contains(p),
          confidence: owner.confidence,
        ),
      );
      f.libraries.add('${v.abi}/${v.name}');
    }
  }
  // Keep the strongest confidence per package.
  final out = <PackageFinding>[];
  for (final f in byName.values) {
    var best = f.confidence;
    for (final v in verdicts) {
      final o = v.owner;
      if (v.status == Status.fail &&
          v.elfFailed &&
          o != null &&
          o.packages.contains(f.name) &&
          (_rank[o.confidence] ?? 9) < (_rank[best] ?? 9)) {
        best = o.confidence;
      }
    }
    final merged = PackageFinding(
      name: f.name,
      path: f.path,
      dev: f.dev,
      confidence: best,
    )..libraries.addAll(f.libraries);
    out.add(merged);
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}
