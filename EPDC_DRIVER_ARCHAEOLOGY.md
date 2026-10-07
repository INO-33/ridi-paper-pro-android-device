# E70Q10 EPDC driver archaeology

조사일: 2026-09-16

이 문서는 production 동작을 바꾸지 않은 source/binary/host 조사 결과다. 결론의
증거 수준은 다음처럼 구분한다.

- **SOURCE-CONFIRMED**: 현재/공식 공개 소스에서 직접 확인
- **BINARY-CONFIRMED**: RIDI stock 바이너리의 ioctl/disassembly로 확인
- **HOST-REPRODUCED**: host model에서 재현했으나 실기기 인과관계는 미확인
- **DEVICE-UNVERIFIED**: 다음 실기기 A/B가 필요한 가설

## 1. Executive conclusion

### 결론

현재 증상을 하나의 원인으로 묶는 것은 맞지 않는다. 가장 타당한 분류는 다음과
같다.

1. **비동기 QUEUE_AND_MERGE와 Android framebuffer page lifetime 사이의 integration
   contract mismatch** — 높은 가능성, DEVICE-UNVERIFIED.

   Stock과 현재 모두 `QUEUE_AND_MERGE`이며 normal update에서 waveform 완료를
   기다리지 않는다. 따라서 update scheme 자체를 잃은 Android 8 regression은
   아니다. 그러나 queued ioctl은 PxP가 source를 읽기 전에 반환하고 Android 8
   HWC는 release/retire fence를 `-1`로 돌려준다. 현재 커널은 page offset은 enqueue
   시점에 저장하도록 보완됐지만 page **내용**은 snapshot하지 않는다. Host replay는
   page가 PxP read 전에 재사용되면 정상 최종 framebuffer와 stale panel이 동시에
   가능함을 재현했다. Stock도 같은 scheme을 쓰므로 이것을 HWC 단독 버그라고
   단정할 수 없고, stock의 buffer cadence/커널 copy/vendor contract와 현재 조합의
   차이를 실기기 trace로 확인해야 한다.

2. **RIDI stock과 현재 포팅의 rotation/ownership 구조 차이** — 높은 확신의 통합
   차이, 중간 정도의 인과 가능성.

   Stock kernel fb0는 `1872x1404`, RGB565, stride 1888, rotate 0이고 Android가
   1404x1872 layer를 1872x1404 framebuffer target으로 회전한다. 현재는 fb0 자체가
   `1404x1872`, stride 1408이고 kernel EPDC/PxP가 `FB_ROTATE_CCW`로 최종 회전을
   수행한다. 이 경로는 generic NXP가 지원하고 Kobo Aura One에서도 유사한 portrait
   fb/rotation 구성이 관측되므로 “회전 자체가 불가능”하지는 않다. 다만 RIDI stock이
   검증한 ED078KH1/P5N 경로와는 분명히 다르며, 현재에만 존재하는 padding/`epdc_offs`
   보완이 이미 이 경계가 민감했음을 보여준다.

3. **canonical NXP collision retry의 mixed-order bounding-box 손실 가능성** —
   SOURCE-CONFIRMED 조건부 취약점, HOST-REPRODUCED, DEVICE-UNVERIFIED.

   EPDC v2가 여러 LUT와 충돌한 최소 bounding rect 하나를 반환할 때, canonical
   driver는 collision mask 중 하나라도 현재 update보다 새 order이면 collision rect
   전체를 재전송하지 않는다. newer LUT가 그 bounding rect 전체를 덮는지는 검사하지
   않는다. Host model에서 왼쪽은 older LUT, 오른쪽은 newer LUT와 충돌하는 경우
   가운데/왼쪽의 8 pixel이 논리적으로 누락되는 counterexample을 재현했다. 이 정책은
   현재 Android 8에서 새로 만든 것이 아니라 오래된 NXP 코드에 있고 5.4 계열까지
   유지된다. 실제 패널에서 이 mixed-order collision이 발생했는지는 trace가 필요하다.

4. **알려진 이후 NXP border/rotation bugfix 누락** — 낮은 가능성.

   현재 base의 `mxc_epdc_fb.c`와 NXP `imx_4.9.11_android_ga`, 4.9.88 파일은
   SHA-256까지 동일하다. 4.14의 의미 있는 차이는 반복 firmware init의 문자열
   overflow 수정 한 건이고, 5.4는 DMA API rename 중심이다. 2011~2016의 shift,
   collision IRQ, width>=2048, stress/cache workaround는 현재 base에 이미 들어 있다.
   조사 범위에서 이후 NXP가 고친 1px border/rotation patch는 찾지 못했다.

5. **얇은 UI 선 품질은 P5N/quantization 별도 문제** — 중간 가능성.

   현재 포팅은 stock의 Netronix AA 확장 전체가 아니라 별도 `PXP_LUT_AA`를 추가해
   P5N source를 `value & 0xF0`으로 양자화한다. 코드 주석은 5-bit라고 하지만 실제
   결과는 16단계다. 이는 1px grayscale/anti-aliased 선 품질과 직접 관련될 수 있으나,
   검은 점/세로줄의 stale-pixel 원인이라고 볼 증거는 없다.

따라서 질문에 대한 현재 답은 **“알려진 최신 NXP fix가 빠진 단순 구형-driver 문제”가
아니라, 오래된 NXP의 비동기 queue/collision semantics와 RIDI stock과 다른 Android 8
buffer/rotation 통합 사이의 contract mismatch가 1순위**다. 얇은 선 품질은 별도의
P5N/AA 통합 문제일 가능성이 더 높다.

## 2. 현재 driver lineage

### 실제 build 대상

- `device/ridi/e70q10/BoardConfig.mk`: `TARGET_KERNEL_DEFCONF := e70q10_defconfig`
- `arch/arm/configs/e70q10_defconfig`:
  `CONFIG_FB_MXC_EINK_PANEL=y`, `CONFIG_MXC_PXP_V2=y`
- `drivers/video/fbdev/mxc/Makefile`: 위 설정은 `mxc_epdc_fb.o`를 build
- DTS compatible: `fsl,imx6sl-epdc`, `fsl,imx6dl-epdc`
- `mxc_epdc_v2_fb.c`는 i.MX7D용 compatible이므로 이름이 비슷해도 실제 i.MX6SL
  EPDC driver가 아니다.

### 계보

- kernel version: `4.9.17`
- NXP tag: `o8.0.0_1.0.0-ga`
- tag commit: `a88711e790e0b196f90f9181cb936c15834a8669`, 2017-03-09
- upstream remote: `https://github.com/nxp-imx/linux-imx`
- 현재 프로젝트 snapshot root: `fb7d307fc1506fbc10eb22ac89a5eb4640be50e8`
- 현재 HEAD: `a48053edf8abe11f1137cefe309bf6418a3c52e6`

NXP tag의 `mxc_epdc_fb.c`와 공개 `imx_4.9.11_android_ga` 파일은 동일하고,
NXP 4.9.88 파일도 동일하다. 현재 파일은 그 base에 E70Q10 panel, Netronix advanced
waveform/P5N, captured `fb_offset`, cleanup fence, edge trace와 여러 실기기 보완을
추가한 vendor fork다. 현재 파일은 base 대비 약 `+1419/-119`, PxP v2는
`+35/-1`이므로 “순정 NXP 4.9 driver 그대로”도 아니다.

## 3. RIDI stock behavior

### Stock kernel

- image string: `Linux version 3.0.35 ... #218 ... Fri Aug 16 20:39:47 KST 2024`
- config: `CONFIG_FB_MXC_EINK_PANEL=y`, `CONFIG_MXC_PXP_V2=y`,
  `CONFIG_MXC_PXP_CLIENT_DEVICE=y`
- kallsyms에는 generic NXP 함수 외에 `ntx_epdc_pmic_exception`,
  `mxc_epdc_fb_aa_info`, `mxc_epdc_fb_fetch_wxi_data`,
  `mxc_epdc_fb_fetch_vc_data`가 존재한다.

따라서 stock은 NXP/Freescale 3.0.35 계열 위의 Netronix/RIDI vendor fork다. GPL
source archive가 workspace에 없고 kernel commit id도 image에 없으므로 정확한 source
commit ancestry는 복구할 수 없었다. 단순 NXP 3.0.35와 동일하다고 취급해서는 안 된다.

### Stock framebuffer/HWC geometry

Runtime dump는 다음을 확정한다.

```text
fb0: mxc_epdc_fb
mode: 1872x1404
bpp: 16
rotate: 0
line_length: 3776 bytes = 1888 RGB565 pixels
xres_virtual,yres_virtual: 1888,4224
```

SurfaceFlinger dump에서는 app/statusbar buffer가 `1404x1872:1408`이지만 display와
framebuffer target은 `1872x1404:1888`, orientation 3이다. 즉 stock은 logical layer
회전을 Android composition 쪽에서 끝낸 뒤 native-landscape fb를 kernel에 넘긴다.

### Stock update scheme: binary-confirmed

`system/lib/hw/gralloc.imx6.so` ARM disassembly에서 다음을 확인했다.

1. ioctl `0x4004462d` (`MXCFB_SET_AUTO_UPDATE_MODE`)에 값 0, 즉 REGION mode
2. 이어 ioctl `0x40044632` (`MXCFB_SET_UPDATE_SCHEME`)에 값 2
3. 값 2는 `UPDATE_SCHEME_QUEUE_AND_MERGE`

normal update helper는 `MXCFB_SEND_UPDATE` 후 flag bit 6이 있을 때만
`MXCFB_WAIT_FOR_UPDATE_COMPLETE`를 호출한다. 일반 호출은 이 bit 없이 waveform 값만
넘기므로 stock도 normal frame마다 WAIT하지 않는다. `epd_ctrl`은 주로 VCOM 제어이고
scheme 초기화 주체가 아니다.

결론: **stock=SNAPSHOT/current=QUEUE_AND_MERGE라는 regression은 반증됐다.**

## 4. NXP BSP evolution

비교한 계열:

- `imx_3.0.35_android_kk4.4.2_1.y_caf`
- `imx_4.1.15_2.0.0_ga`
- `imx_4.9.11_android_ga`
- `imx_4.9.88_2.0.0_ga`
- `imx_4.14.98_2.3.5`
- `lf-5.4.y`

### 관련 commit

| commit | 날짜 | 제목/핵심 | 현재 base | 증상 관련성 |
|---|---:|---|---|---|
| `b9c8bb93a003` | 2011-05-31 | EPDC status IRQ race; clear 전에 capture | 있음 | collision mask 신뢰성, 중요 |
| `0ba4f2582581` | 2011-06-21 | SNAPSHOT FULL update의 endless collision 방지 | 있음 | 현재 Q&M에는 직접 원인 아님 |
| `af027787b601` | 2011-07-05 | 16bpp 일부 x에서 update가 오른쪽 1열 shift | 있음 | 증상과 유사하나 이미 반영 |
| `a615fc7ad97c` | 2012-02-29 | stress failure, workqueue/mutex/LUT cancel 수정 | 있음 | queue 안정성 |
| `6d07d40f6f6e` | 2012-09-26 | ERR005313, width >=2048 split | 있음 | panel width 1872라 비활성 |
| `05a83033f095` | 2012-10-12 | fully-collided VOID를 collision으로 retry | 있음 | partial collision 관련 |
| `2ca4bd89cc5f` | 2013-04-03 | reversed conditional/endless collision 수정 | 있음 | collision 관련 |
| `d59e4e631fd6` | 2016-01-12 | `outer_flush_all` 대신 range | 있음 | crash/cache 안정성 |
| `0040cbe8b7de` | 2017-03-02 | PxP RGB format 정의 정리 | 있음 | artifact fix 근거 없음 |
| `4d69e57a84c1` | 2017-03-11 | unused multi-overlay 제거 | 동등 코드 | artifact fix 아님 |
| `1b54ea4d98d0` | 2019-04-28 | firmware filename out-of-bounds 수정 | 현재 fork는 별도 64-byte/안전 경로 | partial artifact 무관 |

4.9.11과 4.9.88의 EPDC/PxP v2 파일은 각각 byte-identical이다. 4.14 EPDC의
실질 변경은 firmware path 생성 시 `strcat`을 `strcpy`로 시작하게 한 것뿐이다. 5.4는
주로 `dma_alloc_writecombine`을 `dma_alloc_wc`로 rename했다. 즉 NXP가 후속 maintenance
branch에서 border/pitch/collision 알고리즘을 적극 수정했다는 증거는 없다.

### Silicon errata

i.MX6SL 공개 errata에서 display 관련 항목은 다음과 같다.

- **ERR004573**: IRQ clear가 LUT16..63 collision status를 지우므로 status를 먼저
  읽어야 한다. 현재 `mxc_epdc_irq_handler()`가 clear 전에
  `epdc_get_colliding_luts()`를 호출한다. 적용됨.
- **ERR005313**: update width >=2048에서 address truncation. 현재
  `EPDC_V2_MAX_UPDATE_WIDTH=2047` split/restrict workaround가 있다. 이 panel의 native
  width 1872에는 직접 발동하지 않는다.
- **ERR006287**: suspend display-domain power gating 뒤 EPDC/PxP register read가 이전
  값을 반환할 수 있으므로 display domain을 power-gate하지 말라는 erratum. 현재 NXP
  4.9 GPC는 i.MX6SL revision >=1.2에서 dispmix on/off를 구현한다. 이것이 실제 SoC
  revision과 suspend path에서 활성인지 확인이 필요하다. steady-state 최초 부팅부터
  나타나는 점/줄의 1순위 원인은 아니지만, 첫 suspend 이후에만 악화된다면 중요하다.

ERR005992는 i.MX6SoloLite 공개 errata 목록에 없으므로 이 장치의 근거로 사용하지
않는다.

## 5. Comparable devices

| 항목 | RIDI current | RIDI stock | NXP old/new | Kobo Aura One | reMarkable reference |
|---|---|---|---|---|---|
| SoC | i.MX6SL | i.MX6SL | i.MX6SL 지원 | i.MX6SL/Netronix | i.MX6SL 계열 |
| visible panel | 1872x1404 | 1872x1404 | mode별 | 1872x1404 | ES103CS1 1872x1404 mode |
| exposed fb | 1404x1872 | 1872x1404 | configurable | 1404x1872 관측 | vendor별 |
| stride | 1408 RGB565 | 1888 RGB565 | xres virtual align | 1408, 32bpp(line 5632) | 공개 driver generic |
| rotation | kernel CCW | Android/HWC orient 3, kernel 0 | 둘 다 지원 | fb rotate 3 관측 | generic NXP |
| update default | Q&M | Q&M 명시 | Q&M | kernel/vendor binary 미확인 | Q&M 계열 |
| snapshot support | 있음 | 있음 | 있음 | ioctl header에는 있음 | 있음 |

Kobo Aura One의 공개 runtime log는 `1404x1872`, rotate 3, 32bpp, line length
5632(=1408 pixels)를 보인다. 따라서 current의 portrait/1408 geometry가 그 자체로
NXP EPDC에서 불가능한 구성은 아니다. 그러나 Kobo는 32bpp source, 다른 Netronix
kernel/userspace/waveform이므로 RIDI의 RGB565/P5N `epdc_offs` 정확성을 보증하지 않는다.

KOReader/FBInk 계열은 hardware dithering rect를 8px outward-align하고 Kobo kernel의
rotation/fbinfo quirks를 별도로 다룬다. 이것은 vendor EPDC 통합이 실제로 민감하다는
참고 증거이지만 kernel bug의 직접 증명은 아니다.

## 6. UPDATE_SCHEME analysis

### SNAPSHOT

`MXCFB_SEND_UPDATE` 호출 thread가 update buffer를 확보하고
`epdc_process_update()`를 직접 실행한다. `pxp_process_update()` 뒤
`pxp_complete_update()`가 DMA completion을 기다리므로 ioctl 반환 시점에는 RGB
framebuffer source가 internal processed buffer로 소비돼 있다. 이후 EPDC waveform
scan 완료까지 기다리는 것은 아니다.

### QUEUE

descriptor만 pending list에 넣고 workqueue를 깨운 뒤 ioctl이 반환한다. merge하지
않고 나중에 PxP가 framebuffer source를 읽는다.

### QUEUE_AND_MERGE

QUEUE와 같은 비동기 source-read semantics에 pending/collision descriptor merge가
추가된다. waveform/mode가 다르면 AUTO/FULL로 승격하고, touching rect도 merge
대상이다. current fork는 merge 시 최신 `fb_offset`과 queue timestamp를 선택한다.

### 실제 선택

| 구현 | default | userspace override | 실제 결론 |
|---|---|---|---|
| NXP 3.0.35 | Q&M | 가능 | Q&M |
| NXP 4.1/4.9/4.14/5.4 | Q&M | 가능 | Q&M |
| RIDI stock | kernel default 불문 | gralloc이 2 설정 | Q&M |
| RIDI current | Q&M | setter 호출 없음 | Q&M |

따라서 가장 먼저 할 A/B로 SNAPSHOT은 유용하지만, 그것은 stock 설정 복원이 아니라
source-lifetime/merge를 동시에 제거하는 **진단 모드**다.

## 7. Source lifetime 재평가

이전 host 결과의 “명백한 HWC contract violation” 표현은 너무 강하다. 더 정확한
분류는 **legacy fbdev queue semantics와 Android buffer ownership의 integration
contract mismatch 후보**다.

현재 흐름:

```text
SF writes framebuffer page N
-> FBIOPAN_DISPLAY selects N
-> MXCFB_SEND_UPDATE queues descriptor and returns
-> HWC returns releaseFenceFd=-1 / retireFenceFd=-1
-> later kernel workqueue starts PxP DMA from page N
```

current fork는 canonical NXP가 뒤늦게 global `fb_offset`을 읽던 문제를 고쳐 descriptor에
page N을 저장한다. 그러나 page N이 그 사이 다시 쓰이는 것을 막지는 않는다.
`copy_before_process()`도 rev>=2.0의 일반 aligned update에는 실행되지 않는다.

Host replay의 deferred-page-reuse case는 800 mismatch를 냈다. 이것은 hazard의
존재를 증명하지만 실기기에서 queue delay 안에 같은 page가 재사용됐다는 증명은
아니다. Stock도 Q&M async이므로 다음 중 어느 것이 안전성을 제공했는지 아직
미확정이다.

- stock의 native-landscape triple buffer cadence가 충분히 느림
- stock Netronix kernel이 공개 NXP와 다르게 source를 copy
- stock gralloc의 retry/producer scheduling이 page lifetime을 사실상 보장
- stock도 latent hazard를 가졌지만 workload가 노출하지 않음

분류: 사용자 요청의 세 선택지 중 **2번(NXP queue의 정상 semantics + integration
불일치)**가 가장 가깝다. 1번 “명백한 HWC contract violation”으로는 아직 확정하지
않으며, 3번 stock의 다른 안전 메커니즘도 binary/kernel trace 전에는 배제하지 않는다.

## 8. Driver bugs / missing backports

### 실제로 빠진 후속 NXP fix

화면 artifact와 관련된 확인된 missing backport는 찾지 못했다. `MLK-21590`의 firmware
string fix는 base에 없지만 current fork는 더 큰 buffer와 자체 parser로 같은 위험을
별도로 방어한다.

### 더 중요한 차이: missing stock vendor behavior

Stock 3.0.35에는 Netronix AA worker, advanced waveform fetch, PMIC exception rectangle
re-update 등 공식 NXP 4.9에 없는 기능이 있다. 현재 포팅은 일부를 새로 구현했지만
stock source와 semantic-equivalent인지 확인할 수 없다. 즉 위험은 “newer NXP patch
누락”보다 **old Netronix vendor extension의 불완전한 재구성** 쪽이 더 크다.

### Conditional collision loss

canonical/current `epdc_intr_work_func()`는 한 colliding LUT라도 current order 이상이면
collision을 무시한다. hardware collision rect가 여러 충돌의 bounding box일 때 newer
LUT coverage가 box 전체인지 검사하지 않는다.

추가 host test 결과:

- merge union containment: 50,000회, failure 0
- rotation round-trip: 200,000회, failure 0
- mixed older/newer collision model: newer가 10px bounding box 중 2px만 덮지만 전체
  retry가 drop되어 8px가 조건부 미해결

이는 production bug의 충분조건 model이지, 실제 hardware가 해당 mixed mask/bounds를
만들었다는 증명은 아니다. trace에서 collision mask의 LUT order와 각 submit rect를
수집해야 확정된다.

## 9. Cache / DMA coherency

Framebuffer는 `dma_alloc_writecombine()`로 할당되고 mmap도 write-combine pgprot를
사용한다. PxP source는 `smem_start + fb_offset + pxp_input_offs` physical address를
scatterlist에 직접 넣는다. 일반 framebuffer source에 `dma_map_single`/
`dma_sync_single_for_device`는 없다.

이 구조만 보면 의심스럽지만, DMA API상 `dma_alloc_writecombine`/`dma_alloc_wc`는
device-visible consistent allocation이므로 normal cached mapping의 누락 sync와는
다르다. NXP 공식 driver와 stock 계열도 같은 설계를 사용한다. 또한 2016년
`MLK-12179`의 software-processing cache range fix는 현재 들어 있다.

결론:

- classical “CPU cache에는 새 값, DMA에는 옛 값”은 낮은 가능성
- WC store ordering 또는 잘못된 별도 mapping 가능성은 완전히 0은 아님
- source mutation detector가 stable인데도 PxP input/output hash가 달라질 때만 cache
  hypothesis를 우선순위 올릴 것

## 10. Collision / merge

`epdc_submit_merge()`의 일반 rectangle union은 host fuzz에서 축소되지 않았다.
touching rect도 의도적으로 union하며 width/height는 exclusive end 기준으로 보존한다.
따라서 ordinary pending merge의 ±1 계산은 현재 증상을 재현하지 못했다.

남는 위험은 다음이다.

1. mixed-order collision bounding-box 전체 drop
2. collision retry가 physical 최소 rect를 inverse-rotate한 뒤 8x8 PxP 제약을 다시
   만족해야 하는 경로
3. stock Netronix 3.0.35와 current generic 4.9의 collision vendor 차이
4. collision 이후 gralloc shadow가 이미 성공으로 advance된 상태

현재 fork의 `collision_unaligned` copy-buffer 보완은 2번을 겨냥한다. 실기기에서 점/줄
발생 frame이 collision/resubmit과 상관없으면 이 트랙의 우선순위를 낮춘다.

## 11. Stride / rotation / PxP

서로 다른 pitch를 구분해야 한다.

- current logical RGB565: visible 1404, pitch 1408 / 2816 bytes
- stock native RGB565 target: visible 1872, pitch 1888 / 3776 bytes
- current kernel processed P5N: full output pitch는 1872 계열이며 partial은 aligned
  update geometry에 따라 결정

현재 ordinary path는 source address에 `src_width=xres_virtual=1408`을 사용하고,
visible clipping은 xres=1404를 사용한다. Host rectangle/rotation/PxP-offset fuzz
53,600건과 이 조사 추가 round-trip 200,000건에서는 pixel containment 손실이 없다.
1888은 current logical source pitch로 사용되지 않는다.

따라서 “코드 어디선가 1888과 1872를 단순 혼동”은 현재 확인되지 않았다. 다만 stock과
current가 회전을 담당하는 계층 자체가 달라 E70Q10 전용 마지막 4 source columns,
rotated first/last rows, `epdc_offs`는 실기기 A/B 대상으로 유지한다.

### UI line quality

current PxP fork의 P5N path는 Y8 LUT entry를 `& 0xF0`으로 만든다. 5-bit format이라는
이름/주석과 달리 4-bit granularity이며 dithering도 없다. RGB565->Y8 CSC, 이 LUT,
waveform gray mapping의 조합은 anti-aliased 1px line을 불균일하게 만들 수 있다.
이는 stale pixel과 분리해 black/white integer line, 4-bit gray, subpixel AA를 같은
waveform으로 비교해야 한다.

## 12. 실기기 복귀 후 최소 A/B 테스트

우선순위대로 8개만 수행한다.

1. **A — actual scheme 확인**: boot 직후 kernel에 current scheme을 1회 log하고 stock
   binary 결과(Q&M=2)와 대조한다.
2. **B — Q&M vs SNAPSHOT**: 동일한 상단 1px/Total Launcher sequence를 20회씩
   비교한다. SNAPSHOT은 진단용이며 production 결정은 아님.
3. **C — source mutation detector**: enqueue 시 source region/page hash, PxP 시작 직전
   같은 hash, `queue_us`, `fb_offset`을 기록한다. 변하면 lifetime 원인 확정.
4. **D — collision trace**: failed frame에서 collision mask, 각 LUT order, original/hw/
   inverse rect, ignore decision을 기록한다. mixed newer+older mask면 conditional bug를
   집중 검증한다.
5. **E — stock/current geometry**: current kernel을 native 1872x1404로 바꾸는 큰 수정
   대신, 준비된 deterministic edge pattern으로 source x=0/1403/padding과 processed
   first/last row hash만 비교한다.
6. **F — cold boot vs first resume**: suspend 전 20회와 첫 resume 후 20회를 비교하여
   ERR006287/dispmix 가능성을 분리한다.
7. **G — cache discriminator**: source hash가 stable일 때만 controlled DMA sync/barrier
   diagnostic을 한 번 A/B한다. 먼저 sync patch를 production에 넣지 않는다.
8. **H — line-quality matrix**: integer black/white, AA off/on, gray level ramp를 동일 rect/
   waveform으로 출력해 P5N quantization 문제를 독립 판정한다.

판정 기준:

- SNAPSHOT에서만 점/줄 소멸 + source hash mutation 관측: lifetime/integration 확정
- SNAPSHOT에서 소멸하지만 mutation 없음: merge/collision 제거 효과를 D로 구분
- collision 없는 frame에서도 발생: collision 가설 하향, PxP edge/P5N 쪽 상향
- suspend 이후에만 발생: ERR006287/power-domain 쪽 상향
- black/white 선은 정상이고 gray AA만 불량: P5N/AA quality track 확정

## 13. Production fix decision tree

```text
Q&M failure, SNAPSHOT pass
|
+-- source hash changes before PxP
|   -> source-consumed fence 또는 bounded snapshot 설계
|      (waveform completion WAIT는 불필요)
|
+-- source hash stable
    |
    +-- mixed-order collision/ignore 관측
    |   -> newer coverage 기준으로 collision region을 분할/retry하는 최소 patch 검토
    |
    +-- collision 없음
        -> PxP processed first/last row 및 P5N packing 검사

SNAPSHOT에서도 failure
|
+-- cold boot 정상, resume 뒤 failure
|   -> ERR006287/display-domain gating A/B
|
+-- processed buffer부터 틀림
|   -> PxP rotation/pitch/P5N path
|
+-- processed buffer 정상, panel만 틀림
    -> EPDC collision/waveform/panel interface trace

black/white geometry 정상, gray AA line만 불량
-> P5N LUT/quantization 및 stock Netronix AA semantic 비교
```

지금 단계에서는 update rect 확대, fullscreen refresh, waveform 변경, fence 임의 구현,
kernel 교체 중 어느 것도 근거가 충분하지 않다.

## Reproduction artifacts

- 기존 panel replay: `device/ridi/e70q10/tools/epdc_panel_replay.py`
- 기존 test: `device/ridi/e70q10/tools/test_epdc_panel_replay.py`
- 이번 driver semantics test:
  `device/ridi/e70q10/tools/test_epdc_driver_semantics.py`
- 실행 결과:
  `.orchestrator/logs/epdc-driver-archaeology/driver-semantics.json`

실행:

```bash
python3 device/ridi/e70q10/tools/test_epdc_driver_semantics.py \
  --iterations 50000 --seed 3696
```

## Sources

- NXP linux-imx: <https://github.com/nxp-imx/linux-imx>
- i.MX6SoloLite chip errata Rev. 5:
  <https://www.nxp.com/docs/en/errata/IMX6SLCE.pdf>
- NXP Linux reference manual:
  <https://www.nxp.com/docs/en/reference-manual/i.MX_Reference_Manual.pdf>
- FBInk (Kobo framebuffer/rotation observations):
  <https://github.com/NiLuJe/FBInk>
- KOReader MXCFB alignment handling:
  <https://github.com/koreader/koreader-base/blob/master/ffi/framebuffer_mxcfb.lua>
- reMarkable NXP EPDC reference material:
  <https://github.com/canselcik/libremarkable/blob/master/reference-material/mxc_epdc_fb.c>

