// Human-readable report (English or Korean table + "packages to fix").
import '../artifact.dart';
import '../attribution.dart';
import '../checker.dart';
import '../i18n/i18n.dart';
import '../verdict.dart';

/// Terminal display width: East Asian wide characters count as 2.
int displayWidth(String s) {
  var w = 0;
  for (final r in s.runes) {
    final wide = (r >= 0x1100 && r <= 0x115F) ||
        (r >= 0x2E80 && r <= 0xA4CF) ||
        (r >= 0xAC00 && r <= 0xD7A3) ||
        (r >= 0xF900 && r <= 0xFAFF) ||
        (r >= 0xFE30 && r <= 0xFE6F) ||
        (r >= 0xFF00 && r <= 0xFF60) ||
        (r >= 0xFFE0 && r <= 0xFFE6);
    w += wide ? 2 : 1;
  }
  return w;
}

String _pad(String s, int width) {
  final gap = width - displayWidth(s);
  return gap > 0 ? s + ' ' * gap : s;
}

String _hex(Object? v) => '0x${(v as int).toRadixString(16)}';

/// Renders one check result as a sentence fragment.
String describeCheck(Messages m, CheckResult c) {
  final args = Map<String, Object?>.from(c.args);
  for (final k in ['align', 'need', 'end']) {
    if (args[k] is int) args[k] = _hex(args[k]);
  }
  return m.t('detail.${c.code}', args);
}

/// Detail text of a library row (problems joined by `;`).
String libraryDetail(Messages m, LibraryVerdict v) {
  final parts = <String>[];
  switch (v.status) {
    case Status.ok:
      parts.add(describeCheck(m, v.checks.first));
    case Status.na:
      parts.add(describeCheck(m, v.checks.first));
    case Status.fail ||
          Status.warn ||
          Status.error ||
          Status.allowed ||
          Status.known:
      for (final c in v.checks) {
        if (c.status == Status.fail ||
            c.status == Status.warn ||
            c.status == Status.error) {
          parts.add(describeCheck(m, c));
        }
      }
      if (v.status == Status.allowed) parts.add(m.t('detail.allowed'));
      if (v.status == Status.known) parts.add(m.t('detail.known'));
  }
  return parts.join('; ');
}

/// Owner text (`<- package ...`) of a library row, empty without `--project`.
String libraryOwner(Messages m, LibraryVerdict v) {
  final o = v.owner;
  if (o == null) return '';
  switch (o.confidence) {
    case Confidence.exact:
    case Confidence.name:
      final path =
          o.path == null ? m.t('owner.unreachable') : o.path!.join(' -> ');
      return m.t(
          'owner.${o.confidence.json}', {'package': o.package, 'path': path});
    case Confidence.ambiguous:
      return m.t('owner.ambiguous', {'packages': o.packages.join(', ')});
    case Confidence.none:
      if (o.mavenHints.isNotEmpty) {
        return m.t('owner.none_maven', {'artifacts': o.mavenHints.join(', ')});
      }
      return m.t('owner.none');
    case Confidence.engine:
      return m.t('owner.engine');
    case Confidence.app:
      return m.t('owner.app');
  }
}

String _paint(String text, Status s, bool color) {
  if (!color) return text;
  final code = switch (s) {
    Status.ok => '32',
    Status.fail || Status.error => '31',
    Status.warn || Status.allowed || Status.known => '33',
    Status.na => '90',
  };
  return '\x1b[${code}m$text\x1b[0m';
}

/// Builds the full text report.
String renderTextReport(
  Report r,
  Messages m, {
  bool color = false,
}) {
  final b = StringBuffer();
  b.writeln(m.t('title'));
  b.writeln(m.t('input', {'path': r.input, 'kind': r.kind.name}));
  if (r.project != null) b.writeln(m.t('project', {'path': r.project}));
  b.writeln();

  if (r.libraries.isEmpty) {
    b.writeln(m.t('no_libs'));
  } else {
    final rows = <List<String>>[];
    for (final v in r.libraries) {
      final name = v.module != null && v.module != 'base'
          ? '${v.module}:${v.name}'
          : v.name;
      final showOwner = v.status != Status.ok && v.status != Status.na;
      var detail = libraryDetail(m, v);
      final owner = showOwner ? libraryOwner(m, v) : '';
      if (owner.isNotEmpty) detail = '$detail  $owner';
      rows.add([v.abi, name, v.status.label, detail]);
    }
    final head = [
      m.t('col.abi'),
      m.t('col.library'),
      m.t('col.status'),
      m.t('col.detail'),
    ];
    final w = List<int>.generate(
      3,
      (i) => [head[i], ...rows.map((x) => x[i])]
          .map(displayWidth)
          .reduce((a, c) => a > c ? a : c),
    );
    String line(List<String> cells, {Status? status}) {
      final status3 = _pad(cells[2], w[2]);
      return '${_pad(cells[0], w[0])}  ${_pad(cells[1], w[1])}  '
          '${status == null ? status3 : _paint(status3, status, color)}  '
          '${cells[3]}';
    }

    b.writeln(line(head));
    for (var i = 0; i < rows.length; i++) {
      b.writeln(line(rows[i], status: r.libraries[i].status));
    }
  }

  if (r.packages.isNotEmpty) {
    b.writeln();
    b.writeln('${m.t('fix.title')}:');
    for (final p in r.packages) {
      final kind = p.path == null
          ? m.t('fix.unreachable')
          : p.direct
              ? m.t('fix.direct')
              : m.t('fix.transitive');
      final dev = p.dev ? ', ${m.t('fix.dev')}' : '';
      b.writeln('  ${p.name} ($kind$dev)  '
          '[${m.t('fix.confidence', {
            'confidence': m.t('conf.${p.confidence.json}')
          })}]');
      b.writeln('    ${m.t('fix.libs', {'libs': p.libraries.join(', ')})}');
      if (p.path != null) {
        b.writeln('    ${m.t('fix.path', {'path': p.path!.join(' -> ')})}');
      }
      b.writeln('    https://pub.dev/packages/${p.name}');
      if (p.confidence == Confidence.ambiguous) {
        b.writeln('    ${m.t('fix.hint_ambiguous')}');
      } else if (p.path != null && p.direct) {
        b.writeln('    ${m.t('fix.hint_direct')}');
      } else if (p.path != null) {
        b.writeln('    ${m.t('fix.hint_transitive', {'top': p.path![1]})}');
      }
    }
  }

  final unattributed = r.libraries.any((v) =>
      v.status == Status.fail &&
      v.owner != null &&
      v.owner!.confidence == Confidence.none);
  if (unattributed) {
    b.writeln();
    b.writeln(m.t('fix.unattributed'));
    // 캐시를 이미 줬으면 같은 옵션을 다시 권하지 않는다.
    if (r.gradleCache == null) b.writeln(m.t('fix.try_gradle_cache'));
  }

  final s = r.summary;
  b.writeln();
  b.writeln(m.t('summary', {
    'checked': s.checked,
    'failed': s.failed,
    'allowed': s.allowed,
    'warned': s.warned,
    'skipped': s.skipped32bit,
    'errors': s.errors,
  }));
  if (s.known > 0) b.writeln(m.t('baseline.known', {'count': s.known}));
  if (r.baselineFixed.isNotEmpty) {
    b.writeln(m.t('baseline.fixed', {'libs': r.baselineFixed.join(', ')}));
  }
  if (hasAabNote(r)) b.writeln(m.t('note.aab'));
  final configNote = aabConfigNote(r, m);
  if (configNote != null) b.writeln(configNote);
  for (final n in packagingNotes(r, m)) {
    b.writeln(n);
  }
  if (r.project == null && (s.failed > 0)) b.writeln(m.t('note.no_project'));
  b.writeln(m.t(r.exitCode == 0 ? 'result.pass' : 'result.fail'));
  return b.toString();
}

/// Notes for failures that only the app's own packaging can fix (zip offset
/// or bundle config). One note per kind, never one per package.
List<String> packagingNotes(Report r, Messages m) {
  final zipOnly =
      r.libraries.where((v) => v.status == Status.fail && !v.elfFailed);
  final aab4k =
      zipOnly.any((v) => v.checks.any((c) => c.code == 'aab_config_4k'));
  final apkZip = zipOnly.any((v) => v.checks.any((c) => c.code == 'zip_align'));
  return [
    if (apkZip) m.t('note.packaging'),
    if (aab4k) m.t('note.packaging_aab'),
  ];
}

/// The bundle config note (`16K` / `64K`) when an AAB's BundleConfig.pb asks
/// for 16 KB or larger native library alignment, otherwise null. Shown once,
/// because OK rows only print their LOAD alignment.
String? aabConfigNote(Report r, Messages m) {
  for (final v in r.libraries) {
    for (final c in v.checks) {
      if (c.code == 'aab_config_ok') {
        return m.t('note.aab_config_ok', {'alignment': c.args['alignment']});
      }
    }
  }
  return null;
}

/// True when an AAB library had its zip alignment left unchecked.
bool hasAabNote(Report r) =>
    r.kind == ArtifactKind.aab &&
    r.libraries.any((v) => v.checks.any((c) => c.code == 'aab'));
