//============================================================================
//  68000 clock enables for the NeoGeo core: 12MHz (original), 18MHz, 24MHz
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// fx68k takes two clock enables, PHI1 and PHI2, which must alternate. At 12MHz
// the original enables from NEO-D0 are passed through unchanged. At 18MHz and
// 24MHz a local generator makes the phases from the 48MHz clock:
//   24MHz: one phase every clock
//   18MHz: phases on 3 clocks out of 4
// The speed is sampled while the CPU is in reset (nRESET low), so it changes
// only on a reset and never in the middle of a bus cycle.
// SLOW (only used when overclocked) makes the local generator run at the
// stock 12MHz rate (a phase every other clock) for as long as it is high.
// PHI1/PHI2 keep alternating across the change, so it can switch at any time.

module cpu_speed(
	input            CLK,           // 48MHz
	input            nRESET,        // 68000 reset, active low
	input      [1:0] SPEED,         // 0: 12MHz, 1: 18MHz, 2: 24MHz (3: 12MHz)
	input            SLOW,          // run overclocked CPU at 12MHz for now
	input            CLK_EN_68K_P,  // original 12MHz enables
	input            CLK_EN_68K_N,
	output           CPU_EN_P,
	output           CPU_EN_N,
	output           OVERCLOCK      // 18MHz or 24MHz selected
);

reg  [1:0] speed = 0;
reg  [1:0] acc   = 0;
reg        phi2  = 0;	// next phase is PHI2
reg        en_p  = 0, en_n = 0;

always @(posedge CLK) begin
	if (!nRESET) speed <= (SPEED == 2'd3) ? 2'd0 : SPEED;

	en_p <= 0;
	en_n <= 0;
	if (SLOW ? ~acc[0] : (speed == 2'd2 || (speed == 2'd1 && acc != 2'd3))) begin
		if (phi2) en_n <= 1;
		else      en_p <= 1;
		phi2 <= ~phi2;
	end
	acc <= acc + 2'd1;
end

assign CPU_EN_P = (speed == 2'd0) ? CLK_EN_68K_P : en_p;
assign CPU_EN_N = (speed == 2'd0) ? CLK_EN_68K_N : en_n;
assign OVERCLOCK = (speed != 2'd0);

endmodule
