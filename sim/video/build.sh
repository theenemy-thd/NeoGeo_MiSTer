#!/bin/bash
# Build the video bench with Verilator 5.
#   ./build.sh base                    core only
#   ./build.sh xs -DXSPR               core + extra sprite renderer (ideal SDRAM)
#   ./build.sh realxs -DREALSDR -DXSPR core + renderer + real sdram_mux, SDRAM model, 68000 traffic
cd "$(dirname "$0")"
N=../../rtl
NAME=$1; shift
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style -Wno-WIDTH -Wno-MULTIDRIVEN -Wno-UNOPTFLAT \
  -Wno-INITIALDLY -Wno-PINMISSING -Wno-IMPLICIT -Wno-PROCASSWIRE --top-module tb -Mdir obj_$NAME -I. "$@" \
  tb_vid.sv sim_mem.v sdram_beh.sv $N/mem/sdram_mux.sv $N/video/neo_xspr.v \
  $N/video/lspc2_a2.v $N/video/lspc2_clk.v $N/video/lspc_regs.v $N/video/lspc_timer.v $N/video/videosync.v \
  $N/video/slow_cycle.v $N/video/fast_cycle.v $N/video/irq.v $N/video/autoanim.v $N/video/hshrink.v \
  $N/video/neo_b1.v $N/video/linebuffer.v $N/video/zmc2_dot.v $N/video/neo_273.v $N/io/watchdog.v $N/io/clocks.v \
  $N/io/register.v $N/io/resetp.v $N/cells/*.v
