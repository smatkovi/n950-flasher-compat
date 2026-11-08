# v0.1.0 — hardware-tested RM-680 DeviceLock recovery

This source-only release contains the reproducible compatibility builders and
guarded runner used for a successful Nokia N950 recovery:

- genuine Nokia DeviceLock reset and persistence save;
- signed Harmattan Main+eMMC full flash;
- successful unsigned UbiBoot flash to `mtd2` as the security-gate test.

The exact-range ACK does **not** perform a new secure erase.  It only
acknowledges offset 0, length 15,896,412,160 bytes after prior deliberate
erasure/attempts, then lets Nokia's original control flow continue.  Read the
README safety boundary before use.

No Nokia, MOSLO, or UbiBoot binaries are included.  Release assets contain
only original source/scripts and checksums.
