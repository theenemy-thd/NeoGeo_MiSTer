# Full-core Neo Geo CD simulation (Verilator 5)

- `mksrc.py`: copies the sources listed in `files.f` to `src/`, dropping the
  initializers of variables declared inside always blocks (Verilator re-runs
  them every time the block executes). Writes `files_sim.f`.
- `sim_stubs.sv`: memories, PLL, a Verilog port of T80pa around the ghdl
  translation of T80 (`T80s.v` from jtframe), an SDRAM model with sdram.sv's
  timing, and `hps_io` replaced by a test controller: sets up a CD system and
  acts as Main_MiSTer's CD drive (commands, status every 10ms, data sectors
  through ioctl index 2). `+iso=`, `+nsect=`, `+tracks=`, `+press_ms=`,
  `+start_ms=`, `+speed=` (0/1/2), `+cdz=`.
- `tb.sv`: 50MHz clock, DDRAM model, 68000 activity log every 100ms, frame
  dumps (PPM).
- `mkhex.py <bios> <out.hex>`: BIOS image for `+sdram_init=`.
- `mkiso.py test.iso`: test disc (ABS/BIB/CPY.TXT, IPL.TXT, PRG/FIX/SPR/Z80/PCM).
- `build.sh <objdir>` then `run.sh <dir> <objdir>/Vtb <bios.hex> <speed> <cdz> <stop_ms> [plusargs]`.

BIOS files are not included. Paths in the scripts point to the machine the
simulation was made on and need adjusting.
