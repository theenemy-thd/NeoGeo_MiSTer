# NeoGeoTREX (TEST builds)

Modified build of the MiSTer NeoGeo core.

**Main core:** [MiSTer-devel/NeoGeo_MiSTer](https://github.com/MiSTer-devel/NeoGeo_MiSTer)
This branch is based on upstream commit
[`ffaab14`](https://github.com/MiSTer-devel/NeoGeo_MiSTer/commit/ffaab14).
All credit for the core goes to its authors; for the official core use the
link above.

The rbf is named `NeoGeoTREX_*.rbf`, so it sits next to the official
`NeoGeo_*.rbf` without replacing it.

## What TREX adds (v10 TEST)

| OSD option | What it does |
|---|---|
| 68K Speed: 12 / 18 / 24 MHz | 68000 overclock, with pacing for VRAM, CD registers and sound handshakes |
| Sprites per Line: 96 (Original) / No Limit | second sprite renderer for up to 192 extra sprites per line |
| Cart Wait States: Original / Off | drops the cartridge ROM/port wait states |
| User Port: Off / DB15 Joystick | two pads on the DB15 user-port splitter (same adapter as Jotego's DB15 option); E = Coin |

v9 TEST also made VRAM writes ~1.8x faster when overclocked.
Details: `README_68K_OVERCLOCK.md`, `README_v9_TEST.md`, `README_v10_TEST.md`.
Patches against the previous step: `68k_overclock.patch`,
`v9_test_vram_write.patch`, `v10_test_db15.patch`. Simulation benches: `sim/`.

These are **test builds**: tested in simulation and (up to v8) on hardware,
not yet on every game. If something misbehaves, use the official core.

## Build
Quartus 17.0: compile `NeoGeo.qpf` and rename `output_files/NeoGeo.rbf` to
`NeoGeoTREX_v10_TEST.rbf`. Prebuilt rbf files are on the Releases page.
