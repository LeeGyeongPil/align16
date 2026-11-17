import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:align16/src/artifact.dart';
import 'package:align16/src/verdict.dart';

/// Creates a temp folder that the caller removes with [addTearDown].
Directory makeTemp(String name) {
  final base = Directory('${Directory.systemTemp.path}/align16-test');
  base.createSync(recursive: true);
  return base.createTempSync('$name-');
}

/// Evaluates in-memory ELF bytes without any archive.
LibraryVerdict eval(Uint8List bytes,
    {bool strict = false, String abi = 'arm64-v8a'}) {
  return evaluateLibrary(
    LibraryFile.memory('lib/$abi/libx.so', bytes, abiHint: abi),
    bytes,
    strict: strict,
  );
}

CheckResult checkOf(LibraryVerdict v, CheckId id) =>
    v.checks.firstWhere((c) => c.id == id);

void writeText(String path, String text) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(text);
}

void writeBytes(String path, List<int> bytes) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(bytes);
}

List<int> utf(String s) => utf8.encode(s);

/// Writes a fake project: [deps] maps package -> its dependencies.
/// With [withDirs] false the package folders do not exist.
String makeProject(
  Directory tmp,
  Map<String, List<String>> deps, {
  bool withDirs = true,
  bool withConfig = true,
  bool withPlugins = false,
  List<String> rootDeps = const ['fancy_anim', 'clip_kit'],
  String rootDevDeps = '',
}) {
  final proj = '${tmp.path}/my_app';
  writeText('$proj/pubspec.yaml', '''
name: my_app
dependencies:
${rootDeps.map((d) => '  $d: any').join('\n')}
${rootDevDeps.isEmpty ? '' : 'dev_dependencies:\n  $rootDevDeps: any'}
''');
  if (withConfig) {
    writeText(
      '$proj/.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final n in deps.keys)
            {'name': n, 'rootUri': '../../pkgs/$n', 'packageUri': 'lib/'},
          {'name': 'my_app', 'rootUri': '../', 'packageUri': 'lib/'},
        ],
      }),
    );
  }
  if (withDirs) {
    deps.forEach((n, d) => writeText('${tmp.path}/pkgs/$n/pubspec.yaml',
        'name: $n\ndependencies:\n${d.map((x) => '  $x: any').join('\n')}\n'));
  }
  if (withPlugins) {
    writeText(
      '$proj/.flutter-plugins-dependencies',
      jsonEncode({
        'plugins': {
          'android': [
            for (final e in deps.entries)
              {
                'name': e.key,
                'path': '${tmp.path}/pkgs/${e.key}/',
                'dependencies': e.value,
              },
          ],
        },
      }),
    );
  }
  return proj;
}

const chain = {
  'fancy_anim': <String>[],
  'clip_kit': ['clip_native'],
  'clip_native': ['clip_engine_ctx'],
  'clip_engine_ctx': <String>[],
};
