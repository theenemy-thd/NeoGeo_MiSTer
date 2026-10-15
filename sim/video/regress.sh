#!/bin/bash
# full regression of the extra sprite renderer on the video bench
cd "$(dirname "$0")"
# build first: ./build.sh base; ./build.sh xs -DXSPR; ./build.sh realxs -DREALSDR -DXSPR
# scenes: for each dir below, python3 mkscene.py RECIPE SEED DIR
fail=0
run() { # obj dir recipe seed limit args...
	local obj=$1 d=$2 rec=$3 seed=$4 lim=$5; shift 5
	./$obj/Vtb +DIR=$d "$@" > /dev/null
	r=$(python3 compare.py ref $d $rec $seed $lim | tail -1)
	printf "%-8s %-9s %-26s %s\n" "$obj" "$d" "$*" "$r"
	case "$r" in *"different: 0") ;; *) fail=1;; esac
}
light="g_hz:g_hz:1 g_hzf:g_hzf:1 g_vzf:g_vzf:1 chains1:chains:1 chains2:chains:2 tall1:tall:1 tall2:tall:2 xpar1:xpar:1 ywrap1:ywrap:1 ywrap2:ywrap:2 L1:rand_light:1 L2:rand_light:2 L3:rand_light:3"
for e in $light; do IFS=: read d rec s <<< "$e"
	run obj_base    $d $rec $s 96                                  # core alone
	run obj_xs      $d $rec $s 96 +XSPR +SKIP=0 +CORESPROFF         # renderer alone = core
done
for s in 1 2 3 4 5 6; do
	run obj_base    H$s rand_heavy $s 96                           # core: 96 limit
	run obj_xs      H$s rand_heavy $s 96                           # renderer built in, off
	run obj_xs      H$s rand_heavy $s 0 +XSPR +XLAT=8              # no limit (C ROM reads take 8 clocks)
	run obj_realxs  H$s rand_heavy $s 0 +XSPR +M68K                # no limit, real SDRAM, 68K load
	run obj_realxs  H$s rand_heavy $s 96 +M68K                     # real SDRAM, renderer off
done
[ $fail = 0 ] && echo "ALL PASS" || echo "FAILURES"
