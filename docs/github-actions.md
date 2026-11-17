# Using align16 in GitHub Actions

align16 needs only the Dart SDK. The examples below check the APK produced by
`flutter build apk --release` and use the exit code (0 pass, 1 FAIL or ERROR,
2 usage or input error) to fail the job.

## Basic check

```yaml
name: align16
on: [push, pull_request]
jobs:
  page-size:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter build apk --release
      - run: dart pub global activate align16
      - run: >
          align16 check build/app/outputs/flutter-apk/app-release.apk
          --project .
```

Keep the `build/` folder: attribution looks into `build/<plugin>/intermediates`
to find which package brought a failing library in.

## Step summary (Markdown)

```yaml
      - run: >
          align16 check build/app/outputs/flutter-apk/app-release.apk
          --project . --format markdown >> "$GITHUB_STEP_SUMMARY"
```

`--format markdown` still exits with the check result, so the job fails when a
library fails.

## Only fail on new problems (baseline)

Record today's failures once and commit the file:

```sh
align16 check app-release.apk --project . --json > align16-baseline.json
```

Then in CI:

```yaml
      - run: >
          align16 check build/app/outputs/flutter-apk/app-release.apk
          --project . --baseline align16-baseline.json
```

Failures that are already in the baseline are shown as `KNOWN` and do not fail
the job; a new failing library does. Libraries that were fixed since the
baseline are listed so you can refresh the file.

## Known upstream leftovers (allow list)

`align16-allow.txt` (one entry per line, `#` starts a comment):

```text
# vendor SDK, fix announced for the next release
arm64-v8a/libvendor_sdk.so
```

```yaml
      - run: >
          align16 check app-release.apk --project .
          --allow align16-allow.txt
```

## Libraries from Maven AARs

If a failing library is shown as unattributed, point `--gradle-cache` at the
Gradle caches folder of the build machine so extracted AARs are matched to the
plugin that declares them in `android/build.gradle(.kts)`:

```yaml
      - run: >
          align16 check app-release.apk --project .
          --gradle-cache "$HOME/.gradle/caches"
```

Ask which package could ship a library without any build output:

```sh
align16 explain libfoo.so --project .
```

## App bundles

`align16 check app-release.aab` checks every `<module>/lib/<abi>/*.so` and reads
the native-library alignment from `BundleConfig.pb` (`PAGE_ALIGNMENT_16K` is
ok, `PAGE_ALIGNMENT_4K` fails). bundletool rebuilds the final APKs, so zip
offsets inside the AAB are not checked.

> The JSON report stores the paths you passed in (`input`, `project`) and the
> package folders it found (`candidates[].file`). A committed baseline file
> therefore contains local paths; only the `abi/name` keys are used when it is
> read back, so you can edit the paths out before committing.
