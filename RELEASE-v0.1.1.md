# v0.1.1 — optional prebuilt RM-680 compatibility binaries

This prerelease adds the two byte-verified binaries used in the successful
Nokia N950 recovery, alongside the complete MIT-licensed source and builders:

- `flasher-3.12.1-erase240m`
- `ape-algo-moslo-fs-erase-ack.bin`

The exact-range APE does **not** perform a new secure erase.  It only
acknowledges offset 0, length 15,896,412,160 bytes after prior deliberate
erasure/attempts.  Nokia's genuine DeviceLock reset, signed Main+eMMC full
flash, and the unsigned UbiBoot gate test remain separate stages.

Main/eMMC firmware and UbiBoot are not included.  The binaries contain or
derive from third-party Nokia/MOSLO material and are not covered by the MIT
License.  Read `BINARY-ASSET-NOTICE.md` before downloading or redistributing.

Verify every downloaded asset with the attached `SHA256SUMS`.
