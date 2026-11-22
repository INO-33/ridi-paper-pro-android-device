# E70Q10 화면 경로: 큰 복사와 NEON 수정 방향

작성일: 2026-11-17 · 상태: 구현 전 설계 맥락

이 문서는 화면 출력 경로에서 CPU가 하는 전체 프레임 복사와 픽셀 루프를 줄이기 위한
네 가지 수정 방향을 정리한다. 줄 번호는 작성일 트리 기준이다. 코드가 바뀌면 함수
이름으로 다시 찾는다.

증거 표기는 `EPDC_DRIVER_ARCHAEOLOGY.md`를 따른다.

- **SOURCE-CONFIRMED**: 현재 소스에서 직접 확인
- **MEASURED**: 이 트리의 기존 벤치/덤프 값
- **TO-MEASURE**: 구현 전후에 측정해서 판단

## 0. 현재 경로와 공통 전제

```text
앱 Skia(CPU, NEON) -> RGBx/RGBA_8888 ashmem 버퍼
-> SurfaceFlinger HWC1 + libagl/PixelFlinger(CPU) -> RGB565 fb 페이지 (3장, write-combine)
-> hwc_set -> gralloc fb_post: shadow 비교, 영역 계산, MXCFB_SEND_UPDATE (post당 최대 6회)
-> mxc_epdc_fb: SEND ioctl 안에서 source snapshot 복사
-> submit work에서 PxP (RGB565->Y, ROT270, histogram) -> EPDC WB/LUT
```

- fb 페이지 1장은 line_length 2816 x 1872 = 5,271,552 B다. `info->screen_base`는
  `dma_alloc_writecombine`(mxc_epdc_fb.c:7820), 사용자 mmap은
  `pgprot_writecombine`(:2728)이다. 따라서 fb에 대한 CPU 읽기는 uncached다.
  SOURCE-CONFIRMED
- 5.3 MB uncached->cached memcpy는 26.5 ms, PxP 전체 프레임 XRGB->RGB565+회전은
  24.1 ms다(`GRAPHICS_BRINGUP.md`, `pxp_bench`). MEASURED
- `sf_good.txt:189-192`: 전체 화면 앱 레이어는 RGBx_8888이고 상태바와 퀵패널은
  RGBA_8888이다. 모든 레이어가 GLES로 합성되고 FB target은 RGB_565다. MEASURED
- 커널 통계 `/sys/class/graphics/fb0/e70q10_page_lifetime_stats`는
  `ridi,e70q10`에서 기본 활성이다(mxc_epdc_fb.c:7721). snapshot_copies,
  snapshot_partial, snapshot_bytes, collision 계열, source_reused_before_pxp,
  source_reused_before_copybuf가 들어 있다.

### 공통 규칙

- 각 변경은 property 또는 sysfs로 켜고 끈다. 끈 상태는 현재 동작과 같아야 한다.
- 성능 판단은 부분 지표 하나(예: 비교 시간)로 하지 않는다. §5의 end-to-end 지표로
  판단한다.
- 범위 밖: 작은 부분 복사(커널 band snapshot :722, libagl buffer-age `copyBlt`,
  `copy_before_process`)는 다루지 않는다.

## 1. 커널 snapshot 전체 복사를 원본 소비 완료 release fence로 대체

### 현재 SOURCE-CONFIRMED

- HWC가 FB target release fence를 `-1`로 돌려준다(hwcomposer.cpp:413). 그래서
  SurfaceFlinger는 post 직후 같은 페이지를 다시 쓸 수 있다.
- 커널은 이를 막으려고 SEND ioctl 안에서 원본을 snapshot 슬롯으로 복사한다.
  - 호출 경로: `__mxc_epdc_fb_send_single_update` ->
    `e70q10_source_snapshot_acquire_locked`(:5133)
  - 전체 복사 함수: `e70q10_copy_frame_to_snapshot_locked`(:622). 5.27 MB를 CPU
    memcpy로 복사하고, 그동안 `queue_mutex`를 잡고 있다.
- 전체 복사로 가는 경우:
  - AUTO/PARTIAL이 아닌 모든 요청: 앱 지정 waveform, WAIT, sleep, cleanup
  - flags나 marker가 있는 요청, source bounds가 없거나 맞지 않는 요청
  - coalesce/deferred 경로(:3632-3840)
  - `e70q10_promote_deferred_snapshot_locked`(:745): 스냅샷끼리 5.27 MB 복사

### 불변식 (구현이 지켜야 할 것)

1. SurfaceFlinger(libagl)가 페이지에 쓰기 시작하기 전에, 그 페이지를 원본으로 읽을 수
   있는 모든 update descriptor가 terminal이어야 한다.
2. 1번에는 한 post의 여러 SEND, merge, coalesce, collision 재처리가 모두 포함된다.
3. signal 시점은 원본을 더 이상 읽지 않는 시점, 즉 descriptor terminal이다. EPDC
   파형(LUT) 종료까지 기다리지 않는다.
4. fence는 정상, 지연, 오류, 취소 어느 경우에도 반드시 signal된다.
   - libagl은 dequeue fence를 `Fence::TIMEOUT_NEVER`로 기다린다(egl.cpp:445-446,
     673-674).
   - 따라서 signal이 한 번 빠지면 SurfaceFlinger가 영구 정지한다.
5. gralloc shadow(비교 기준)는 유지한다. fence는 원본 보호용이지 shadow를 대신하지
   않는다.

### descriptor가 원본을 읽는 곳 SOURCE-CONFIRMED

| 시점 | 위치 |
|---|---|
| PxP 처리 (submit할 때마다) | `epdc_submit_work_func` :4632 -> `epdc_process_update` :3848 -> `tx_submit` :8964 |
| 정렬 안 된 collision 재시도 | `copy_before_process` :3367 (원본 -> copybuf) |
| collision 후 재처리 | WB 완료 시 collision이면 collision list로 감(:6908). 이후 :4440에서 다시 선택돼 PxP 재처리하면서 **원본을 다시 읽음** |
| PxP 없는 직접 경로 | :4591 조건 (회전 UR, 8bit, rev>20). EPDC가 파형 동안 원본을 직접 읽음. E70Q10은 CCW, RGB565, rev 20이라 쓰이지 않음 |

### 해제 지점 = 지금 snapshot ref를 놓는 지점 SOURCE-CONFIRMED

현재 snapshot 수명은 이미 "descriptor가 terminal이 될 때까지"로 맞춰져 있다(주석
:506). 그러므로 page hold를 같은 지점에 걸면 된다.

- `epdc_free_update_desc_locked`(:525)의 모든 호출 지점
  - WB 완료이면서 collision이 없거나 무시된 경우(:6949). 정상 경로이고 파형 종료
    전이다.
  - merge로 흡수된 경우(:4474, :4548), coalesce(:3699, :3826)
  - recovery 실패(:2478), submit 오류(:5154, :5178, :5254)
- merge가 새 원본을 채택하는 경우: `e70q10_source_snapshot_adopt_newer_locked`(:855,
  호출 :4357)
  - 합쳐진 desc는 더 새 페이지를 읽는다.
  - hold를 새 페이지로 옮기고, 이전 페이지 ref는 놓는다.
  - 근거: buffer-age repair 덕분에 각 페이지는 항상 완전한 프레임을 담는다.

### 커널 설계 (mxc_epdc_fb.c, uapi mxcfb.h)

- **page hold 객체**
  - 필드: `{page, generation, refs, struct fence, sealed, created_jiffies, in_flight, delayed_work}`
  - generation은 pan 때 증가한다(:6314).
- **fence 모드의 SEND**
  - snapshot 대신 desc가 캡처한 `fb_offset`의 hold에 ref를 건다(`desc->source_hold`).
  - source bounds, snapshot 슬롯, 슬롯 부족(EBUSY) 때의 coalesce는 쓰지 않는다.
  - 지금의 EBUSY는 슬롯 부족에서 나오므로 fence 모드에서는 사라진다. Q&M merge는
    그대로 유지한다.
- **merge 판단**: `e70q10_snapshot_covers_rect`(:562)는 hold를 전체 프레임 원본으로
  취급한다.
- **signal 조건**: `refs == 0 && sealed`이면 `fence_signal`한다.
- **ioctl**: 아래 둘을 추가한다. 0x3b와 0x3c는 현재 mxcfb.h에서 쓰지 않는다. 기존
  E70Q10 ioctl은 0x39와 0x3a다.

  ```c
  #define MXCFB_E70Q10_SET_SOURCE_MODE  _IOW('F', 0x3b, __u32) /* 0 snapshot(기본), 1 fence */
  struct mxcfb_e70q10_source_fence {
      __u32 fb_offset;  /* in: 방금 post한 페이지 */
      __u32 flags;      /* in: 0 */
      __s32 fence_fd;   /* out: sync_file fd, 읽는 desc가 없으면 -1 */
      __u32 seqno;      /* out: 진단용 */
  };
  #define MXCFB_E70Q10_GET_SOURCE_FENCE _IOWR('F', 0x3c, struct mxcfb_e70q10_source_fence)
  ```

  - GET은 해당 (page, generation) hold를 seal하고 fence를 만든다.
  - seal 이후 같은 generation에 들어오는 SEND(슬립 오버레이 등)는 새 hold를 만든다.
  - 기본 모드는 snapshot이다. gralloc이 초기화 때 fence 모드를 요청한 경우에만
    전환해서 구 userspace와 호환을 유지한다.

### 지연 fallback

- fence 모드에서는 desc가 오래 살아 있으면 SurfaceFlinger가 dequeue에서 그만큼
  멈춘다. collision 연쇄나 LUT 대기가 원인이다. 지금 snapshot 방식에는 없던
  backpressure다. TO-MEASURE
- 그래서 hold마다 타이머를 둔다.
  - 설정: sysfs `e70q10_source_hold_ms`, 초기값 100, 0이면 끔
  - 만료 시: 아직 살아 있는 desc의 영역만 기존 band snapshot 경로로 복사한다. desc를
    snapshot 원본으로 바꾸고 hold ref를 놓는다.
  - 카운터: `hold_late_snapshot`, `hold_late_bytes`
- **경쟁 조건**: PxP 처리 중에는 `queue_mutex`가 풀려 있다(:4628-4632).
  - 그 desc가 `in_flight`이면 타이머는 원본만 snapshot으로 돌려 둔다.
  - hold ref는 그 PxP 패스가 끝난 뒤에 놓는다.
  - 진행 중인 DMA가 아직 페이지를 읽고 있으므로, 그 전에 signal하면 안 된다.
- **절대 watchdog** (예: 2 s): WARN 후 위와 같이 처리한다. snapshot 슬롯도 없으면
  `status = -ETIMEDOUT`로 signal한다. 화면 잔상 위험이 시스템 정지보다 낫다.
- fallback용 snapshot 슬롯 할당(:8061)은 유지한다.

### 오류와 취소

- 다음 경로에서 desc를 정리할 때 hold ref도 함께 풀리게 한다: blank/suspend,
  recovery, 큐 flush, 드라이버 remove, PxP 실패.
- 그래도 남은 hold는 `status`를 -ECANCELED 또는 -EIO로 설정한 뒤 signal한다.
- **4.9 API 주의**
  - 이 커널은 `dma_fence`가 아니라 `struct fence`다(include/linux/fence.h, `int status`).
  - `status`는 `fence_signal` 전에 설정한다.
  - `sync_file_poll`은 오류 status여도 POLLIN만 반환한다(sync_file.c:315). libsync
    `sync_wait`는 POLLERR만 오류로 본다(sync.c:117).
  - 그러므로 오류로 signal된 fence도 SurfaceFlinger 대기를 푼다. 오류값은 진단용이다.
- **fence_ops**
  - 콜백: `get_driver_name`, `get_timeline_name`, `enable_signaling`(true 반환),
    `wait = fence_default_wait`
  - `fence_context_alloc(1)`은 한 번만 호출하고, hold마다 seqno를 늘린다.
  - fd는 `sync_file_create` + `get_unused_fd_flags(O_CLOEXEC)` + `fd_install`로 만든다.

### userspace 연결

- **gralloc** (framebuffer.cpp)
  - `fb_post`(:1926)의 마지막 SEND가 끝나면 GET_SOURCE_FENCE를 호출하고, fd를
    context에 보관한다.
  - 새 확장 `reserved_proc[3]` = `int fb_takeReleaseFence(dev)`를 둔다. 기존 확장은
    [0..2]다(:2274-2278).
  - SEND가 없던 post(동일 프레임 억제, policy disable)는 -1을 돌려준다.
- **HWC** (hwcomposer.cpp): post(:463) 뒤에 FB target `layer.releaseFenceFd`에 그 fd를
  넣는다. retire fence는 -1로 둔다.
- **SurfaceFlinger**: 받을 준비가 이미 돼 있다.
  - `HWComposer::getAndResetReleaseFence`(HWComposer_hwc1.cpp:816)는 API 1.1 이상에서
    동작한다. 현재 HWC는 1.5다(hwcomposer.cpp:704).
  - `FramebufferSurface::onFrameCommitted`(FramebufferSurface.cpp:255-261)가 fence를
    현재 slot에 붙이고, 다음 acquire 때 release한다.
  - 이후 libagl이 dequeue에서 그 fence를 기다린다.
- **슬립 오버레이**
  - `m->currentBuffer`, 즉 현재 표시 중인 페이지에 직접 쓴다(framebuffer.cpp:1730, 1768).
  - fence 모드에서는 쓰기 전에 그 페이지의 hold fence를 기다린다. 타임아웃이면 이번
    한 번은 snapshot 모드로 제출한다.
- **libagl `copyBlt`**: 이전 페이지를 읽기만 하므로 영향 없다.

### 대안 비교

- `UPDATE_SCHEME_SNAPSHOT`도 원본 복사가 없다. PxP를 ioctl 안에서 끝내기 때문이다
  (ARCHAEOLOGY §6, :5247).
- 대신 SEND마다 SurfaceFlinger가 PxP 완료를 동기로 기다리고, Q&M merge도 없어진다.
- 그래서 비교용 진단 모드로만 쓰고, 운영 경로는 fence로 간다.

### 검증

- fence 모드에서 snapshot을 끈 상태로 다음 두 카운터가 0을 유지해야 한다:
  `source_reused_before_pxp`, `source_reused_before_copybuf`.
  - 단, generation은 다시 pan할 때만 증가한다(:6314). 그래서 "다시 post되기 전에
    쓰기"는 이 카운터로 잡지 못한다.
  - 디버그 빌드에서 desc 영역 CRC를 SEND 시점과 `tx_submit` 직전에 계산해 불일치
    횟수를 센다. 0이어야 한다.
- 스트레스 시나리오
  - 빠른 스크롤, 같은 영역 연속 입력(collision 연쇄)
  - Settings REAGL, 리더 페이지 넘김
  - 큐가 찬 상태에서 blank/unblank, 슬립 진입, recovery 강제, PxP 100 ms 초과 경로
- 측정 TO-MEASURE
  - snapshot_bytes는 0에 가까워져야 한다.
  - hold_late_* 카운터
  - SurfaceFlinger dequeue 대기 시간: libagl의 fence wait 앞뒤에 계측을 넣는다.
  - post에서 화면 반영까지의 지연

### 하지 말 것

- PxP 완료 시점에 signal하지 않는다. collision이면 재처리하면서 원본을 다시 읽는다.
- LUT 완료까지 hold하지 않는다. SurfaceFlinger를 불필요하게 막는다.
- release fence 자리에 retire fence를 쓰지 않는다.

## 2. gralloc 큰 damage 비교: 생략하지 말고 범위를 줄인다

### 현재 SOURCE-CONFIRMED (framebuffer.cpp)

- 누적 damage가 화면의 35% 이상이면 `direct_validation=false`가 된다
  (`EPDC_FULL_AREA_PERCENT` :89, 판정 :1247-1252).
- 그러면 damage와 상관없이 **전체 프레임**을 스캔한다(:1270).
  - `cache_epdc_scan_region`(:653, :1281): 5.27 MB를 WC fb에서 캐시 버퍼로 읽는다.
    26.5 ms 규모다.
  - 이어서 `find_changed_regions`(:770, :1286)를 돈다.
- 작은 damage는 이미 ROI + 8px halo만 스캔한다(:1257).
- HWC는 geometry 변경과 damage UNKNOWN도 전체 화면 rect로 넘긴다
  (hwcomposer.cpp:299-325). 그래서 지금 gralloc은 "SurfaceFlinger가 실제로 기술한 큰
  damage"와 "대체용 전체 화면"을 구분하지 못한다.

### 그냥 생략하면 안 되는 이유

- 앱이나 SurfaceFlinger의 damage는 실제 변경보다 넓을 수 있다.
- damage를 그대로 제출하면 비교 비용은 줄지만 다음이 늘 수 있다.
  - 커널 snapshot 복사량 (snapshot 모드일 때)
  - PxP 처리량
  - EPDC 갱신 충돌
- 동일 프레임 제출 억제를 유지해야 한다(:1362-1388).
  - 변경이 없으면 SEND하지 않는다.
  - 예외: cleanup과 앱의 FULL 요청은 변경이 없어도 전체를 제출한다.
  - 영역 수 초과(`region_count < 0`)면 전체를 제출한다.
- 경계 보정도 유지해야 한다: `align_epdc_region` 8px(:604), halo,
  `merge_epdc_regions`(:1015, 제출 최대 6).

### 변경

1. HWC가 damage 출처를 함께 넘긴다: SurfaceFlinger가 기술한 damage인지,
   geometry 변경이나 UNKNOWN을 대신하는 전체 화면인지. 확장 함수를 추가하거나
   `setUpdateRect` 확장으로 넘긴다.
2. 기술된 damage면 35% 이상이어도 스캔 범위를 누적 damage ROI + halo로 제한한다.
   - ROI 안에서는 지금처럼 64px 타일로 실제 변경 영역을 찾는다(최대 12, 제출 6).
   - 결과가 0이면 제출하지 않는다.
3. 전체 스캔은 다음 경우에만 한다: 대체용 전체 화면, cleanup, shadow 무효.
4. ROI 밖 신뢰성 확인용 디버그 모드를 둔다(property 예: `debug.ridi.epdc.audit_roi`).
   - ROI 스캔 뒤 ROI 밖도 스캔해서 놓친 변경을 센다.
   - 시나리오 전체에서 0이어야 기본으로 켠다.
5. (선택) 비교 루프를 NEON으로 바꾼다.
   - 현재 bionic `memcmp`의 NEON 경로는 꺼져 있다. `NEON_UNALIGNED_ACCESS`가 정의되지
     않았다(generic/bionic/memcmp.S).
   - 타일 행 128 B 비교를 NEON 헬퍼로 바꾼다.

### 유지할 것

- shadow의 의미: 마지막으로 패널에 제출한 프레임
- 동일 프레임 억제와 그 예외(cleanup, 앱 FULL, 영역 수 초과), 8px 정렬, halo, merge
- `outside_input` 진단(:1291), pending damage 누적

### 측정 (비교 시간만 보지 않는다)

- gralloc
  - fb_post 시작부터 마지막 SEND 반환까지의 시간
  - 스캔 바이트
  - 제출 영역 합계와 개수
- 커널
  - PxP 처리 면적과 시간
  - WB 완료까지의 시간
  - collision_created, retry 계열 카운터
  - snapshot_bytes (snapshot 모드일 때)
- 화면: audit 모드에서 놓친 변경 0, 잔상과 누락 없음

## 3. SurfaceFlinger 합성 8888->565를 NEON으로

### 현재 SOURCE-CONFIRMED (system/core/libpixelflinger)

- PixelFlinger의 NEON은 단색 블렌드 `col32cb16blend_neon.S` 하나뿐이다
  (Android.mk:35-37, `-D__ARM_HAVE_NEON`).
- 1:1 8888 SRC: `scanline_t32cb16`(scanline.cpp:2132). 스칼라 C로 한 번에 2픽셀.
- 1:1 8888 SRC_OVER: `scanline_t32cb16blend`(:2181) -> `t32cb16blend.S`.
  - ARM 스칼라 코드다.
  - dst를 32bit(2픽셀)씩 읽는데, fb가 WC라서 읽을 때마다 uncached 접근이 된다.
- 1:1 x888(RGBx_8888) SRC
  - shortcut 표(:190-262)에 1:1 항목(t0=0x00000A02)이 없다.
  - 그래서 JIT(GGLAssembler, ARM 스칼라)로 갈 가능성이 높다.
  - 전체 화면 앱 레이어가 바로 이 형식이다.
- SurfaceFlinger는 GL_DITHER를 끈다(GLES11RenderEngine.cpp:43). 그래서 dither
  변형은 대상이 아니다.

### 1단계: 실제 경로 확인

- `DEBUG_NEEDS`(:72)를 켜거나, `pick_scanline`(:328)에 1회성 로그를 넣는다. 로그는
  property로 켜고 끈다.
  - 기록할 내용: needs의 n, p, t0, t1과 선택된 shortcut 이름 또는 JIT 여부
- 수집할 화면: 런처, 리더, Settings, 상태바, 다이얼로그

### 구현

- shortcut을 추가한다. 기존 항목보다 앞에 두고 `__ARM_HAVE_NEON`으로 게이트한다.
  - **565 fb, 8888/x888 tx, SRC, 1:1**
    - 한 번에 8픽셀: `vld4.8` -> `vshll.u8 #8`, `vsri.16`로 565 pack -> `vst1.16`
  - **565 fb, 8888 tx, SRC_OVER, 1:1**
    - NEON 블렌드
    - dst를 `vld1.16`으로 8픽셀씩 읽어서 WC 읽기 횟수를 줄인다.
- 앞뒤 잔여 픽셀과 `uintptr_t(dst)&2` 정렬은 기존 C 코드가 처리한다.
- 결과는 기존과 **비트 단위로 같아야** 한다.
  - SRC: `convertAbgr8888ToRgb565`(:144)의 절삭 방식
  - SRC_OVER: `blender_32to16`(:1170)과 같은 식
    - s==0이면 건너뛴다.
    - sA==0xff이면 변환해서 복사한다.
    - 그 밖에는 f = 0x100 - (sA + (sA>>7))이고, 채널별로 s5/6 + (f*d)>>8
- 테스트
  - 무작위 입력, 모든 alpha, 길이 1..64, dst 정렬 0과 2에서 C 결과와 비교한다.
    `tests/arch-arm64/t32cb16blend` 형식을 참고한다.
  - 기기에서 같은 화면의 screencap을 바이트 단위로 비교한다.
- 측정: SurfaceFlinger 합성 시간(systrace `doComposition`,
  `dumpsys SurfaceFlinger --latency`)
- 범위 밖: PxP로 합성을 대신하는 것.
  - 앱 버퍼가 ashmem(gralloc.cpp:221)이라 PxP가 직접 읽지 못한다.
  - ION CMA 할당으로 바꾸는 일이 먼저 필요하므로 별도 과제다.

## 4. 슬립 오버레이: NEON 블렌드와 WC 재읽기 제거

### 현재 SOURCE-CONFIRMED (framebuffer.cpp:1691-1925)

- 알파 bounding box 안을 세 번 순회한다.
- 블렌드 `blend_straight_argb_over_rgb565`(:1603)는 스칼라 코드다. 픽셀마다 /255,
  /31, /63 연산을 한다.
- 세 번째 패스(:1910)는 `shadow_row[x] = framebuffer_row[x]`로 WC fb를 16bit씩
  읽는다. 픽셀마다 uncached 읽기다.
- 빈도는 슬립 진입 1회로 낮다. 그래도 전체 화면 이미지면 절전 진입 지연에 그대로
  더해진다.

### 변경

- 세 번째 패스에서 fb를 읽지 않는다.
  - 대신 `blend(source, 이전 shadow)`를 다시 계산해 shadow에 쓴다. 같은 함수라 값이
    같다.
  - 제출되지 않은 픽셀의 복원은 shadow -> fb 쓰기만 한다.
- NEON으로 한 번에 8픽셀을 블렌드한다. 결과는 비트 단위로 같아야 한다.
  - (v + 127)/255에서 v는 최대 255*255+127 = 65152다. t = v + 127로 두면
    (t + 1 + (t>>8)) >> 8이 정확한 몫이다.
  - `rgb565_red/green/blue`(:1581)의 확장과 `pack_rgb565`(:1595)는 LUT나 같은
    정확한 나눗셈으로 처리한다.
- 방향 1(fence 모드)과 함께 쓸 때: 오버레이는 현재 표시 페이지에 쓰므로, 쓰기 전에 그
  페이지의 hold fence를 기다린다.
- 테스트
  - 무작위 ARGB x RGB565 샘플에서 스칼라 결과와 비교한다.
  - 실제 슬립 이미지의 결과를 바이트 단위로 비교한다.
  - `fb_submitEinkSleepOverlay` 소요 시간을 잰다.

## 5. 공통 측정

각 시나리오를 같은 콘텐츠로 30회 이상 반복한다.

- 리더 페이지 넘김 (앱 지정 waveform)
- Settings 스크롤 (REAGL)
- 런처 페이지 이동
- 같은 영역 연속 키 입력 (collision)
- 퀵패널 열기/닫기 (RGBA 블렌드)
- 슬립 진입

| 지표 | 출처 |
|---|---|
| SF 합성 시간 | systrace, `dumpsys SurfaceFlinger --latency` |
| fb_post 시작부터 마지막 SEND 반환까지 | gralloc 계측 추가 |
| 스캔 바이트, 제출 영역 합계와 개수 | gralloc 계측 추가 |
| snapshot_copies / snapshot_partial / snapshot_bytes | `e70q10_page_lifetime_stats` |
| collision_created, retry 계열 | 같은 파일 |
| PxP 처리 시간과 면적 | 커널 계측 추가 (`tx_submit`부터 완료 콜백까지) |
| SF dequeue fence 대기 | libagl 계측 추가 (방향 1) |
| hold_late_snapshot, hold_late_bytes | 방향 1에서 추가하는 카운터 |
| source_reused_*, 디버그 CRC 불일치 | 0이어야 함 |

## 진행 순서

- 권장 순서는 1 -> 2 -> 3 -> 4다.
- 1과 4는 슬립 오버레이에서 만난다. 4를 먼저 하면 fence 대기 부분은 1을 할 때 추가한다.
- 2와 3은 서로 독립이다.
