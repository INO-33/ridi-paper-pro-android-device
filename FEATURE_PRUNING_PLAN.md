# E70Q10 Android 8 feature-pruning plan

> This is the detailed pruning checklist. The authoritative execution order is
> now [`FINAL_PORTING_PLAN.md`](FINAL_PORTING_PLAN.md). The target application
> is YES24 and the target home application is Total Launcher; the stock RIDI
> application is reverse-engineering reference only.

## Goal

Build an Android 8.0 userspace for the RIDI Paper Pro E70Q10 that contains
only the Android runtime and hardware support required by YES24 and Total
Launcher on a dedicated e-reader.

Android 8.0 is the first Android release with Project Treble. The E70Q10 was
not launched as a Treble device, so full Treble compliance is not a bring-up
goal. However, the NXP Oreo BSP and SurfaceFlinger still require a minimal
HIDL/VNDK foundation. Do not remove that foundation merely to reduce image
size.

The reference product now inherits the E70Q10 positive reader allowlist rather
than `generic_no_telephony`. The latter still imported phone, Bluetooth, NFC,
printing, calendar, contacts, mail, music and decorative applications.

## Hardware-backed functions to retain

- i.MX6SL CPU, memory controller, clocks and pin control
- E Ink EPDC framebuffer and waveform loading
- TPS65185 E Ink panel power sequencing
- RC5T619 PMIC, battery and charging status
- ED078KH3 panel timing and the verified 16-bit EPDC bus configuration
- frontlight control
- CYTTSP5 touchscreen
- physical-button key layout
- external SD storage
- USB gadget, ADB during bring-up, and later MTP if required
- suspend, resume, shutdown, watchdog and RTC wake
- RTL8189FTV Wi-Fi in station mode for book download and authentication

## Android and Oreo infrastructure that must remain

Removing these components would prevent Android framework startup or the
graphics path from working:

- `init`, `ueventd`, property service and SELinux policy loading
- `servicemanager`, `hwservicemanager` and `vndservicemanager`
- Binder and HwBinder
- Zygote, ART and Bionic
- ActivityManager, PackageManager and WindowManager
- SurfaceFlinger and InputFlinger
- SettingsProvider
- keystore, certificate handling and TLS
- `vold` and external-storage support
- `logd`, watchdog and battery/charger handling
- USB gadget support
- ADB and shell in engineering builds
- `android.hardware.graphics.allocator@2.0`
- `android.hardware.graphics.mapper@2.0`
- `android.hardware.graphics.allocator@2.0` and mapper 2.0 remain for buffer
  allocation; the selected initial display path uses direct HWC1 and does not
  package graphics composer 2.1
- the required HIDL libraries and `vndk-sp`
- a minimal device VINTF manifest

The KitKat graphics and EPDC HAL binaries are not ABI-compatible with Oreo.
Their behaviour can be used as a reference, but the implementation must be
rebuilt against the Oreo interfaces.

## Features to exclude immediately

These features have no corresponding E70Q10 hardware or no e-reader use case:

| Area | Remove or avoid |
| --- | --- |
| Cellular | RIL, telephony provider, Phone, SMS/MMS, CellBroadcast, SIM Toolkit |
| NFC | NFC app, NFC HAL and secure-element services |
| Location | GPS/GNSS HAL, FusedLocation and network-location packages |
| Bluetooth | Bluetooth app/HAL, BLE declarations, A2DP and AVRCP |
| Camera | Camera app, camera provider/HAL and camera-specific encoders |
| Sensors | sensors HAL and sensor feature declarations |
| Other HALs | vibrator, fingerprint and consumer-IR HALs |
| Form factors | TV, Leanback, Automotive and Wear packages |
| Decoration | live wallpapers, wallpaper picker, dreams and photo table |
| Printing | PrintSpooler and printer-recommendation services |
| Voice | TTS engines, speech recognition and voice dialling |
| Google | GMS, Play Store, Google SetupWizard and Google location services |
| Testing | CTS/VTS payloads, test apps, sample HALs and benchmarks |
| Update | A/B OTA, `update_engine`, snapshot and boot-control HAL |

The stock KitKat image declares Bluetooth even though the identified
RTL8189FTV chip is Wi-Fi-only. Treat that Bluetooth stack as inherited generic
NXP product baggage unless another radio is physically identified.

## Wi-Fi scope

Wi-Fi is excluded from the first RAM-boot image to reduce bring-up variables.
Add it to the reader profile only after the base framework reaches
`sys.boot_completed`.

Retain:

- the verified RTL8189FTV/RTL8189FS kernel driver
- Wi-Fi firmware and board-specific configuration
- `wpa_supplicant`
- DHCP client and `netd`
- Android Wi-Fi framework/service
- certificate storage and TLS support
- the Wi-Fi section of Settings

Exclude unless testing proves a requirement:

- `hostapd`
- SoftAP and tethering
- Wi-Fi Direct/P2P
- Passpoint
- network-location collection

## Audio and media scope

No speaker, microphone, DAC or audio codec has been identified in the hardware
report. Initially exclude:

- primary, USB, remote-submix and A2DP audio HALs
- AudioFlinger device configuration
- OMX and MediaCodec hardware codecs
- music and video applications
- video recording and encoding support

Do not confuse Android media playback with document rendering. Retain:

- Skia
- PNG, JPEG and WebP image decoding
- FreeType, HarfBuzz and the required fonts
- PDF/EPUB renderer dependencies
- SurfaceFlinger and the EPDC graphics path

Android DRM/media services and YES24 content protection are also separate.
Determine YES24's actual DRM dependencies before removing framework DRM
components.

## Application disposition

The following classification is based on the extracted stock filesystem.

### Initial retain candidates

- YES24 and Total Launcher only after the reference system boots reliably
- Korean input method
- Settings and SettingsProvider
- SystemUI and disabled-by-policy Keyguard framework support
- InputDevices
- DownloadProvider
- DocumentsUI
- ExternalStorageProvider
- MediaProvider
- PackageInstaller
- CertInstaller
- Shell in engineering builds only
- Launcher2 as a recovery HOME until Total Launcher is packaged in `/system`
- WebView for YES24 login/store flows
- proxy and captive-portal components until Wi-Fi authentication is validated

### Removal candidates

- Bluetooth, NFC, telephony, Telecom and MMS
- contacts, calendar, email and standalone Browser
- camera, gallery, music, MusicFX and TTS
- printing, dreams, wallpapers and Easter egg
- FusedLocation and ManagedProvisioning
- PacProcessor when proxy support is not required
- ProxyHandler when proxy support is not required
- Suconfig in production
- DefaultContainerService after the Oreo package-install path is verified

### Quarantine pending dependency analysis

- `iToast_v0.1.6`
- `MsgE6`
- `com.wordwebsoftware.android.wordweb`

These stock proprietary applications may document frontlight UI, device
messages, dictionary integration or other hardware behaviour. They are
reverse-engineering references, not product dependencies. Inspect their
manifest, native-library dependencies and runtime calls before reimplementing
only the required hardware behaviour.

## WebView decision

WebView is relatively large, but YES24 may use it for login, payment, notices,
dictionary content or book rendering.

1. Start with WebView present in the reader profile.
2. Record YES24 startup and representative login, download and reading
   workflows.
3. Check process, ActivityManager and log output for WebView use.
4. If unused, remove both Browser and WebView.
5. If used, retain WebView but remove the standalone Browser application.

## Resource and framework reductions

- package only Korean and English resources
- retain only the density needed by the 1404 x 1872 panel
- configure a single Android user
- hide the multi-user UI
- lock the product UI to portrait unless an application requires rotation
- omit boot animation
- omit 64-bit userspace; i.MX6SL is a 32-bit ARM platform
- minimize Java and native debug information in release images
- omit user-facing backup services
- keep zRAM or equivalent memory pressure support because the device has 1 GiB
- keep recovery until a proven alternative recovery path exists

Production builds must restore secure ADB policy and move from permissive to
enforcing SELinux. Engineering-only shortcuts must not become release
defaults.

## Product profiles

### 1. `e70q10_minimal`

Purpose: RAM-boot and basic Android framework bring-up.

- kernel, DTB and ramdisk
- graphics, EPDC, touch and physical buttons
- power, battery, watchdog and external SD
- ADB, shell and verbose logging
- no Wi-Fi or reader applications

Exit criteria:

- repeatable RAM boot without eMMC writes
- ADB remains responsive
- `sys.boot_completed=1`
- touch, buttons and EPDC updates remain stable
- watchdog recovers a userspace or kernel hang

### 2. `e70q10_reader`

Purpose: functional e-reader validation.

- Wi-Fi station mode
- download and external-storage providers
- Korean input and fonts
- YES24
- Total Launcher with a fallback HOME activity
- WebView retained until measured
- final frontlight and EPDC policy
- no camera, audio, Bluetooth, cellular, NFC or GMS

Exit criteria:

- login and book download work
- DRM-protected and unprotected books open
- cover, EPUB and PDF rendering work
- suspend/resume and Wi-Fi reconnection work
- repeated page turns do not leak memory or accumulate unacceptable ghosting

### 3. `e70q10_user`

Purpose: recoverable production image.

- secure ADB or ADB disabled by default
- SELinux enforcing
- release signing
- debug and tracing tools removed
- recovery/update path proven before any eMMC installation
- only dependencies observed in reader-profile testing retained

## Implementation policy

Prefer a positive package allowlist based on `core_minimal.mk`. Avoid inheriting
the complete NXP EVK product and then trying to subtract packages with
`PRODUCT_PACKAGES -=`; transitive dependencies and inherited makefiles make
that approach difficult to audit.

Every optional feature should pass this decision sequence:

1. Is corresponding hardware physically present?
2. Did the stock reader use the feature rather than merely ship its package?
3. Does the measured YES24 or Total Launcher workflow require it?
4. Does Oreo framework startup require it?
5. Can its removal be verified with RAM/SD boot before any eMMC write?

Record the resulting package delta and boot-test result for every pruning
change.
