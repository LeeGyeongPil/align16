import 'dart:convert';

import '../explain.dart';
import '../i18n/i18n.dart';
import '../paths.dart';

/// Text output of `align16 explain`.
///
/// Candidate files under [cwd] (default: the current folder) are shown
/// relative to it, like the paths the user typed.
String renderExplainText(ExplainResult r, Messages m, {String? cwd}) {
  final b = StringBuffer();
  b.writeln(m.t('explain.title', {'name': r.name}));
  b.writeln(m.t('project', {'path': r.project}));
  b.writeln();
  if (r.special == 'engine') b.writeln(m.t('explain.engine'));
  if (r.special == 'app') b.writeln(m.t('explain.app'));
  if (r.candidates.isEmpty) {
    if (r.special == null) {
      if (r.unmapped.isNotEmpty) {
        // 캐시에서 찾았지만 어느 플러그인도 선언하지 않은 경우: 아티팩트를 보여 준다.
        b.writeln(m.t('explain.none_but_maven', {'name': r.name}));
        _writeUnmapped(b, r, m);
      } else if (r.gradleCache != null) {
        // 이미 --gradle-cache 를 줬으면 같은 옵션을 다시 권하지 않는다.
        b.writeln(
            m.t('explain.none_cache', {'name': r.name, 'path': r.gradleCache}));
      } else {
        b.writeln(m.t('explain.none', {'name': r.name}));
      }
    }
    return b.toString();
  }
  b.writeln(m.t('explain.candidates'));
  for (final c in r.candidates) {
    final kind = c.path == null
        ? m.t('explain.unreachable')
        : c.direct
            ? m.t('fix.direct')
            : m.t('fix.transitive');
    b.writeln('  ${m.t('explain.candidate', {
          'abi': c.abi,
          'package': c.package,
          'kind': kind,
          'path': c.path?.join(' -> ') ?? '-',
        })}');
    // 화면에는 현재 폴더 기준 상대경로(JSON 은 도구용이라 절대경로 그대로).
    b.writeln(
        '    ${m.t('explain.file', {'file': displayPath(c.file, from: cwd)})}');
    if (c.maven != null) {
      b.writeln('    ${m.t('explain.maven', {'maven': c.maven})}');
    }
    b.writeln('    https://pub.dev/packages/${c.package}');
  }
  final pkgs = {for (final c in r.candidates) c.package};
  if (pkgs.length > 1) {
    b.writeln();
    b.writeln(m.t('explain.ambiguous'));
  }
  if (r.unmapped.isNotEmpty) {
    b.writeln();
    b.writeln(m.t('explain.also_maven'));
    _writeUnmapped(b, r, m);
  }
  return b.toString();
}

void _writeUnmapped(StringBuffer b, ExplainResult r, Messages m) {
  for (final u in r.unmapped) {
    b.writeln('  ${m.t('explain.maven_unmapped', {
          'abi': u.abi,
          'artifact': u.artifact
        })}');
  }
  b.writeln(m.t('explain.maven_unmapped_hint'));
}

/// JSON output of `align16 explain` (language independent).
String renderExplainJson(ExplainResult r) {
  return const JsonEncoder.withIndent('  ').convert({
    'schema': 1,
    'name': r.name,
    'project': r.project,
    'special': r.special,
    'candidates': [
      for (final c in r.candidates)
        {
          'package': c.package,
          'abi': c.abi,
          'file': c.file,
          'direct': c.direct,
          'reachable': c.path != null,
          'path': c.path,
          'maven': c.maven,
        },
    ],
    'gradle_cache': r.gradleCache,
    'maven_hints': [
      for (final u in r.unmapped) {'artifact': u.artifact, 'abi': u.abi},
    ],
  });
}
