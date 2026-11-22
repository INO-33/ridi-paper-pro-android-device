# RIDI8 user signing and optional diagnostic root

Physical `e70q10_reference-user` and `e70q10_minimal-user` products use
`release.mk`. Development and emulator profiles retain their existing behavior.

## Keys

The first key set was generated on 2026-11-10 in
`$HOME/.local/share/ridi8-signing/keys`, outside the source repository.
It contains distinct `releasekey`, `platform`, `shared`, and `media` pairs:
RSA-2048, SHA-256 self-signed certificates, and Android-compatible PKCS#8 keys.
Certificates are valid for 10,000 days from generation. Public fingerprints
are recorded in the parent directory `public-certificates.json`.

The directory is mode 0700 and all key/certificate files are mode 0600.
Private `.pk8` files are unencrypted for the existing unattended build tools.
Keep an encrypted offline backup of all eight files. Never commit private keys,
place them in deliveries, regenerate them for each build, or replace this set
when updating already released firmware. Public certificates may be distributed.

`RIDI_RELEASE_KEY_DIR` may select another private store. Missing key pairs stop
the user build; the product never falls back to AOSP test keys. Relative APK
certificate names (`platform`, `shared`, `media`) resolve under this directory.
The default/OTA key is `releasekey`. These are APK/OTA keys, not i.MX HAB or
bootloader secure-boot provisioning keys.

## Build profile

Select `e70q10_reference-user` instead of `e70q10_reference-eng`, keeping the
existing graphics/backend arguments. The user profile keeps `ro.secure=1`,
`ro.adb.secure=1`, and `ro.debuggable=0`. APKs are directly signed with the
private certificates; the build tags/fingerprint use `release-keys` for this
physical user product. Pre-signed third-party packages retain their own signatures.

With the existing helper, set `E70Q10_LUNCH=e70q10_reference-user`, reuse the
existing `E70Q10_OUT_DIR` on the already mounted build volume, and run
`device/ridi/e70q10/tools/build_android8.sh build bootimage systemimage vendorimage`.
Do not run a clean build or change the graphics baseline as part of this switch.
No firmware was built or installed during the initial key/profile setup.

## Root switch

The existing Developer options root switch is included in user builds, default
OFF. USB debugging is separate and keeps standard PC-key authentication.
Enabling root allows `su`/ADB UID0 without setting global `ro.debuggable=1`.
Explicit `adb unroot` is honored; `adb root` requires the switch to be ON.
Existing init one-shot restart/link handling remains in effect. A persisted ON
choice from an older installation is retained; the default does not erase it.

SELinux remains enforcing. The physical user product enables a narrowly scoped
`su` diagnostic domain with log, dump, sysfs/proc read, framebuffer read, APK/app
data read, Binder command-line diagnostics, and `/data/local/tmp` access.
It does not import the permissive development `su` domain, enable global JDWP,
disable ADB authentication, authorize `adb disable-verity`, grant kernel policy
replacement/ptrace/raw I/O, or generally permit remounting/writing system files.
Additional low-level debugging may still require the development image or
specific policy changes. Other user products retain AOSP root prohibitions.

## First transition / validation

Existing test-key Android 8 userdata may require offline signing repair after
switching to the private keys. The current GUI separates ordinary image updates
from "서명 복구 · SD 없이". Ordinary updates do not automatically migrate
certificates or require signing-policy.tsv. If Android cannot boot because of the
stored signature mismatch, enter fastboot again and run the standalone rescue
RAM image. It needs no SD or authenticated Android ADB connection, verifies the
installed factory APKs before writes, and preserves app IDs/data. The rescue
performs no full eMMC backup and no boot/system/vendor image writes.

The build helper generates signing-policy.tsv beside user systemimage outputs.
Use the policy and boot image from the same firmware to generate a new rescue
image in the GUI. The prebuilt rescue is bound to the included APK inventory;
unknown certificates or a different installed firmware stop before migration.
See porting/e70q10/emmc-tool/SIGNING_RESCUE.md. Host tests passed; actual rescue
activation on real userdata and subsequent normal boot are still pending.

Host checks cover all four real key pairs with Android8 SignApk/Java8 and APK
signature verification, actual ADB authorization functions, Make profile
selection, and user SELinux compilation with all neverallow assertions enabled
and no permissive domains. Full Android/ARM build, split-policy build, physical
boot/authenticated ADB/root toggling and Kyobo compatibility remain untested.
