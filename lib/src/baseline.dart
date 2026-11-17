import 'dart:convert';
import 'dart:io';

import 'artifact.dart';

/// Failures recorded by an earlier `align16 check --json` run.
///
/// With `--baseline`, only failures that are not in this set count.
class Baseline {
  Baseline(this.keys);

  /// `<abi>/<library name>` of every library that was failing, allowed or
  /// already known in the baseline run.
  final Set<String> keys;

  /// Reads a JSON report written by `--json` (schema 1).
  ///
  /// Throws [InputError] (`err.baseline_read`) when it cannot be used.
  factory Baseline.load(String path) {
    try {
      final j = jsonDecode(File(path).readAsStringSync());
      if (j is! Map || j['schema'] != 1 || j['libraries'] is! List) {
        throw InputError('err.baseline_read', {'path': path});
      }
      final keys = <String>{};
      for (final l in j['libraries'] as List) {
        if (l is! Map) continue;
        final status = l['status'];
        if (status == 'fail' ||
            status == 'error' ||
            status == 'allowed' ||
            status == 'known') {
          keys.add('${l['abi']}/${l['name']}');
        }
      }
      return Baseline(keys);
    } on FileSystemException {
      throw InputError('err.baseline_read', {'path': path});
    } on FormatException {
      throw InputError('err.baseline_read', {'path': path});
    }
  }

  bool contains(String abi, String name) => keys.contains('$abi/$name');
}
