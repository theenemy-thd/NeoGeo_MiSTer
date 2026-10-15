# NeoGeo / Neo Geo CD core — 68000 overclock (18 / 24 MHz) and no sprite limit, v8

Based on MiSTer-devel/NeoGeo_MiSTer (commit ffaab14, 1 Sep 2026). Works for
both cartridge (AES/MVS) and CD systems, since they share the same 68000.

## The options

OSD main page:
- **68K Speed: 12MHz / 18MHz / 24MHz** (default 12MHz), described first below.
- **Sprites per Line: 96 (Original) / No Limit** (default 96), described in
  "Sprites per line" further down. Takes effect immediately.

The new speed takes effect on **Reset & apply** (or when a game is loaded),
never in the middle of a game, so the CPU can't be switched mid bus cycle.

At 12MHz the core is identical to the official one: the original clock
enables are passed straight through and none of the pacing below is active.

## What runs faster

Only the 68000, plus the two pieces of logic that follow its bus cycles
(NEO-C1 wait-state counter and the system register latch). Everything else
keeps its original clock: video (LSPC), sound (YM2610, Z80), timers and IRQs,
the CD drive interface and CD DMA. So games keep the same frame rate and
music speed; the 68000 just gets more work done per frame, which removes or
reduces slowdown.

## Why v1 glitched, and what v2 does

v1 showed broken graphics from boot at 18/24MHz (e.g. Last Resort). The video
chip (LSPC) handles the 68000's VRAM accesses in its own time slots: a write
waits in a one-entry buffer, and reads come from latches refreshed a little
after the VRAM address is set. At 12MHz the 68000 can never get ahead of
that; at 18/24MHz it overwrote pending writes and read stale latches, so the
BIOS and games wrote the wrong tiles.

v2 adds wait states, only when overclocked:
- **VRAM registers ($3C0000-$3C0005):** if the LSPC still has a write
  pending, or its read latches don't yet hold the new address, the access
  (and DTACK) waits until they do. Only back-to-back VRAM accesses are slowed,
  and only to the pace the LSPC can take.
- **Neo Geo CD registers ($FF0000-$FF0FFF):** the CD logic samples 68000
  strobes at the stock 12MHz rate, so fast accesses could be missed or run
  together (v1 would not have booted CD games). Those accesses are stretched
  to what the 12MHz logic needs.

Everything else (work RAM, ROM, palette, I/O) runs at full speed.

## Why v2 lost sound in some games, and what v3 does

Blazing Star had no music at the start at 18MHz and no sound at all at 24MHz.
Games time some of their talks with the sound CPU (Z80) with 68000 loops
written for 12MHz: after sending $03 (Z80 soft reset) or $01 (prepare for
slot switch) they wait a fixed number of loops for the Z80 to be ready, and
they wait for Z80 replies with loop-count timeouts. Overclocked, those waits
end early and the next sound commands arrive while the Z80 is still
restarting, so they are lost.

v3 puts the 68000 back to its stock rate for short moments, automatically:
- for 250ms after the 68000 writes $01 or $03 to the sound register (SNK
  asks for the Z80 reset to take under 100ms, so the game's wait fits);
- while the 68000 keeps reading the sound register (a polling loop, reads
  less than 0.5ms apart), and for 2ms after the last read.

Those only happen at boot, on reset or slot switches, and while a game waits
on the Z80, so they don't take away the speed-up during play. A single sound
command or read per frame never slows the CPU. The switch between speeds is
seamless (the CPU clock phases keep alternating), so it can happen anywhere.

## Neo Geo CD at 24MHz (v5, v6, v7)

v4 didn't get past the Neo Geo CD logo at 24MHz (18MHz was fine), with every
game.

v5 kept the 68000 at its stock rate for 1ms after any access to the CD
registers ($FF0000-$FF0FFF), because the BIOS talks to the CD drive through a
handshake with loop-count timeouts. That was not enough: v5 still hangs on the
logo at 24MHz.

A full simulation of the whole core (real BIOS files, a model of the MiSTer's
CD drive handling, and a test disc) boots at 24MHz just like at 12MHz, with v4
as well as v5: logo, disc checks, loading, start of the game, for both the CD
BIOS and UniBIOS CD. So the hang is not a logic problem that simulation can
show, most likely a timing problem in the FPGA itself, on some path that only
the CD system uses at 24MHz.

v6 therefore keeps only program execution fast on the CD system: any 68000
access that is not work RAM ($000000-$1FFFFF) or the BIOS ($C00000-$CFFFFF),
and any time the CD DMA has the bus, runs at the stock rate, until 0.25ms after
the last one (plus the 1ms window from v5 for the CD registers). Game code and
data in RAM still run at 18/24MHz. Cartridge games are not affected.

v6 crashed too (UniBIOS CD, CDZ: illegal instruction at $C00010, stack
pointer 0, within half a second of the BIOS starting). In simulation, v6 runs
that first part of the boot at the stock rate anyway; the crash lines up with
the first long run of work RAM writes, which v6 still did at 24MHz.

On the CD system the 68000's work RAM is in SDRAM. A write is queued and done
when the SDRAM is next free, taking the address and data off the 68000 bus
at that moment, while the 68000 gets DTACK straight away. If the SDRAM is busy
for longer than the rest of the bus cycle (much shorter at 24MHz), the write
lands with the next cycle's address or data, or two writes merge into one.

v7:
- CPU writes to CD RAM (work RAM, FIX, sprite RAM) hold DTACK until the SDRAM
  write has started (`CD_WR_PENDING` from sdram_mux.sv), only when overclocked.
- BIOS code ($C00000-$CFFFFF program fetches) always runs at the stock rate on
  the CD system. Games run from work RAM at the chosen speed.
- The v5 and v6 stock-rate windows stay.

## Sprites per line (v4)

The Neo Geo video chip (LSPC) draws at most 96 sprites on a line: the first
96, by sprite number, that cross the line. The rest are not drawn, which is
the blanking/flicker you see when a lot is on screen (games rotate the sprite
order so the missing ones change every frame).

With **No Limit**, a second sprite renderer (`rtl/video/neo_xspr.v`) draws the
sprites after the 96th into its own line buffers, and NEO-B1 shows them on top
of the LSPC's sprites (later sprites have priority on the Neo Geo) and under
the fix layer. The LSPC itself is untouched, so the first 96 are drawn exactly
as before; with the option at 96 the core behaves exactly like the official
one.

- Up to 192 extra sprites per line (288 in total, 3x the original).
- It works one line ahead like the LSPC: during each line it finds the sprites
  for two lines later (reading the sprite tables from a second port of the
  VRAM), and draws the next line (tile map from the VRAM's second port,
  vertical shrink from the LO ROM's spare port, graphics from SDRAM).
- Graphics fetches go through the SDRAM controller at the lowest priority and
  only in the gaps between the LSPC's own sprite and fix fetches, so they
  never delay those (the LSPC needs its sprite data 250ns after asking).
- It reproduces the core's LSPC exactly: horizontal and vertical shrink,
  flips, auto-animation, chained (sticky) sprites, sprite heights of 32 and
  over including the "continuous" 33+ ones, wrap-around at the screen edges.
- It is off while the SDRAM is refreshed (vertical blank), while a Neo Geo CD
  is uploading sprites, while ROMs are being loaded, and when the CD system
  turns sprites off. (CD reading and CD music during play do not stop it.)
- If a line has more extra sprites than can be fetched in one line time, the
  last ones are simply not drawn, as with the option off. In simulation with
  the 68000 at 24MHz doing nothing but ROM reads, 192 extra sprites on a line
  took 84% of the line time.

What it can change: a game that relies on the limit on purpose (hiding a
sprite by making it the 97th on a line) will show it. The flicker some games
make by rotating the sprite order stops, since nothing is dropped.

## Cart wait states (v8, test option)

OSD: **Cart Wait States: Original / Off** (default Original, status bit 48).

Some carts tell the NEO-C1 to add wait states to program ROM reads, because
the original ROM chips were slow. On MiSTer the ROM is in SDRAM and the core
already waits for SDRAM on every read, so the cart wait only costs time where
it is longer than that. "Off" removes it; ROM reads stay correct because the
SDRAM wait is untouched. Games that set it (MiSTer romsets.xml):

- Every program ROM read (ROMWAIT): Ninja Combat, Ninja Commando, KOF '94
- Second program ROM bank (PWAIT): KOF '94, '95, '96, '97, '98, '99, 2000,
  2001, Fatal Fury 3, Real Bout Fatal Fury 2

All other games are unaffected. Expected gain: a few percent in those games,
probably most in Ninja Combat / Ninja Commando / KOF '94. It is a test
candidate: compare slowdown with Original vs Off. Leave it on Original for
the Neo Geo CD (no effect there).

## Known side effects

Some games use the CPU for timing loops, which will run faster. A game that
relies on exact 68000 timing (raster effects timed by instruction counts) may
look or behave differently; if so, use 12MHz for that game.

## Building (Quartus 17.0)

1. Unzip somewhere with a short path (not inside the zip).
2. Open `NeoGeo.qpf` (or `NeoGeo_DualSDR.qpf` for dual SDRAM) and compile.
3. Result: `output_files/NeoGeo.rbf`. Copy it to `_Console/` (e.g. as
   `NeoGeoTREX_20260926.rbf` to keep it next to the official core; the core's
   settings, memory cards and game folders don't depend on the file name).

Timing: the fx68k multicycle constraints stay valid at 18/24MHz (the
constrained registers update 3-4 CPU phases apart, which is at least 3
system clocks even at 24MHz), so Quartus' timing report covers the new
speeds. Check the compile shows no failing timing paths, as usual.

## Changes

- `rtl/cpu/cpu_speed.v` (new): fx68k PHI1/PHI2 enables. 12MHz: original
  enables; 18MHz: phases on 3 of every 4 clocks of 48MHz; 24MHz: a phase every
  clock. PHI1/PHI2 always alternate. Speed is sampled while the CPU is in reset.
- `neogeo.sv`: OSD option `oDE` (status bits 45-46, previously unused, so no
  saved settings change meaning); CPU, NEO-C1 and syslatch use the new
  enables; LSPC VRAM pacing and CD register pacing (DTACK waits, only when
  overclocked); sound sync (stock-rate windows around Z80 reset/polling).
- `rtl/cpu/cpu_speed.v` also has a SLOW input for those windows.
- `rtl/video/lspc2_a2.v`, `slow_cycle.v`, `fast_cycle.v`: a `CPU_VRAM_BUSY`
  output (write pending, or read latches not yet reloaded after an address
  change). Nothing inside the LSPC changes behaviour.
- `files.qip`: adds `cpu_speed.v`.
- Sprites per line: `rtl/video/neo_xspr.v` (new, listed in `rtl/video/video.qip`);
  `neogeo.sv`: OSD option `oF` (status bit 47, previously unused), fast and
  slow VRAM become dual-port (port B for the renderer), LO ROM port A is shared
  with the renderer outside ROM loading; `rtl/mem/sdram_mux.sv`: renderer read
  requests (lowest priority, timed between PCK1/PCK2 fetches);
  `rtl/video/neo_b1.v`: renderer pixels over the LSPC's sprites;
  `rtl/video/lspc2_a2.v`: raster/pixel counters and auto-animation exported.
- `68k_overclock.patch`: all changes as a patch against ffaab14.

## Testing done

- `sim/cdsim/`: the whole core (`emu`, all of neogeo.sv) in Verilator with the
  real Neo Geo CD BIOS files (not included), a Z80, SDRAM and DDRAM models, and
  an HPS model that plays Main_MiSTer's CD drive part (`neogeocd.cpp` +
  `megacdd.cpp`), sector transfers included. `mkiso.py` builds a small test
  disc. With the CD BIOS (top loader) and UniBIOS CD, at 12 and 24MHz, v4, v5
  and v6 all go through logo, TOC, disc recognition, loading and hand-over to
  the game program in the same way. The 24MHz hang seen on hardware does not
  show up in simulation.

- `sim/cpu_speed_tb.sv`: fx68k running a test program (loops, ADD, MULU,
  DIVU, shifts, memory writes) at 12, 18 and 24MHz, with and without random
  SDRAM-style wait states. Results identical at all speeds; speed-up
  1.50x / 2.00x from BRAM, 1.40x / 1.73x with SDRAM-like waits. With
  `+SLOWTOG` the speed also switches to stock and back at random times:
  results still identical.
- `sim/sound_sync_tb.sv`: fx68k with the sound sync logic from neogeo.sv.
  A $03 write followed by a 12MHz-timed delay loop, and a REG_SOUND polling
  loop, take exactly as long at 18/24MHz as at 12MHz (30.0ms and 10.8ms);
  plain code before and after runs 1.5x/2x faster, and the 250ms window ends
  on time. A CD register write followed by a 12MHz-timed loop also takes
  exactly the stock time at 18/24MHz (0.75ms), and full speed returns after.
- `sim/lspc_pacing_tb.sv`: fx68k + the core's real LSPC and VRAMs, running a
  BIOS-style loop (set VRAMADDR/VRAMMOD, 64 writes through VRAMRW, then 64
  address-set + read-back pairs) at 48 CPU/LSPC phase offsets per speed.
  With pacing, VRAM contents and read-backs are correct at all speeds and
  offsets. With pacing forced off (`-DNOPACE`) it reproduces the v1 bug: every
  run at 18/24MHz has wrong VRAM words or stale read-backs.
- `sim/cd_pacing_tb.sv`: fx68k doing back-to-back CD register writes and
  reads against the core's 12MHz strobe sampling, 32 phase offsets per speed.
  With pacing, every access is seen exactly once at all speeds; without it,
  18MHz loses a third of the writes and 24MHz all of them.
- `sim/video/`: a video bench with the core's real LSPC, NEO-B1, ZMC2,
  NEO-273, line buffers, VRAM and LO ROM, and C ROM through either an ideal
  memory or the real `sdram_mux.sv` + a model with `sdram.sv`'s timing + a
  24MHz 68000 hammering the ROM. Every pixel of a frame is compared with a
  Python reference renderer (`scene.py`), which itself matches the unmodified
  core exactly on all scenes (it had to learn the core's h-shrink pattern,
  its handling of 32+ tall sprites and one corner case of the 96th sprite).
  Results (`regress.sh`: 13 scene types, plus 6 heavy scenes with 150-285
  sprites on some lines):
  - The renderer drawing *every* sprite, with the LSPC's sprites hidden, gives
    the same picture as the LSPC, pixel for pixel, on all scenes (shrink,
    flips, chains, tall/continuous sprites, wrap-around, auto-animation, NTSC
    and PAL).
  - No Limit on the heavy scenes matches the reference without a limit, pixel
    for pixel, also with real SDRAM timing and the 68000 load. The LSPC's own
    96 sprites are never disturbed.
  - Renderer built in but switched off: identical to the core.
- Verilator lint of the whole core: no new errors or warnings from the change.
- Not compiled with Quartus here: the sprite renderer adds about 5 block RAMs
  (M10K) and some logic. If the core doesn't fit, lower `MAXOVF` in
  `neo_xspr.v` (extra sprites per line) from 192 to 96.
- Not yet tested on hardware.
