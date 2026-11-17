// GitHub-flavored Markdown report, meant for `$GITHUB_STEP_SUMMARY`.
import '../attribution.dart';
import '../checker.dart';
import '../i18n/i18n.dart';
import '../verdict.dart';
import 'text_report.dart';

String _cell(String s) => s.replaceAll('|', r'\|').replaceAll('\n', ' ');

/// Builds the Markdown report.
String renderMarkdownReport(Report r, Messages m) {
  final b = StringBuffer();
  b.writeln('## ${m.t('title')}');
  b.writeln();
  b.writeln('- ${m.t('input', {'path': '`${r.input}`', 'kind': r.kind.name})}');
  if (r.project != null) {
    b.writeln('- ${m.t('project', {'path': '`${r.project}`'})}');
  }
  b.writeln();
  if (r.libraries.isEmpty) {
    b.writeln(m.t('no_libs'));
  } else {
    final showOwner = r.project != null;
    b.writeln('| ${m.t('col.abi')} | ${m.t('col.library')} | '
        '${m.t('col.status')} | ${m.t('col.detail')}${showOwner ? ' | ${m.t('fix.title')}' : ''} |');
    b.writeln('|---|---|---|---|${showOwner ? '---|' : ''}');
    for (final v in r.libraries) {
      final name = v.module != null && v.module != 'base'
          ? '${v.module}:${v.name}'
          : v.name;
      final owner = v.status != Status.ok && v.status != Status.na
          ? libraryOwner(m, v)
          : '';
      b.writeln(
          '| ${_cell(v.abi)} | `${_cell(name)}` | **${v.status.label}** | '
          '${_cell(libraryDetail(m, v))}${showOwner ? ' | ${_cell(owner)}' : ''} |');
    }
  }

  if (r.packages.isNotEmpty) {
    b.writeln();
    b.writeln('### ${m.t('fix.title')}');
    b.writeln();
    for (final p in r.packages) {
      final kind = p.path == null
          ? m.t('fix.unreachable')
          : p.direct
              ? m.t('fix.direct')
              : m.t('fix.transitive');
      final dev = p.dev ? ', ${m.t('fix.dev')}' : '';
      b.writeln('- **[${p.name}](https://pub.dev/packages/${p.name})** '
          '($kind$dev, ${m.t('fix.confidence', {
            'confidence': m.t('conf.${p.confidence.json}')
          })})');
      b.writeln('  - ${m.t('fix.libs', {
            'libs': p.libraries.map((l) => '`$l`').join(', ')
          })}');
      if (p.path != null) {
        b.writeln(
            '  - ${m.t('fix.path', {'path': '`${p.path!.join(' -> ')}`'})}');
      }
    }
  }
  final unattributed = r.libraries.any((v) =>
      v.status == Status.fail &&
      v.owner != null &&
      v.owner!.confidence == Confidence.none);
  if (unattributed) {
    b.writeln();
    b.writeln('> ${m.t('fix.unattributed')}');
    if (r.gradleCache == null) {
      b.writeln('>');
      b.writeln('> ${m.t('fix.try_gradle_cache')}');
    }
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
  if (s.known > 0) {
    b.writeln();
    b.writeln(m.t('baseline.known', {'count': s.known}));
  }
  if (r.baselineFixed.isNotEmpty) {
    b.writeln();
    b.writeln(m.t('baseline.fixed', {'libs': r.baselineFixed.join(', ')}));
  }
  if (hasAabNote(r)) {
    b.writeln();
    b.writeln('> ${m.t('note.aab')}');
  }
  final configNote = aabConfigNote(r, m);
  if (configNote != null) {
    b.writeln();
    b.writeln('> $configNote');
  }
  for (final n in packagingNotes(r, m)) {
    b.writeln();
    b.writeln('> $n');
  }
  b.writeln();
  b.writeln('**${m.t(r.exitCode == 0 ? 'result.pass' : 'result.fail')}**');
  return b.toString();
}
