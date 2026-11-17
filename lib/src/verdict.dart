// Verdict model and the per-library checks.
import 'dart:typed_data';

import 'artifact.dart';
import 'attribution.dart';
import 'elf.dart';

/// Individual check kinds. [json] is the stable code used in `--json`.
enum CheckId {
  loadAlign('load-align'),
  relro('relro'),
  congruence('congruence'),
  zipAlign('zip-align');

  const CheckId(this.json);
  final String json;
}

/// Result states. [json] is the stable, language-independent code.
enum Status {
  ok('ok', 'OK'),
  fail('fail', 'FAIL'),
  warn('warn', 'WARN'),
  na('na', 'N/A'),
  error('error', 'ERROR'),
  allowed('allowed', 'ALLOWED'),
  known('known', 'KNOWN');

  const Status(this.json, this.label);
  final String json;
  final String label;
}

/// One check outcome. [code] selects a detail message, [args] fill it in.
class CheckResult {
  CheckResult(this.id, this.status, this.code, [this.args = const {}]);

  final CheckId id;
  final Status status;
  final String code;
  final Map<String, Object?> args;
}

/// All outcomes for one library file.
class LibraryVerdict {
  LibraryVerdict({
    required this.path,
    required this.name,
    required this.abi,
    required this.status,
    required this.checks,
    this.module,
    this.minLoadAlign,
    this.is64 = true,
  });

  final String path;
  final String name;
  final String abi;
  final String? module;
  final int? minLoadAlign;
  final bool is64;
  final List<CheckResult> checks;

  /// Overall status (may become [Status.allowed] after the allow list).
  Status status;

  /// Overall status before the allow list was applied.
  Status? statusBeforeAllow;

  /// Filled in when `--project` is given.
  Owner? owner;

  /// True when an ELF check (not the zip offset or bundle config) failed or
  /// the file could not be read. Only these can be fixed in a package.
  bool get elfFailed => checks.any((c) =>
      c.id != CheckId.zipAlign &&
      (c.status == Status.fail || c.status == Status.error));

  /// Checks that are not OK/N/A, in order.
  Iterable<CheckResult> get problems =>
      checks.where((c) => c.status != Status.ok && c.status != Status.na);
}

/// Runs every check on one library.
///
/// [bytes] are the uncompressed file contents. Never throws for bad input;
/// broken files get [Status.error].
LibraryVerdict evaluateLibrary(
  LibraryFile lib,
  Uint8List bytes, {
  bool strict = false,
}) {
  final ElfInfo info;
  try {
    info = parseElf(bytes);
  } on ElfFormatException catch (e) {
    return LibraryVerdict(
      path: lib.path,
      name: lib.name,
      module: lib.module,
      abi: lib.abiHint ?? 'unknown',
      status: Status.error,
      checks: [CheckResult(CheckId.loadAlign, Status.error, e.code)],
    );
  }
  final abi = lib.abiHint ?? info.abi ?? 'unknown';

  if (!info.is64) {
    return LibraryVerdict(
      path: lib.path,
      name: lib.name,
      module: lib.module,
      abi: abi,
      is64: false,
      status: Status.na,
      checks: [CheckResult(CheckId.loadAlign, Status.na, 'elf32')],
    );
  }

  final checks = <CheckResult>[
    _loadAlign(info),
    _relro(info),
    _congruence(info, strict),
    if (lib.inZip) _zipAlign(lib),
  ];

  var status = Status.ok;
  if (checks.any((c) => c.status == Status.warn)) status = Status.warn;
  if (checks.any((c) => c.status == Status.fail)) status = Status.fail;
  return LibraryVerdict(
    path: lib.path,
    name: lib.name,
    module: lib.module,
    abi: abi,
    minLoadAlign: info.minLoadAlign,
    status: status,
    checks: checks,
  );
}

CheckResult _loadAlign(ElfInfo info) {
  final min = info.minLoadAlign;
  if (min == null) {
    return CheckResult(CheckId.loadAlign, Status.ok, 'no_load');
  }
  if (min < pageSize16k) {
    return CheckResult(CheckId.loadAlign, Status.fail, 'load_align',
        {'align': min, 'need': pageSize16k});
  }
  return CheckResult(
      CheckId.loadAlign, Status.ok, 'load_align_ok', {'align': min});
}

CheckResult _relro(ElfInfo info) {
  final ok = info.relroAligned;
  if (ok == null) return CheckResult(CheckId.relro, Status.ok, 'no_relro');
  if (ok) return CheckResult(CheckId.relro, Status.ok, 'relro_ok');
  return CheckResult(CheckId.relro, Status.fail, 'relro',
      {'end': info.relro!.end, 'need': pageSize16k});
}

CheckResult _congruence(ElfInfo info, bool strict) {
  final bad = info.incongruentLoads;
  if (bad.isEmpty) {
    return CheckResult(CheckId.congruence, Status.ok, 'congruent');
  }
  return CheckResult(
    CheckId.congruence,
    strict ? Status.fail : Status.warn,
    'incongruent',
    {'count': bad.length},
  );
}

CheckResult _zipAlign(LibraryFile lib) {
  if (lib.isAab) {
    final b = lib.bundle;
    if (b != null && b.enabled) {
      if (b.alignment == '16k' || b.alignment == '64k') {
        return CheckResult(CheckId.zipAlign, Status.ok, 'aab_config_ok',
            {'alignment': b.alignment.toUpperCase()});
      }
      if (b.alignment == '4k') {
        return CheckResult(CheckId.zipAlign, Status.fail, 'aab_config_4k');
      }
    }
    return CheckResult(CheckId.zipAlign, Status.na, 'aab');
  }
  if (!lib.stored) {
    return CheckResult(CheckId.zipAlign, Status.na, 'deflated');
  }
  final offset = lib.zipDataOffset!;
  if (offset % pageSize16k != 0) {
    return CheckResult(CheckId.zipAlign, Status.fail, 'zip_align',
        {'offset': offset, 'need': pageSize16k});
  }
  return CheckResult(
      CheckId.zipAlign, Status.ok, 'zip_align_ok', {'offset': offset});
}
