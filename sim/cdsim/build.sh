#!/bin/bash
# build.sh <objdir> [extra verilator args]
S=/tmp/claude-0/-home-claude/318fcbfa-b65f-58cc-a3f0-144783abf396/scratchpad
export VERILATOR_ROOT=$S/verilator PATH=$S/verilator/bin:$PATH
cd $S/cdsim
OBJ=$1; shift
verilator --binary --timing -O3 -j 2 -I. --x-assign fast --x-initial 0 \
 -Wno-fatal -Wno-lint -Wno-style -Wno-WIDTH -Wno-UNOPTFLAT -Wno-INITIALDLY -Wno-PINMISSING -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD \
 -Wno-COMBDLY -Wno-IMPLICIT -Wno-SELRANGE -Wno-CASEINCOMPLETE -Wno-UNSIGNED -Wno-PROCASSWIRE -Wno-BLKANDNBLK \
 --top-module tb -Mdir $OBJ "$@" \
 -f ${FL:-files_sim.f} sim_stubs.sv tb.sv 2>&1 | grep -E "%Error|Error" | head -40
