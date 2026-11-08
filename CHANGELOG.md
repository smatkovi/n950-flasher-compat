# Changelog

## v0.1.0 — 2026-11-08

- Add the hardware-tested exact-range erase acknowledgement for the RM-680
  15,896,412,160-byte eMMC user area.
- Preserve Nokia's genuine `bb5_devlock_reset()` and `bb5_save_secs()` flow.
- Add deterministic ARM/QEMU validation and APE-overlay verification.
- Add a configurable, fail-closed signed-fullflash-to-UbiBoot runner.
- Add the locally applied 240-minute flasher timeout patch recipe.
