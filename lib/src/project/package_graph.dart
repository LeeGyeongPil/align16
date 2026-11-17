// Dependency graph of a Flutter project, built without running pub or flutter.
//
// Sources: `pubspec.yaml` (root name + direct deps), `.dart_tool/package_config.json`
// (package folders), each package's `pubspec.yaml` (its dependencies), and
// `.flutter-plugins-dependencies` as a fallback when package folders are gone.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../artifact.dart';

/// Package graph rooted at the app.
class PackageGraph {
  PackageGraph._({
    required this.root,
    required this.edges,
    required this.dirs,
    required this.pluginDirs,
    required this.rootDev,
  });

  /// Name of the app package.
  final String root;

  /// package -> packages it depends on (`dependencies`; the root also lists
  /// `dev_dependencies`).
  final Map<String, Set<String>> edges;

  /// package -> folder, from `package_config.json`.
  final Map<String, String> dirs;

  /// plugin -> folder, from `.flutter-plugins-dependencies` (Android plugins).
  final Map<String, String> pluginDirs;

  /// Root dependencies that come from `dev_dependencies`.
  final Set<String> rootDev;

  /// Every package name the graph knows (root excluded).
  Set<String> get packages => {
        ...edges.keys,
        for (final s in edges.values) ...s,
        ...dirs.keys,
        ...pluginDirs.keys,
      }..remove(root);

  /// Loads the graph of the project in [projectDir].
  ///
  /// Throws [InputError] (`err.no_pubspec`) when there is no readable
  /// `pubspec.yaml`.
  factory PackageGraph.load(String projectDir) {
    final pubspec = File('$projectDir/pubspec.yaml');
    if (!pubspec.existsSync()) {
      throw InputError('err.no_pubspec', {'path': projectDir});
    }
    final Object? rootDoc;
    try {
      rootDoc = loadYaml(pubspec.readAsStringSync());
    } on YamlException {
      throw InputError('err.no_pubspec', {'path': projectDir});
    }
    final rootName = rootDoc is YamlMap && rootDoc['name'] is String
        ? rootDoc['name'] as String
        : null;
    if (rootName == null) {
      throw InputError('err.no_pubspec', {'path': projectDir});
    }

    final edges = <String, Set<String>>{};
    final dirs = <String, String>{};
    final pluginDirs = <String, String>{};
    final fallback = <String, Set<String>>{};

    // Fallback: .flutter-plugins-dependencies
    final pluginsFile = File('$projectDir/.flutter-plugins-dependencies');
    if (pluginsFile.existsSync()) {
      try {
        final j = jsonDecode(pluginsFile.readAsStringSync());
        final android = j is Map && j['plugins'] is Map
            ? (j['plugins'] as Map)['android']
            : null;
        if (android is List) {
          for (final p in android) {
            if (p is Map && p['name'] is String) {
              final n = p['name'] as String;
              if (p['path'] is String) pluginDirs[n] = p['path'] as String;
              fallback[n] = {
                if (p['dependencies'] is List)
                  for (final d in p['dependencies'] as List)
                    if (d is String) d,
              };
            }
          }
        }
        if (j is Map && j['dependencyGraph'] is List) {
          for (final p in j['dependencyGraph'] as List) {
            if (p is Map && p['name'] is String) {
              fallback.putIfAbsent(
                  p['name'] as String,
                  () => {
                        if (p['dependencies'] is List)
                          for (final d in p['dependencies'] as List)
                            if (d is String) d,
                      });
            }
          }
        }
      } on FormatException {
        // A broken helper file must not stop the check.
      }
    }

    // package_config.json
    final configFile = File('$projectDir/.dart_tool/package_config.json');
    final configDir = Directory('$projectDir/.dart_tool').absolute.uri;
    if (configFile.existsSync()) {
      try {
        final j = jsonDecode(configFile.readAsStringSync());
        if (j is Map && j['packages'] is List) {
          for (final p in j['packages'] as List) {
            if (p is Map && p['name'] is String && p['rootUri'] is String) {
              final uri = configDir.resolve(p['rootUri'] as String);
              if (uri.scheme == 'file') {
                dirs[p['name'] as String] = uri.toFilePath();
              }
            }
          }
        }
      } on FormatException {
        // Treated as "no package_config".
      }
    }

    final rootDeps = _deps(rootDoc, includeDev: true);
    final rootDevSet = _devDeps(rootDoc);
    edges[rootName] = rootDeps;

    final names = {...dirs.keys, ...fallback.keys}..remove(rootName);
    for (final n in names) {
      Set<String>? deps;
      final dir = dirs[n];
      if (dir != null) {
        final f = File('$dir/pubspec.yaml');
        if (f.existsSync()) {
          try {
            deps = _deps(loadYaml(f.readAsStringSync()), includeDev: false);
          } on YamlException {
            deps = null;
          }
        }
      }
      edges[n] = deps ?? fallback[n] ?? <String>{};
    }

    return PackageGraph._(
      root: rootName,
      edges: edges,
      dirs: dirs,
      pluginDirs: pluginDirs,
      rootDev: rootDevSet,
    );
  }

  /// Builds a graph directly from edges (for tests and tools).
  factory PackageGraph.fromEdges(String root, Map<String, Set<String>> edges) {
    return PackageGraph._(
      root: root,
      edges: edges,
      dirs: const {},
      pluginDirs: const {},
      rootDev: <String>{},
    );
  }

  static Set<String> _deps(Object? doc, {required bool includeDev}) {
    final out = <String>{};
    if (doc is! YamlMap) return out;
    for (final key in [
      'dependencies',
      if (includeDev) 'dev_dependencies',
    ]) {
      final m = doc[key];
      if (m is YamlMap) {
        for (final k in m.keys) {
          if (k is String) out.add(k);
        }
      }
    }
    return out;
  }

  static Set<String> _devDeps(Object? doc) {
    final out = <String>{};
    if (doc is! YamlMap) return out;
    final runtime = _deps(doc, includeDev: false);
    final dev = doc['dev_dependencies'];
    if (dev is YamlMap) {
      for (final k in dev.keys) {
        if (k is String && !runtime.contains(k)) out.add(k);
      }
    }
    return out;
  }

  /// Shortest dependency path from the root to [name] (both included), or
  /// null when [name] cannot be reached. Safe on cyclic graphs.
  List<String>? pathTo(String name) {
    if (name == root) return [root];
    final prev = <String, String>{};
    final seen = <String>{root};
    final queue = Queue<String>()..add(root);
    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      final next = (edges[cur] ?? const <String>{}).toList()..sort();
      for (final n in next) {
        if (!seen.add(n)) continue;
        prev[n] = cur;
        if (n == name) {
          final path = <String>[n];
          var c = n;
          while (prev.containsKey(c)) {
            c = prev[c]!;
            path.add(c);
          }
          return path.reversed.toList();
        }
        queue.add(n);
      }
    }
    return null;
  }
}
