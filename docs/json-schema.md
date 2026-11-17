# JSON report (`--json`, schema 1)

All field names are snake_case. `--lang` never changes the JSON.

| Field | Meaning |
|---|---|
| `schema`, `tool`, `version` | Report format number, `align16`, tool version |
| `input`, `kind`, `project` | Path you passed, `apk`/`aab`/`so`/`dir`, `--project` or null |
| `libraries[]` | One entry per native library: `abi`, `path`, `name`, `module`, `status`, `status_before_allow`, `min_load_align`, `checks[]`, `owner` |
| `libraries[].checks[]` | `id` (`load-align`, `relro`, `congruence`, `zip-align`), `status`, `code` and the values of the check |
| `libraries[].owner` | `package`, `confidence` (`exact`, `name`, `ambiguous`, `none`, `engine`, `app`), `path`, `candidates[]`, `maven_hints` |
| `packages[]` | Packages to fix: only libraries that fail an ELF check are blamed here. `name`, `direct`, `dev`, `reachable`, `path`, `confidence`, `libraries` |
| `packaging_issue` | true when a library fails only the zip offset or the AAB bundle config: fix the app build (AGP 8.5.1+), not a package |
| `baseline_fixed` | `abi/name` entries that failed in the baseline but no longer do |
| `summary` | `checked`, `failed`, `allowed`, `warnings`, `known`, `skipped_32bit`, `errors` |

`status` is one of `ok`, `fail`, `warn`, `na`, `error`, `allowed`, `known`.

## `align16 explain --json`

| Field | Meaning |
|---|---|
| `schema`, `name`, `project` | Format number `1`, the library file name you asked about, `--project` |
| `special` | `engine` for `libflutter.so`, `app` for `libapp.so`, otherwise null |
| `candidates[]` | Packages that ship this file name: `package`, `abi`, `file`, `direct`, `reachable`, `path`, `maven` (Gradle cache artifact folder or null) |
| `gradle_cache` | The `--gradle-cache` folder that was searched, or null |
| `maven_hints[]` | `artifact` and `abi` of extracted AARs in the Gradle cache that contain the file but that no plugin declares in `android/build.gradle(.kts)` |

The exit code is 0 when a package (or the engine / app) was found and 1 otherwise; `maven_hints` alone keep it at 1. A `--gradle-cache` folder that does not exist is an input error (exit code 2) for both `check` and `explain`.
