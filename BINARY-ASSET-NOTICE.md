# Prebuilt binary asset notice

The optional GitHub Release binaries are provided for compatibility and
recovery testing on the Nokia N950 RM-680:

```text
flasher-3.12.1-erase240m
SHA-256 b961720d131df7e04502350313f2a9bcec460399df2c01a5028b2cf8f33c0a16

ape-algo-moslo-fs-erase-ack.bin
SHA-256 ef7b90e02ba830a918e2daffab503c42e45b79e033a2c290d92b48d700d2e3c1
```

The first is a three-byte timeout modification of Nokia flasher 3.12.1.  The
second retains Nokia's APE kernel/initramfs and adds MOSLO-derived filesystem
tools plus this project's exact-range acknowledgement hook.

These files are not original standalone MIT-licensed works.  They contain or
derive from third-party Nokia/MOSLO material, and this repository cannot grant
rights to that material.  Users are responsible for reviewing the applicable
licenses and determining whether downloading or redistributing these assets is
permitted in their jurisdiction.

The exact-range APE does **not** perform a new secure erase.  It acknowledges
only offset 0 and length 15,896,412,160 bytes, then lets Nokia's original
DeviceLock reset and signed full-flash control flow continue.
