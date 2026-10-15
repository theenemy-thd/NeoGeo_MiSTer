// LSPC VRAM access pacing for the overclocked 68000
// The LSPC takes CPU VRAM writes and reads in its own time slots. At 12MHz the
// 68000 can't get ahead of it, but at 18/24MHz it would overwrite a pending
// write or read a stale latch. When the CPU accesses the VRAM registers
// ($3C0000/2/4) while the LSPC is still busy with the previous access, the
// access is held back (LSPC strobes and DTACK) until the LSPC is free. Then it
// goes through once, and DTACK waits 3 more clocks so read data is valid.
wire LSPC_VRAM_BUSY, LSPC_VRAM_WR_BUSY;
wire lspc_vram_acc = (~nLSPWE & (M68K_ADDR[3:1] <= 3'd2)) | (~nLSPOE & ~M68K_ADDR[2]);
reg  lspc_granted = 0, lspc_waited = 0;
reg  [1:0] lspc_dly = 0;
wire lspc_hold = CPU_OVERCLOCK & lspc_vram_acc & ~lspc_granted & (~nLSPWE ? LSPC_VRAM_WR_BUSY : LSPC_VRAM_BUSY);
wire lspc_dtack_wait = lspc_hold | (lspc_waited & (lspc_dly != 2'd3));

always @(posedge CLK_48M) begin
	if (!lspc_vram_acc) begin
		lspc_granted <= 0;
		lspc_waited  <= 0;
		lspc_dly     <= 0;
	end else begin
		if (lspc_hold) lspc_waited  <= 1;
		else           lspc_granted <= 1;
		if (lspc_granted && lspc_dly != 2'd3) lspc_dly <= lspc_dly + 2'd1;
	end
end
