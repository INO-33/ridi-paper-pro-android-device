# RIDI PAPER PRO · 기기 설정과 시스템 구성

Android 8용 RIDI PAPER PRO(E70Q10) 제품 정의입니다. 보드 설정, init/fstab,
리소스 오버레이, RIDI 앱과 빌드에 필요한 기기 자산을 보관합니다.

**전체 소스 준비:** [메인 manifest 저장소](https://github.com/INO-33/ridi-paper-pro)

## 포함 내용

- `AndroidProducts.mk`, `BoardConfig.mk`, `e70q10*.mk`: 제품·보드·패키지 구성
- `init.E70Q10.rc`, `fstab.E70Q10`, `sepolicy/`: 부팅·파티션·권한 설정
- `overlay/`: Settings, SystemUI 등 기기별 화면과 기본값
- `paper_launcher/`, `sleep/`: RIDI 런처와 절전 화면 자산
- `webview/`: Android 제품에 넣는 고정 WebView APK
- `stock-blobs/`, `prebuilt/`: waveform 및 Wi-Fi 모듈 등 필수 입력
- `tools/`: Android 빌드, RAM 부팅 이미지 및 에뮬레이터 보조 도구

## 제품과 빌드

자동 배치 경로는 `device/ridi/e70q10`입니다. 메인 저장소의 준비 스크립트와
환경 설정을 사용한 뒤 기준 제품을 빌드합니다.

```sh
"$ANDROID_BUILD_TOP/ridi-build-support/build.sh" check e70q10_reference-eng
"$ANDROID_BUILD_TOP/ridi-build-support/build.sh" build e70q10_reference-eng bootimage systemimage vendorimage
```

`e70q10_minimal-eng`는 초기 진단용 구성이고, `e70q10_emulator-eng`와
`e70q10_emulator_armv7-eng`는 에뮬레이터용입니다. 실제 기기의 현재 구성과
파티션 배치를 기준으로 이미지를 준비해야 합니다. 과거 SD/RAM 부팅 설명을
현재 eMMC 설치 절차로 그대로 사용하지 마세요.

프레임워크/gralloc 확장이 있는 변경은 같은 빌드의 system/vendor를 함께
준비합니다. 커널 변경은 boot/vendor 모듈 호환성도 확인합니다. 업데이터와 GUI
사용법은 [SD 도구 저장소](https://github.com/INO-33/ridi-paper-pro-sd-tools)에 있습니다.

## 기기 자산과 이력

waveform은 EPDC 초기화에 필요하고, `prebuilt/8189fs.ko`는 선택한 커널과
호환되어야 합니다. 비공개 기기 자산을 포함하므로 이 저장소를 공개로 바꾸지
않습니다. WebView 소스는 [Chromium 저장소](https://github.com/INO-33/ridi-paper-pro-webview)에
별도로 있으며, 제품에 포함된 APK의 해시는 메인 lock 파일에서 확인할 수 있습니다.

이번 README 교체 전의 상세 포팅 기록은
[`docs/BRINGUP_HISTORY.md`](docs/BRINGUP_HISTORY.md)에 보존했습니다.
그 문서에는 초기 단계의 상태와 과거 이미지 경로도 포함됩니다.

현재 체크포인트는 2026-10-16입니다. 최종 저전압 종료 화면 등 실기기에서
계속 확인할 항목이 있으며, 소스 업로드가 모든 기능 검증 완료를 의미하지는 않습니다.
