// Command line front end. `runCli` takes its streams and environment as
// arguments so tests can call it directly.
import 'dart:io';

import 'package:args/args.dart';

import 'allowlist.dart';
import 'baseline.dart';
import 'artifact.dart';
import 'checker.dart';
import 'explain.dart';
import 'i18n/i18n.dart';
import 'report/explain_report.dart';
import 'report/json_report.dart';
import 'report/markdown_report.dart';
import 'report/text_report.dart';
import 'sample/sample_project.dart';
import 'version.dart';

/// Looks for `--lang <v>` / `--lang=<v>` before the real parse so that help
/// and usage errors already use the right language.
String? _scanLangFlag(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--') break;
    if (a == '--lang' && i + 1 < args.length) return args[i + 1];
    if (a.startsWith('--lang=')) return a.substring(7);
  }
  return null;
}

ArgParser _checkParser(Messages m) => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false, help: m.t('opt.help'))
  ..addOption('lang',
      allowed: ['en', 'ko'], help: m.t('opt.lang'), valueHelp: 'en|ko')
  ..addOption('project', abbr: 'p', help: m.t('opt.project'), valueHelp: 'dir')
  ..addOption('abi', help: m.t('opt.abi'), valueHelp: 'list')
  ..addOption('allow', help: m.t('opt.allow'), valueHelp: 'file')
  ..addOption('baseline', help: m.t('opt.baseline'), valueHelp: 'file')
  ..addOption('gradle-cache', help: m.t('opt.gradle_cache'), valueHelp: 'dir')
  ..addOption('format',
      help: m.t('opt.format'), valueHelp: 'text|json|markdown')
  ..addFlag('strict', negatable: false, help: m.t('opt.strict'))
  ..addFlag('json', negatable: false, help: m.t('opt.json'))
  ..addFlag('no-color', negatable: false, help: m.t('opt.no_color'));

ArgParser _explainParser(Messages m) => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false, help: m.t('opt.help'))
  ..addOption('lang',
      allowed: ['en', 'ko'], help: m.t('opt.lang'), valueHelp: 'en|ko')
  ..addOption('project', abbr: 'p', help: m.t('opt.project'), valueHelp: 'dir')
  ..addOption('abi', help: m.t('opt.abi'), valueHelp: 'list')
  ..addOption('gradle-cache', help: m.t('opt.gradle_cache'), valueHelp: 'dir')
  ..addFlag('json', negatable: false, help: m.t('opt.json'))
  // explain 출력은 원래 색을 쓰지 않는다. 그래도 check·sample 과 같은 공통
  // 옵션을 스크립트가 그대로 넘길 수 있게 --no-color 를 받아 둔다(아무 일도 안 함).
  ..addFlag('no-color', negatable: false, help: m.t('opt.no_color'));

ArgParser _sampleParser(Messages m) => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false, help: m.t('opt.help'))
  ..addOption('lang',
      allowed: ['en', 'ko'], help: m.t('opt.lang'), valueHelp: 'en|ko')
  ..addOption('out', abbr: 'o', help: m.t('opt.out'), valueHelp: 'dir')
  ..addFlag('no-color', negatable: false, help: m.t('opt.no_color'));

ArgParser _topParser(Messages m) => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false, help: m.t('opt.help'))
  ..addFlag('version', negatable: false, help: m.t('opt.version'))
  ..addOption('lang',
      allowed: ['en', 'ko'], help: m.t('opt.lang'), valueHelp: 'en|ko');

String _topHelp(Messages m) => '''
align16 $packageVersion - ${m.t('help.summary')}

${m.t('help.usage')}

${m.t('help.commands')}
  check   ${m.t('help.cmd.check')}
  explain ${m.t('help.cmd.explain')}
  sample  ${m.t('help.cmd.sample')}

${m.t('help.global')}
${_topParser(m).usage}
''';

/// Runs align16 and returns the process exit code.
///
/// [env] defaults to the real environment; [isTerminal] decides whether the
/// table may be colored.
Future<int> runCli(
  List<String> args, {
  Map<String, String>? env,
  StringSink? out,
  StringSink? err,
  bool? isTerminal,
}) async {
  final environment = env ?? Platform.environment;
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final terminal = isTerminal ?? stdout.hasTerminal;

  final langFlag = _scanLangFlag(args);
  final Messages m;
  if (langFlag != null && langFlag != 'en' && langFlag != 'ko') {
    // Bad value: answer in the environment language.
    final mm = Messages(resolveLang(env: environment));
    stderrSink.writeln(mm.t('err.bad_lang', {'value': langFlag}));
    return 2;
  }
  m = Messages(resolveLang(flag: langFlag, env: environment));

  // command = first argument that is not an option or the value of --lang
  String? command;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--lang') {
      i++;
      continue;
    }
    if (a.startsWith('--lang=')) continue;
    // The command word must come first (after an optional --lang).
    command = a.startsWith('-') ? null : a;
    break;
  }

  if (command == null) {
    final ArgResults top;
    try {
      top = _topParser(m).parse(args);
    } on FormatException catch (e) {
      stderrSink.writeln(m.t('err.usage', {'message': e.message}));
      stderrSink.writeln(_topHelp(m));
      return 2;
    }
    if (top['version'] == true) {
      stdoutSink.writeln('align16 $packageVersion');
      return 0;
    }
    if (top['help'] == true) {
      stdoutSink.write(_topHelp(m));
      return 0;
    }
    stderrSink.write(_topHelp(m));
    return 2;
  }

  switch (command) {
    case 'check':
      return _check(args, m, environment, stdoutSink, stderrSink, terminal);
    case 'explain':
      return _explain(args, m, stdoutSink, stderrSink);
    case 'sample':
      return _sample(args, m, environment, stdoutSink, stderrSink, terminal);
  }
  stderrSink.writeln(m.t('err.unknown_command', {'command': command}));
  return 2;
}

bool _useColor(bool noColorFlag, Map<String, String> env, bool terminal) =>
    !noColorFlag && terminal && (env['NO_COLOR'] ?? '').isEmpty;

Future<int> _check(
  List<String> args,
  Messages m,
  Map<String, String> env,
  StringSink out,
  StringSink err,
  bool terminal,
) async {
  final parser = _checkParser(m);
  final ArgResults res;
  try {
    res = parser.parse(args);
  } on FormatException catch (e) {
    err.writeln(m.t('err.usage', {'message': e.message}));
    err.writeln(m.t('help.check_usage'));
    return 2;
  }
  if (res['help'] == true) {
    out.writeln(m.t('help.check_usage'));
    out.writeln();
    out.write(parser.usage);
    out.writeln();
    return 0;
  }
  final rest = res.rest;
  // rest[0] is the command word `check` itself.
  final inputs = rest.length > 1 ? rest.sublist(1) : <String>[];
  if (inputs.isEmpty) {
    err.writeln(m.t('err.missing_input'));
    return 2;
  }
  if (inputs.length > 1) {
    err.writeln(m.t('err.too_many', {'args': inputs.skip(1).join(' ')}));
    return 2;
  }

  try {
    final abis = _parseAbis(res['abi'] as String?);
    var format = (res['format'] as String?) ?? 'text';
    if (!['text', 'json', 'markdown'].contains(format)) {
      throw InputError('err.format', {'value': format});
    }
    if (res['json'] == true) {
      if (res['format'] != null && format != 'json') {
        throw InputError('err.format_conflict', {'value': format});
      }
      format = 'json';
    }
    final allowPath = res['allow'] as String?;
    final baselinePath = res['baseline'] as String?;
    final report = checkArtifact(
      inputs.first,
      CheckOptions(
        abis: abis,
        allow: allowPath == null ? null : Allowlist.load(allowPath),
        strict: res['strict'] == true,
        projectDir: res['project'] as String?,
        gradleCache: res['gradle-cache'] as String?,
        baseline: baselinePath == null ? null : Baseline.load(baselinePath),
      ),
    );
    if (format == 'json') {
      out.writeln(renderJsonReport(report));
    } else if (format == 'markdown') {
      out.write(renderMarkdownReport(report, m));
    } else {
      out.write(renderTextReport(report, m,
          color: _useColor(res['no-color'] == true, env, terminal)));
    }
    return report.exitCode;
  } on InputError catch (e) {
    err.writeln(m.t(e.key, e.args));
    return 2;
  }
}

Future<int> _sample(
  List<String> args,
  Messages m,
  Map<String, String> env,
  StringSink out,
  StringSink err,
  bool terminal,
) async {
  final parser = _sampleParser(m);
  final ArgResults res;
  try {
    res = parser.parse(args);
  } on FormatException catch (e) {
    err.writeln(m.t('err.usage', {'message': e.message}));
    err.writeln(m.t('help.sample_usage'));
    return 2;
  }
  if (res['help'] == true) {
    out.writeln(m.t('help.sample_usage'));
    out.writeln();
    out.write(parser.usage);
    out.writeln();
    return 0;
  }
  final dir = (res['out'] as String?) ?? 'align16-sample';
  final SampleFiles files;
  try {
    files = writeSample(dir, messages: m);
  } on FileSystemException catch (e) {
    err.writeln(m.t('err.sample_write', {'path': dir, 'message': e.message}));
    return 2;
  }
  out.writeln(m.t('sample.banner'));
  out.writeln();
  out.writeln(m.t('sample.created', {'path': files.apk}));
  out.writeln(m.t('sample.created', {'path': files.aab}));
  out.writeln(m.t('sample.created', {'path': files.project}));
  // README "Known leftovers" 예제가 쓰는 허용 목록도 함께 만든다.
  out.writeln(m.t('sample.created', {'path': files.allow}));
  out.writeln();
  out.writeln(
      m.t('sample.running', {'apk': files.apk, 'project': files.project}));
  out.writeln();
  try {
    final report = checkArtifact(
      files.apk,
      CheckOptions(projectDir: files.project),
    );
    out.write(renderTextReport(report, m,
        color: _useColor(res['no-color'] == true, env, terminal)));
  } on InputError catch (e) {
    err.writeln(m.t(e.key, e.args));
    return 2;
  }
  out.writeln();
  out.writeln(m.t('sample.next_allow', {
    'apk': files.apk,
    'project': files.project,
    'allow': files.allow,
  }));
  out.writeln(m.t('sample.next'));
  return 0;
}

Set<String>? _parseAbis(String? arg) {
  if (arg == null) return null;
  final abis = <String>{};
  for (final a in arg.split(',')) {
    final t = a.trim();
    if (t.isEmpty) continue;
    if (!knownAbis.contains(t)) throw InputError('err.bad_abi', {'abi': t});
    abis.add(t);
  }
  return abis;
}

Future<int> _explain(
  List<String> args,
  Messages m,
  StringSink out,
  StringSink err,
) async {
  final parser = _explainParser(m);
  final ArgResults res;
  try {
    res = parser.parse(args);
  } on FormatException catch (e) {
    err.writeln(m.t('err.usage', {'message': e.message}));
    err.writeln(m.t('help.explain_usage'));
    return 2;
  }
  if (res['help'] == true) {
    out.writeln(m.t('help.explain_usage'));
    out.writeln();
    out.write(parser.usage);
    out.writeln();
    return 0;
  }
  final names = res.rest.length > 1 ? res.rest.sublist(1) : <String>[];
  if (names.isEmpty) {
    err.writeln(m.t('err.missing_name'));
    return 2;
  }
  if (names.length > 1) {
    err.writeln(m.t('err.too_many', {'args': names.skip(1).join(' ')}));
    return 2;
  }
  final project = res['project'] as String?;
  if (project == null) {
    err.writeln(m.t('err.explain_needs_project'));
    return 2;
  }
  try {
    final result = explainLibrary(
      names.first,
      project,
      abis: _parseAbis(res['abi'] as String?),
      gradleCache: res['gradle-cache'] as String?,
    );
    if (res['json'] == true) {
      out.writeln(renderExplainJson(result));
    } else {
      out.write(renderExplainText(result, m));
    }
    return result.exitCode;
  } on InputError catch (e) {
    err.writeln(m.t(e.key, e.args));
    return 2;
  }
}
