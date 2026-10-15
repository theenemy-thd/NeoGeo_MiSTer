# NeoGeoTREX v9 TEST – faster VRAM writes when overclocked

Test build from the separate `speed-test` branch. The known-good build
(v8, branch `cpu-overclock`) is untouched; keep its rbf as a fallback.

## What changed (only this, on top of v8)
When the 68000 is overclocked, CPU accesses to the video chip's VRAM port are
held until the chip is ready (the v2 fix for Last Resort's glitches). Writes
were also waiting for the chip to reload its *read* buffers, which only reads
need. Writes now wait only for the previous write and the address update.

## Measured (whole-core simulation, cart-like, 24MHz)
| 68000 activity               | v8         | v9 test     |
|------------------------------|------------|-------------|
| Back-to-back VRAM writes     | 6.9 MHz    | **12.3 MHz** (1.78x; video chip's own limit) |
| Plain code (ROM fetches)     | 18.5 MHz   | 18.5 MHz    |
| Work RAM reads               | 18.6 MHz   | 18.6 MHz    |
| VRAM reads                   | 20.8 MHz   | 20.8 MHz    |

In v8, VRAM write loops at 24MHz were *slower than stock 12MHz*. Every game
writes its sprite tables through this port each frame, so this is where
overclocked games were losing the most.

Correctness: `sim/lspc_pacing_tb.sv` (real 68000 + real LSPC, VRAM write loop
and read-back) passes at all 48 CPU/LSPC timing alignments at 12, 18 and 24MHz.

## What to test
Same games as before at 24MHz: Last Resort (the original glitch), Blazing Star,
Metal Slug series, KOF. Watch for wrong sprites/tiles or text. If anything looks
wrong, go back to v8.

## Not done yet: program ROM wait
Plain code runs at ~18.5MHz instead of 24MHz because every instruction fetch
waits for an SDRAM read (~50ns). A small on-chip instruction cache could win
most of that back (up to ~1.3x on CPU-heavy code); it is a bigger change.

## Build
Compile `NeoGeo.qpf` (or `NeoGeo_DualSDR.qpf`) as before and rename the rbf
to `NeoGeoTREX_v9test.rbf` (any name starting NeoGeoTREX).
`v9_test_vram_write.patch` is the change against v8.
