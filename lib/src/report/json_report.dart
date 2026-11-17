// Machine-readable report. Language independent: only codes and values.
import 'dart:convert';

import '../checker.dart';
import '../verdict.dart';
import '../version.dart';

/// Builds the JSON document (`schema: 1`).
Map<String, Object?> reportToJson(Report r) {
  return {
    'schema': 1,
    'tool': 'align16',
    'version': packageVersion,
    'input': r.input,
    'kind': r.kind.name,
    'project': r.project,
    'libraries': [
      for (final v in r.libraries)
        {
          'abi': v.abi,
          'path': v.path,
          'name': v.name,
          'module': v.module,
          'status': v.status.json,
          'status_before_allow': v.statusBeforeAllow?.json,
          'min_load_align': v.minLoadAlign,
          'checks': [
            for (final c in v.checks)
              {
                'id': c.id.json,
                'status': c.status.json,
                'code': c.code,
                ...c.args,
              },
          ],
          'owner': v.owner == null
              ? null
              : {
                  'package': v.owner!.package,
                  'confidence': v.owner!.confidence.json,
                  'path': v.owner!.path,
                  'candidates': [
                    for (final c in v.owner!.candidates)
                      {'package': c.package, 'file': c.file, 'maven': c.maven},
                  ],
                  'maven_hints': v.owner!.mavenHints,
                },
        },
    ],
    'packages': [
      for (final p in r.packages)
        {
          'name': p.name,
          'direct': p.direct,
          'dev': p.dev,
          'reachable': p.path != null,
          'path': p.path,
          'confidence': p.confidence.json,
          'libraries': p.libraries,
        },
    ],
    'packaging_issue':
        r.libraries.any((v) => v.status == Status.fail && !v.elfFailed),
    'baseline_fixed': r.baselineFixed,
    'summary': {
      'checked': r.summary.checked,
      'failed': r.summary.failed,
      'allowed': r.summary.allowed,
      'warnings': r.summary.warned,
      'known': r.summary.known,
      'skipped_32bit': r.summary.skipped32bit,
      'errors': r.summary.errors,
    },
  };
}

/// Pretty-printed JSON text.
String renderJsonReport(Report r) =>
    const JsonEncoder.withIndent('  ').convert(reportToJson(r));
