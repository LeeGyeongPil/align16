/// English messages. Keep the key set identical to `messagesKo`.
const Map<String, String> messagesEn = {
  // report
  'title': 'align16 - Android 16 KB page-size check',
  'input': 'Input: {path} ({kind})',
  'project': 'Project: {path}',
  'col.abi': 'ABI',
  'col.library': 'Library',
  'col.status': 'Status',
  'col.detail': 'Details',
  'no_libs': 'No native libraries (.so) found in this input.',
  // detail lines
  'detail.load_align_ok': 'min LOAD align {align}',
  'detail.no_load': 'no PT_LOAD segments',
  'detail.load_align': 'LOAD align {align} < {need}',
  'detail.relro': 'RELRO ends at {end}, not on a {need} boundary',
  'detail.no_relro': 'no RELRO',
  'detail.relro_ok': 'RELRO ok',
  'detail.congruent': 'offsets congruent',
  'detail.incongruent':
      'p_offset and p_vaddr differ modulo p_align in {count} segment(s) '
          '(p_align edited without relinking?)',
  'detail.zip_align': 'STORED data at offset {offset} is not 16 KB aligned',
  'detail.zip_align_ok': 'zip offset {offset} aligned',
  'detail.aab': 'zip alignment not checked in an AAB',
  'detail.deflated': 'compressed entry, zip alignment n/a',
  'detail.elf32': '32-bit library, not affected',
  'detail.not_elf': 'not an ELF file',
  'detail.truncated': 'truncated ELF headers',
  'detail.read_failed': 'cannot read entry: {message}',
  'detail.allowed': 'allowed by --allow',
  // owner column
  // The bracketed words must equal conf.* below, so a table row and the
  // "Packages to fix" list name the same match the same way.
  'owner.exact': '<- {package} [identical bytes] ({path})',
  'owner.name': '<- {package} [name only] ({path})',
  'owner.unreachable': 'not reachable from the app',
  'owner.ambiguous': '<- several candidates: {packages}',
  'owner.none': '<- unattributed',
  'owner.engine': '<- Flutter engine',
  'owner.app': '<- the app (Dart AOT code)',
  // packages to fix
  'fix.title': 'Packages to fix',
  'fix.direct': 'direct',
  'fix.transitive': 'transitive',
  'fix.unreachable': 'not reachable from the app',
  'fix.dev': 'dev_dependencies',
  'fix.confidence': 'match: {confidence}',
  'conf.exact': 'identical bytes',
  'conf.name': 'name only',
  'conf.ambiguous': 'several candidates',
  'conf.none': 'unattributed',
  'conf.engine': 'Flutter engine',
  'conf.app': 'the app',
  'fix.libs': 'libraries: {libs}',
  'fix.path': 'path: {path}',
  'fix.hint_direct':
      'Upgrade it, replace it, or ask the maintainers for a 16 KB build.',
  'fix.hint_transitive':
      'Upgrade {top} (it pulls this in), or review dependency_overrides.',
  'fix.hint_ambiguous':
      'Several packages ship this file name; check each candidate.',
  'fix.unattributed':
      'Some failing libraries could not be attributed. They may come from a '
          'Maven AAR (Gradle cache), which is not tracked per plugin.',
  // summary
  'summary': '{checked} checked, {failed} failed, {allowed} allowed, {warned} '
      'warnings, {skipped} 32-bit skipped, {errors} errors',
  'result.pass': 'RESULT: PASS - no 16 KB problems in the checks above.',
  'result.fail': 'RESULT: FAIL - fix the libraries marked FAIL or ERROR.',
  'note.aab':
      'Note: for an AAB, bundletool rebuilds the final APKs, so zip alignment '
          'is not checked here.',
  'note.no_project':
      'Tip: add --project <app folder> to trace failing libraries to pub '
          'packages.',
  'note.packaging':
      'Packaging issue in your app build, not in the plugins: some native '
          'libraries are stored in the APK at an offset that is not a multiple of '
          '16 KB. Use AGP 8.5.1 or newer, or run zipalign -P 16 before signing '
          'with apksigner (aligning an already signed APK breaks its '
          'signature). See '
          'https://developer.android.com/guide/practices/page-sizes',
  'note.packaging_aab':
      'App-level setting: the bundle config sets 4 KB native library '
          'alignment (PAGE_ALIGNMENT_4K), which affects every native library. '
          'Switch it to PAGE_ALIGNMENT_16K or use AGP 8.5.1 or newer. See '
          'https://developer.android.com/guide/practices/page-sizes',
  'err.empty_dir':
      'No native libraries (.so) found in {path}. Check that the path is the '
          'unpacked build output (for example build/app/intermediates) or pass '
          'the .apk / .aab file.',
  // errors
  'err.not_found': 'Input not found: {path}',
  'err.not_zip':
      'Not a ZIP (APK/AAB) or ELF (.so) file: {path}. Pass an .apk, an .aab, '
          'a .so file or a folder.',
  'err.bad_zip': 'Broken ZIP structure in {path}: {message}',
  'err.no_pubspec':
      'No readable pubspec.yaml in --project {path}. Point --project at the '
          'root of your Flutter app.',
  'err.allow_read': 'Cannot read the allow list: {path}',
  'err.bad_abi':
      'Unknown ABI "{abi}". Use one or more of: arm64-v8a, x86_64, riscv64, '
          'armeabi-v7a, x86.',
  'err.missing_input':
      'Missing input. Usage: align16 check <apk|aab|so|dir> [options]',
  'err.too_many': 'Too many arguments: {args}',
  'err.unknown_command': 'Unknown command "{command}". Run align16 --help.',
  'err.usage': '{message}',
  'err.bad_lang': 'Unsupported language "{value}". Use en or ko.',
  'err.sample_write': 'Cannot write the sample to {path}: {message}',
  // help
  'help.summary':
      'Checks APK, AAB and .so files for 16 KB page-size alignment and traces '
          'failures to pub packages.',
  'help.usage': 'Usage: align16 <command> [arguments]',
  'help.commands': 'Commands:',
  'help.cmd.check': 'Check an APK, AAB, .so file or folder.',
  'help.cmd.sample': 'Create a synthetic practice sample and check it.',
  'help.global': 'Global options:',
  'help.check_usage': 'Usage: align16 check <apk|aab|so|dir> [options]',
  'help.sample_usage': 'Usage: align16 sample [options]',
  'opt.help': 'Show this help.',
  'opt.version': 'Print the version.',
  'opt.lang': 'Display language (default: ALIGN16_LANG, then LC_ALL, '
      'LC_MESSAGES, LANG).',
  'opt.project': 'Flutter app folder, to trace libraries to pub packages.',
  'opt.abi': 'Comma-separated ABIs to check (default: all found).',
  'opt.allow': 'File of libraries to allow (libname.so or abi/libname.so).',
  'opt.strict': 'Treat the congruence warning as a failure.',
  'opt.json': 'Print one JSON document instead of the table.',
  'opt.no_color': 'Do not color the output.',
  'opt.out': 'Folder for the sample files (default: ./align16-sample).',
  // sample
  'sample.banner':
      'This is a synthetic practice sample (tiny fake ELF/ZIP files and a '
          'fake Flutter project), not a real build. The checks below are real.',
  'sample.created': 'Created: {path}',
  'sample.running': 'Running: align16 check {apk} --project {project}',
  'sample.next':
      'Try it on your app: align16 check build/app/outputs/flutter-apk/'
          'app-release.apk --project .',
  'sample.next_allow':
      'Accept the known leftovers: align16 check {apk} --project {project} '
          '--allow {allow}',
  'sample.allow_comment':
      'align16 allow list for the practice sample. Libraries listed here are\n'
          'shown as ALLOWED and do not fail the run (known leftovers).\n'
          'One libname.so or <abi>/libname.so per line.',
  // baseline, AAB config, Maven hints
  'detail.known': 'known failure from the baseline',
  'detail.aab_config_ok':
      'AAB config: native libraries aligned to {alignment} when installed',
  'detail.aab_config_4k':
      'AAB config sets 4 KB native library alignment (PAGE_ALIGNMENT_4K); '
          'use PAGE_ALIGNMENT_16K',
  'note.aab_config_ok':
      'Note: the bundle config (BundleConfig.pb) sets {alignment} native '
          'library alignment, so bundletool keeps the libraries page-aligned in '
          'the APKs it builds.',
  'owner.none_maven': '<- unattributed (possible Maven artifact: {artifacts})',
  'baseline.known': 'Not counted: {count} known failure(s) from the baseline.',
  'baseline.fixed': 'Fixed since the baseline: {libs}',
  'err.baseline_read': 'Cannot use the baseline file {path}. Create it with: '
      'align16 check <input> --json > align16.json',
  'err.format': 'Unknown format "{value}". Use text, json or markdown.',
  'err.format_conflict':
      '--json cannot be combined with --format {value}. Use only one.',
  'err.missing_name':
      'Missing library name. Usage: align16 explain <libname.so> --project <dir>',
  'err.explain_needs_project':
      'explain needs --project <app folder> to know which packages to look at.',
  // markdown, explain
  'help.cmd.explain': 'Show which package could ship a library name.',
  'help.explain_usage':
      'Usage: align16 explain <libname.so> --project <dir> [options]',
  'opt.format': 'Output format: text, json or markdown (default: text).',
  'opt.gradle_cache':
      'Gradle caches folder to search extracted AARs (for example '
          '~/.gradle/caches).',
  'opt.baseline':
      'Earlier --json report; only failures that are not in it count.',
  'explain.title': 'Explain: {name}',
  'explain.candidates': 'Candidates:',
  'explain.candidate': '{abi}  {package} ({kind})  {path}',
  'explain.file': 'file: {file}',
  'explain.maven': 'Gradle cache artifact: {maven}',
  'explain.none':
      'No package in this project ships {name}. It may come from a Maven AAR; '
          'try --gradle-cache <your Gradle caches folder>.',
  'explain.engine': 'This is the Flutter engine library, not a pub package.',
  'explain.app': 'This is your own compiled Dart code (AOT), not a package.',
  'explain.ambiguous':
      'Several packages ship this file name. Compare their files with the one '
          'in your build.',
  'explain.unreachable': 'not reachable',
  // Gradle cache (explain and check)
  'err.gradle_cache': 'Gradle cache folder not found: {path}. Pass the Gradle '
      'caches folder of the machine that built the app (for example '
      '~/.gradle/caches).',
  'explain.none_cache':
      'No package in this project ships {name}, and no extracted AAR in the '
          'Gradle cache {path} contains it. Build the app once on this machine '
          'so Gradle extracts the AARs, then try again.',
  'explain.none_but_maven':
      'No pub package in this project declares {name}, but extracted AARs in '
          'the Gradle cache contain it:',
  'explain.also_maven':
      'Also in Gradle cache artifacts that no plugin declares:',
  'fix.try_gradle_cache':
      'Add --gradle-cache <Gradle caches folder> (for example '
          '~/.gradle/caches) to look them up in extracted AARs.',
  'explain.maven_unmapped': '{abi}  Gradle artifact: {artifact}',
  'explain.maven_unmapped_hint':
      'No plugin lists these artifacts in its android/build.gradle(.kts). To '
          'see who pulls them in, run ./gradlew :app:dependencies in the '
          'android folder.',
};
