import 'dart:io';

import 'package:align16/src/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
