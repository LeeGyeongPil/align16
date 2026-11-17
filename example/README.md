# align16 examples

Install the command line tool:

```sh
dart pub global activate align16
```

Try it without a build (writes a tiny synthetic sample and checks it):

```sh
align16 sample --out ./align16-sample
```

Check a real build and trace failures to pub packages:

```sh
align16 check build/app/outputs/flutter-apk/app-release.apk --project .
align16 check build/app/outputs/bundle/release/app-release.aab --project .
```

Use it in CI (exit code 1 on FAIL or ERROR, JSON for tooling):

```sh
align16 check app-release.apk --project . --json > align16.json
align16 check app-release.apk --project . --allow align16-allow.txt
```

Show the output in Korean: `align16 check app.apk --lang ko` or
`ALIGN16_LANG=ko`.
