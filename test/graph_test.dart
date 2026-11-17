import 'dart:io';

import 'package:align16/src/artifact.dart';
import 'package:align16/src/project/package_graph.dart';
import 'package:test/test.dart';

import 'helpers.dart';

late Directory tmp;

void main() {
  setUp(() => tmp = makeTemp('graph'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('shortest path: transitive and direct', () {
    final g = PackageGraph.load(makeProject(tmp, chain));
    expect(g.root, 'my_app');
    expect(g.pathTo('clip_engine_ctx'),
        ['my_app', 'clip_kit', 'clip_native', 'clip_engine_ctx']);
    expect(g.pathTo('fancy_anim'), ['my_app', 'fancy_anim']);
    expect(g.pathTo('my_app'), ['my_app']);
  });

  test('the shorter of two paths wins', () {
    final g = PackageGraph.load(makeProject(
      tmp,
      {
        'a': ['b'],
        'b': ['c'],
        'c': <String>[],
      },
      rootDeps: ['a', 'c'],
    ));
    expect(g.pathTo('c'), ['my_app', 'c']);
  });

  test('unreachable package gives null', () {
    final g = PackageGraph.load(makeProject(tmp, {
      ...chain,
      'island': <String>[],
    }));
    expect(g.pathTo('island'), isNull);
    expect(g.pathTo('does_not_exist'), isNull);
  });

  test('cycles terminate', () {
    final g = PackageGraph.load(makeProject(
      tmp,
      {
        'a': ['b'],
        'b': ['a'],
        'z': <String>[],
      },
      rootDeps: ['a'],
    ));
    expect(g.pathTo('b'), ['my_app', 'a', 'b']);
    expect(g.pathTo('z'), isNull);
  });

  test('falls back to .flutter-plugins-dependencies when folders are missing',
      () {
    final g = PackageGraph.load(
        makeProject(tmp, chain, withDirs: false, withPlugins: true));
    expect(g.pathTo('clip_engine_ctx'),
        ['my_app', 'clip_kit', 'clip_native', 'clip_engine_ctx']);
  });

  test('works with only .flutter-plugins-dependencies (no package_config)', () {
    final g = PackageGraph.load(makeProject(tmp, chain,
        withDirs: false, withConfig: false, withPlugins: true));
    expect(g.pathTo('clip_native'), ['my_app', 'clip_kit', 'clip_native']);
  });

  test('dev dependencies of the app are flagged', () {
    final g = PackageGraph.load(
        makeProject(tmp, chain, rootDevDeps: 'clip_engine_ctx'));
    expect(g.rootDev, {'clip_engine_ctx'});
    expect(g.pathTo('clip_engine_ctx'), ['my_app', 'clip_engine_ctx']);
  });

  test('missing pubspec.yaml is an input error', () {
    final dir = '${tmp.path}/empty';
    Directory(dir).createSync();
    expect(
        () => PackageGraph.load(dir),
        throwsA(
            isA<InputError>().having((e) => e.key, 'key', 'err.no_pubspec')));
  });

  test('fromEdges builds a graph directly', () {
    final g = PackageGraph.fromEdges('app', {
      'app': {'x'},
      'x': {'y'},
    });
    expect(g.pathTo('y'), ['app', 'x', 'y']);
  });
}
