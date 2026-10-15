#!/bin/bash
# run.sh <dir> <binary> <bios.hex> <speed> <cdz> <stop_ms> [extra plusargs]
cd $(dirname $0)
d=$1; b=$2; h=$3; sp=$4; z=$5; st=$6; shift 6
mkdir -p $d; cd $d; rm -f *.ppm log.txt; cp ../*.mem .
nohup ../$b +sdram_init=../$h +speed=$sp +cdz=$z +stop_ms=$st +iso=../test.iso +dump_every=30 +cddlog +prefix=f "$@" > log.txt 2>&1 &
