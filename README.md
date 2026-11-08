# Nokia N950 Harmattan flasher compatibility tools

Source-only, reproducible compatibility patches for the Nokia N950 (RM-680)
Harmattan flashing flow.  The hardware-tested recovery path lets Nokia's
original `softupd` reset the BB5 DeviceLock state, performs a signed
Main+eMMC factory flash, and then uses an unsigned UbiBoot kernel flash as the
practical security-gate test.

## Important safety boundary

The successful `erase-ack` path **does not perform a new secure erase**.  It
acknowledges only this exact `BLKSECDISCARD` request without sending CMD38 to
the eMMC:

```text
offset  0
length  15,896,412,160 bytes (0x3b3800000)
```

Every other secure-discard range fails with `EINVAL`; unrelated ioctls pass
through unchanged.  Nokia's unmodified `softupd` then calls
`bb5_devlock_reset()` and `bb5_save_secs()` before the signed full flash.

Use this only when:

- the device is an RM-680 with that exact eMMC user-area size;
- erasure was already deliberately completed or attempted and all data is
  backed up;
- a destructive signed Main+eMMC factory flash is intended immediately;
- you understand that this run does not itself prove secure data erasure.

Disconnecting power during the signed full flash can leave the phone
unbootable.  This project is experimental recovery tooling, not a general
N950 installer.

## Verified result

The complete path was hardware-tested on an N950 RM-680, hardware revision
1124, with NOLO 2.3.6:

1. fresh NOLO identification;
2. exact full-range erase acknowledgement;
3. Nokia DeviceLock reset and signed Main+eMMC full flash: `Success`;
4. unsigned 11,964 KiB UbiBoot kernel written to `mtd2`: `Success`;
5. no `Security failure` or `Devicelock ON` response.

The earlier 96 MiB secure-discard split and the 8 MiB normal-discard fallback
were **not** successful on this old kernel/eMMC combination and are not the
recommended recovery path.

## No vendor binaries

This repository and its releases intentionally contain no Nokia firmware,
Nokia flasher binary, extracted Nokia initramfs, MOSLO binary, or UbiBoot
kernel.  You must supply your own copies.  See [NOTICE.md](NOTICE.md).

Known input and output hashes are listed in
[KNOWN-HASHES.md](KNOWN-HASHES.md).

## Build

Required host tools include Bash, coreutils, util-linux (`flock`, `setsid`),
systemd (`systemd-inhibit`), `0xFFFF`, `binwalk`, `cpio`, Clang/LLD with ARM
support, `readelf`, and `qemu-arm`.

The byte-identical reference build used Clang/LLD 23.1.3, QEMU 11.1.2, and
GNU cpio 2.15.  The final builder deliberately rejects a compiler/toolchain
combination that does not reproduce the hardware-tested output hash.

Provide your locally obtained inputs:

```bash
export N950_MAIN_IMAGE=/path/to/DFL61_HARMATTAN_40.2012.21-3_PR_LEGACY_RM680-OEM1-916_ARM.bin
export N950_MOSLO_IMAGE=/path/to/zImage-moslo
export N950_STOCK_ROOT=/path/to/extracted/harmattan-root
export N950_APE_ROOT="$PWD/stock-ape-root"
```

`N950_STOCK_ROOT` must contain `sbin/dosfslabel`.  Extract the original APE
initramfs from your verified Main image without committing vendor files:

```bash
./extract-stock-ape-root.sh "$N950_APE_ROOT"
```

Build the exact-range APE and the local timeout-patched host flasher:

```bash
./secure-discard/build-erase-ack-ape.sh
./build-flasher-erase-timeout-240m.sh
```

Expected outputs:

```text
ape-algo-moslo-fs-erase-ack.bin  9,256,960 bytes
SHA-256 ef7b90e02ba830a918e2daffab503c42e45b79e033a2c290d92b48d700d2e3c1

flasher-3.12.1-erase240m         135,280 bytes
SHA-256 b961720d131df7e04502350313f2a9bcec460399df2c01a5028b2cf8f33c0a16
```

The host-flasher builder changes exactly three bytes in a locally supplied
stock flasher.  It does not modify `/usr/bin/flasher`.

## Configure and run

Copy the local configuration template and fill in your paths and the device
identifier printed by `flasher -i`:

```bash
cp n950-local.conf.example n950-local.conf
chmod 600 n950-local.conf
```

The local configuration is ignored by Git.  First perform the offline check:

```bash
./reset-devicelock-and-flash-ubiboot.sh --check
```

For the destructive run, physically cold-start the phone into fresh NOLO:
unplug USB, remove the battery, discharge the device, reinstall the battery,
leave it powered off, start the command below, and then connect USB within 45
seconds:

```bash
sudo ./reset-devicelock-and-flash-ubiboot.sh \
  --arm-acknowledge-already-erased
```

The runner is fail-closed.  It requires the configured exact device ID,
`Found device RM-680`, `NOLO version`, verified hashes, stage exit status zero,
and `Success`.  It will not proceed from an already-running old APE/softupd
session.  UbiBoot is attempted only after the signed full flash succeeds.

## Repository contents

- `build-flasher-erase-timeout-240m.sh` — local three-byte timeout patch.
- `extract-stock-ape-root.sh` — extracts Nokia's APE root locally from the
  user-supplied Main FIASCO.
- `build-patched-ape.sh` — builds the MOSLO filesystem-tool overlay from
  user-supplied inputs.
- `secure-discard/liberase-ack.c` — exact-range ioctl interposer.
- `secure-discard/test_erase_ack_ioctl.c` — ARM/QEMU smoke test.
- `secure-discard/build-erase-ack-ape.sh` — deterministic final APE builder.
- `reset-devicelock-and-flash-ubiboot.sh` — guarded, configurable runner.

## License

The original source and scripts in this repository are available under the
MIT License.  This license does not cover third-party inputs or generated
artifacts containing them; see [NOTICE.md](NOTICE.md).
