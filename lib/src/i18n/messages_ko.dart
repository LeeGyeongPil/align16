/// 한국어 메시지. 키 집합은 `messagesEn` 과 같아야 한다.
const Map<String, String> messagesKo = {
  // report
  'title': 'align16 - Android 16 KB 페이지 크기 검사',
  'input': '입력: {path} ({kind})',
  'project': '프로젝트: {path}',
  'col.abi': 'ABI',
  'col.library': '라이브러리',
  'col.status': '상태',
  'col.detail': '상세',
  'no_libs': '이 입력에서 네이티브 라이브러리(.so)를 찾지 못했습니다.',
  // detail lines
  'detail.load_align_ok': 'LOAD 최소 정렬 {align}',
  'detail.no_load': 'PT_LOAD 세그먼트 없음',
  'detail.load_align': 'LOAD 정렬 {align} < {need}',
  'detail.relro': 'RELRO 끝 {end} 이(가) {need} 경계가 아님',
  'detail.no_relro': 'RELRO 없음',
  'detail.relro_ok': 'RELRO 정상',
  'detail.congruent': '오프셋 합동',
  'detail.incongruent': '{count}개 세그먼트에서 p_offset 과 p_vaddr 가 p_align 기준으로 어긋남 '
      '(다시 링크하지 않고 p_align 만 고친 흔적?)',
  'detail.zip_align': 'STORED 데이터 오프셋 {offset} 이(가) 16 KB 정렬이 아님',
  'detail.zip_align_ok': 'zip 오프셋 {offset} 정렬됨',
  'detail.aab': 'AAB 에서는 zip 정렬을 검사하지 않음',
  'detail.deflated': '압축 항목, zip 정렬 해당 없음',
  'detail.elf32': '32비트 라이브러리, 영향 없음',
  'detail.not_elf': 'ELF 파일이 아님',
  'detail.truncated': 'ELF 헤더가 잘려 있음',
  'detail.read_failed': '항목을 읽을 수 없음: {message}',
  'detail.allowed': '--allow 로 허용됨',
  // owner column
  'owner.exact': '<- {package} [바이트 일치] ({path})',
  'owner.name': '<- {package} [이름 일치] ({path})',
  'owner.unreachable': '앱에서 닿지 않음',
  'owner.ambiguous': '<- 후보 여러 개: {packages}',
  'owner.none': '<- 귀속 못 함',
  'owner.engine': '<- Flutter 엔진',
  'owner.app': '<- 앱 자체 (Dart AOT 코드)',
  // packages to fix
  'fix.title': '고칠 패키지',
  'fix.direct': '직접',
  'fix.transitive': '전이',
  'fix.unreachable': '앱에서 닿지 않음',
  'fix.dev': 'dev_dependencies',
  'fix.confidence': '귀속 근거: {confidence}',
  'conf.exact': '바이트 일치',
  'conf.name': '이름 일치',
  'conf.ambiguous': '후보 여러 개',
  'conf.none': '귀속 못 함',
  'conf.engine': 'Flutter 엔진',
  'conf.app': '앱 자체',
  'fix.libs': '라이브러리: {libs}',
  'fix.path': '경로: {path}',
  'fix.hint_direct': '업그레이드하거나 교체하거나, 관리자에게 16 KB 빌드를 요청하세요.',
  'fix.hint_transitive':
      '이것을 끌어오는 {top} 을(를) 올리거나 dependency_overrides 를 검토하세요.',
  'fix.hint_ambiguous': '여러 패키지가 같은 파일 이름을 싣고 있습니다. 후보를 각각 확인하세요.',
  'fix.unattributed':
      '일부 실패한 라이브러리는 귀속하지 못했습니다. 플러그인 단위로 남지 않는 Maven AAR(Gradle 캐시)에서 '
          '온 것일 수 있습니다.',
  // summary
  'summary': '검사 {checked}개, 실패 {failed}개, 허용 {allowed}개, 경고 {warned}개, '
      '32비트 제외 {skipped}개, 오류 {errors}개',
  'result.pass': '결과: 통과 - 위 검사에서 16 KB 문제가 없습니다.',
  'result.fail': '결과: 실패 - FAIL 또는 ERROR 로 표시된 라이브러리를 고치세요.',
  'note.aab':
      '참고: AAB 는 bundletool 이 최종 APK 를 다시 만들기 때문에 여기서는 zip 정렬을 검사하지 않습니다.',
  'note.no_project': '팁: --project <앱 폴더> 를 주면 실패한 라이브러리를 pub 패키지까지 추적합니다.',
  'note.packaging':
      '앱 빌드(패키징)의 문제이며 플러그인 탓이 아닙니다: 일부 네이티브 라이브러리가 APK 안에서 16 KB 배수가 아닌 위치에 저장돼 있습니다. AGP 8.5.1 이상을 쓰거나, apksigner 로 서명하기 전에 zipalign -P 16 을 실행하세요(이미 서명한 APK 를 다시 정렬하면 서명이 깨집니다). 참고: https://developer.android.com/guide/practices/page-sizes',
  'note.packaging_aab':
      '앱 수준 설정 문제: 번들 설정이 네이티브 라이브러리 정렬을 4 KB(PAGE_ALIGNMENT_4K)로 지정해 모든 네이티브 라이브러리에 영향을 줍니다. PAGE_ALIGNMENT_16K 로 바꾸거나 AGP 8.5.1 이상을 쓰세요. 참고: https://developer.android.com/guide/practices/page-sizes',
  'err.empty_dir':
      '{path} 에서 네이티브 라이브러리(.so)를 찾지 못했습니다. 압축을 푼 빌드 산출물 경로인지 확인하거나 .apk / .aab 파일을 넘기세요.',
  // errors
  'err.not_found': '입력을 찾을 수 없습니다: {path}',
  'err.not_zip':
      'ZIP(APK/AAB) 또는 ELF(.so) 파일이 아닙니다: {path}. .apk, .aab, .so 파일 또는 폴더를 주세요.',
  'err.bad_zip': '{path} 의 ZIP 구조가 깨져 있습니다: {message}',
  'err.no_pubspec':
      '--project {path} 에서 읽을 수 있는 pubspec.yaml 이 없습니다. --project 를 Flutter 앱 루트로 지정하세요.',
  'err.allow_read': '허용 목록을 읽을 수 없습니다: {path}',
  'err.bad_abi':
      '알 수 없는 ABI "{abi}". arm64-v8a, x86_64, riscv64, armeabi-v7a, x86 중에서 고르세요.',
  'err.missing_input': '입력이 없습니다. 사용법: align16 check <apk|aab|so|dir> [옵션]',
  'err.too_many': '인자가 너무 많습니다: {args}',
  'err.unknown_command': '알 수 없는 명령 "{command}". align16 --help 를 실행해 보세요.',
  'err.usage': '사용법 오류: {message}',
  'err.bad_lang': '지원하지 않는 언어 "{value}". en 또는 ko 를 쓰세요.',
  'err.sample_write': '{path} 에 샘플을 쓸 수 없습니다: {message}',
  // help
  'help.summary':
      'APK, AAB, .so 파일의 16 KB 페이지 크기 정렬을 검사하고 실패를 pub 패키지까지 추적합니다.',
  'help.usage': '사용법: align16 <명령> [인자]',
  'help.commands': '명령:',
  'help.cmd.check': 'APK, AAB, .so 파일 또는 폴더를 검사합니다.',
  'help.cmd.sample': '연습용 합성 샘플을 만들고 검사합니다.',
  'help.global': '공통 옵션:',
  'help.check_usage': '사용법: align16 check <apk|aab|so|dir> [옵션]',
  'help.sample_usage': '사용법: align16 sample [옵션]',
  'opt.help': '이 도움말을 봅니다.',
  'opt.version': '버전을 출력합니다.',
  'opt.lang': '화면 언어 (기본: ALIGN16_LANG, LC_ALL, LC_MESSAGES, LANG 순).',
  'opt.project': 'Flutter 앱 폴더. 라이브러리를 pub 패키지까지 추적합니다.',
  'opt.abi': '검사할 ABI 목록(쉼표 구분, 기본: 찾은 전부).',
  'opt.allow': '허용할 라이브러리 목록 파일 (libname.so 또는 abi/libname.so).',
  'opt.strict': '합동 경고를 실패로 처리합니다.',
  'opt.json': '표 대신 JSON 문서 하나를 출력합니다.',
  'opt.no_color': '출력에 색을 쓰지 않습니다.',
  'opt.out': '샘플 파일을 만들 폴더 (기본: ./align16-sample).',
  // sample
  'sample.banner':
      '연습용 합성 샘플(synthetic practice sample)입니다(아주 작은 가짜 ELF/ZIP 파일과 가짜 Flutter 프로젝트이며 실제 빌드가 아닙니다). '
          '아래 검사는 진짜로 실행됩니다.',
  'sample.created': '만든 위치: {path}',
  'sample.running': '실행: align16 check {apk} --project {project}',
  'sample.next':
      '내 앱에서 해 보기: align16 check build/app/outputs/flutter-apk/app-release.apk --project .',
  'sample.next_allow':
      '알려진 잔여 문제 허용하기: align16 check {apk} --project {project} --allow {allow}',
  'sample.allow_comment': '연습용 샘플의 align16 허용 목록입니다. 여기 적은 라이브러리는\n'
      'ALLOWED 로 표시되고 실행을 실패시키지 않습니다(알려진 잔여 문제).\n'
      '한 줄에 libname.so 또는 <abi>/libname.so 하나씩 적습니다.',
  // baseline, AAB config, Maven hints
  'detail.known': '기준선(baseline)에 있던 알려진 실패',
  'detail.aab_config_ok': 'AAB 설정: 설치 시 네이티브 라이브러리를 {alignment} 로 정렬',
  'detail.aab_config_4k':
      'AAB 설정이 네이티브 라이브러리 정렬을 4 KB(PAGE_ALIGNMENT_4K)로 지정함. PAGE_ALIGNMENT_16K 로 바꾸세요',
  'note.aab_config_ok':
      '참고: 번들 설정(BundleConfig.pb)이 네이티브 라이브러리 정렬을 {alignment} 로 지정하므로 bundletool 이 만드는 APK 에서도 라이브러리가 페이지 경계에 맞게 놓입니다.',
  'owner.none_maven': '<- 귀속 못 함 (Maven 아티팩트 후보: {artifacts})',
  'baseline.known': '집계 제외: 기준선(baseline)에 있던 알려진 실패 {count}개.',
  'baseline.fixed': '기준선 이후 고쳐진 항목: {libs}',
  'err.baseline_read':
      '기준선 파일 {path} 을(를) 쓸 수 없습니다. align16 check <입력> --json > align16.json 으로 만드세요.',
  'err.format': '알 수 없는 형식 "{value}". text, json, markdown 중에서 고르세요.',
  'err.format_conflict': '--json 은 --format {value} 와 함께 쓸 수 없습니다. 하나만 쓰세요.',
  'err.missing_name':
      '라이브러리 이름이 없습니다. 사용법: align16 explain <libname.so> --project <dir>',
  'err.explain_needs_project':
      'explain 은 어떤 패키지를 볼지 알려면 --project <앱 폴더> 가 필요합니다.',
  // markdown, explain
  'help.cmd.explain': '라이브러리 이름을 어떤 패키지가 싣고 있을 수 있는지 보여 줍니다.',
  'help.explain_usage':
      '사용법: align16 explain <libname.so> --project <dir> [옵션]',
  'opt.format': '출력 형식: text, json, markdown (기본: text).',
  'opt.gradle_cache': '추출된 AAR 을 찾을 Gradle 캐시 폴더 (예: ~/.gradle/caches).',
  'opt.baseline': '이전 --json 보고서. 여기에 없는 실패만 집계합니다.',
  'explain.title': '설명: {name}',
  'explain.candidates': '후보:',
  'explain.candidate': '{abi}  {package} ({kind})  {path}',
  'explain.file': '파일: {file}',
  'explain.maven': 'Gradle 캐시 아티팩트: {maven}',
  'explain.none':
      '이 프로젝트의 어떤 패키지도 {name} 을(를) 싣고 있지 않습니다. Maven AAR 에서 온 것일 수 있으니 --gradle-cache <Gradle 캐시 폴더> 를 써 보세요.',
  'explain.engine': 'Flutter 엔진 라이브러리이며 pub 패키지가 아닙니다.',
  'explain.app': '앱 자체의 컴파일된 Dart 코드(AOT)이며 패키지가 아닙니다.',
  'explain.ambiguous': '여러 패키지가 같은 파일 이름을 싣고 있습니다. 빌드에 들어간 파일과 각 후보를 비교하세요.',
  'explain.unreachable': '닿지 않음',
  // Gradle cache (explain and check)
  'err.gradle_cache':
      'Gradle 캐시 폴더를 찾을 수 없습니다: {path}. 앱을 빌드한 컴퓨터의 Gradle 캐시 폴더(예: ~/.gradle/caches)를 주세요.',
  'explain.none_cache':
      '이 프로젝트의 어떤 패키지도 {name} 을(를) 싣고 있지 않고, Gradle 캐시 {path} 의 추출된 AAR 에도 없습니다. 이 컴퓨터에서 앱을 한 번 빌드해 Gradle 이 AAR 을 풀어 두게 한 뒤 다시 해 보세요.',
  'explain.none_but_maven':
      '이 프로젝트의 어떤 pub 패키지도 {name} 을(를) 선언하지 않았지만, Gradle 캐시의 추출된 AAR 에 들어 있습니다:',
  'explain.also_maven': '어느 플러그인도 선언하지 않은 Gradle 캐시 아티팩트에도 있습니다:',
  'fix.try_gradle_cache':
      '--gradle-cache <Gradle 캐시 폴더>(예: ~/.gradle/caches) 를 주면 추출된 AAR 에서 찾아봅니다.',
  'explain.maven_unmapped': '{abi}  Gradle 아티팩트: {artifact}',
  'explain.maven_unmapped_hint':
      '이 아티팩트를 android/build.gradle(.kts) 에 적은 플러그인이 없습니다. 누가 끌어오는지 보려면 android 폴더에서 ./gradlew :app:dependencies 를 실행하세요.',
};
