# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-18

First release.

### Added
- Libraries that fail only the zip offset or the AAB `PAGE_ALIGNMENT_4K` config
  are not listed under "Packages to fix"; a separate note points to the app
  build (AGP 8.5.1+, or `zipalign -P 16` before signing with `apksigner`).
  `--json` has `packaging_issue`.
- Confidence labels are translated in text and Markdown reports; the "Packages
  to fix" list shows `[match: identical bytes]` / `[match: name only]`.
- `explain` also reads `--gradle-cache` and reports unmapped Gradle artifacts;
  a missing `--gradle-cache` folder exits with code 2.
- A note when the AAB `BundleConfig.pb` sets 16K or 64K alignment.
- `align16 check <apk|aab|so|dir>`: parses ZIP and ELF headers directly (no
  readelf, zipalign or Android SDK) and reports four checks per 64-bit library:
  `load-align` (every PT_LOAD p_align >= 0x4000), `relro` (PT_GNU_RELRO end on a
  16 KB boundary or at its LOAD end), `congruence` (p_offset and p_vaddr agree
  modulo p_align, catches a patched p_align) and `zip-align` (STORED APK entries
  start on a 16 KB offset). 32-bit libraries are reported as N/A.
- ZIP reader with ZIP64 support that computes data offsets from the local
  header and reads only the bytes it needs.
- `--project <dir>`: traces failing libraries to the pub package that brought
  them in, with the direct or transitive dependency path, from
  `pubspec.yaml`, `.dart_tool/package_config.json` and
  `.flutter-plugins-dependencies`. Confidence levels: `exact`, `name`,
  `ambiguous` (all candidates listed), `none`.
- `--json` (schema 1), `--abi`, `--allow`, `--strict`, `--no-color`, exit codes
  0 (pass), 1 (FAIL or ERROR), 2 (usage or input error).
- `align16 sample`: synthetic APK, AAB and fake Flutter project plus a real
  check, to try the tool without a build.
- `--format markdown` (GitHub step summary) and `align16 explain <libname.so>
  --project <dir>` (which package could ship a library, without build output).
- `--gradle-cache <dir>`: matches libraries from extracted Maven AARs
  (`transforms-*/*/transformed/<artifact>/jni/<abi>`) to the pub package that
  declares the artifact in `android/build.gradle(.kts)`.
- AAB `BundleConfig.pb`: reads the `uncompress_native_libraries` alignment
  (`PAGE_ALIGNMENT_4K` fails, 16K and 64K pass).
- `--baseline <align16.json>`: only failures missing from an earlier `--json`
  report fail the run (shown as `KNOWN`); fixed ones are listed.
- `docs/github-actions.md`: workflow examples.
- English and Korean output and help (`--lang`, `ALIGN16_LANG`, `LC_ALL`,
  `LC_MESSAGES`, `LANG`).

### Tested with
- Dart SDK 3.8.1, `args` 2.7.0, `yaml` 3.1.4; dev dependencies `archive` 4.6.0
  (independent ZIP cross-check) and `test` 1.31.0.
