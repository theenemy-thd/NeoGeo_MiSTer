// NeoGeo video bench: the core's LSPC2 + NEO-B1 + ZMC2 + NEO-273 with VRAM,
// LO ROM and C ROM models. VRAM contents come from hex files; the palette
// address (PA) of every pixel of a chosen frame is dumped to a text file.
`timescale 1ns/1ps
module tb;

reg CLK_48M = 0, CLK_96M = 0;
always #10.416 CLK_48M = ~CLK_48M;
always #5.208 CLK_96M = ~CLK_96M;

reg CLK_EN_24M_N = 0, CLK_EN_24M_P = 0;
always @(posedge CLK_48M) begin
	CLK_EN_24M_N <= ~CLK_EN_24M_N;
	CLK_EN_24M_P <= CLK_EN_24M_N;
end

reg nRESET = 0;
wire nRESETP;

// clocks from NEO-D0
wire CLK_EN_12M, CLK_EN_12M_N, CLK_EN_6MB, CLK_EN_1HB;
clocks_sync CLKS(CLK_48M, CLK_EN_24M_P, CLK_EN_24M_N, nRESETP, , , , , , , , , CLK_EN_12M, CLK_EN_12M_N, CLK_EN_6MB, CLK_EN_1HB);

// ---------------------------------------------------------------- memories
reg  [15:0] svram[0:32767];
reg  [15:0] fvram[0:2047];
reg  [7:0]  lorom[0:65535];
reg  [15:0] crom[0:(1<<20)-1];     // 2MB of C ROM (word array, SDRAM order)
localparam [26:0] CROM_MASK = 27'h1FFFFF;

wire [14:0] SLOW_VRAM_ADDR;
wire [15:0] SLOW_VRAM_DATA_OUT;
reg  [15:0] SLOW_VRAM_DATA_IN;
wire        BOE, BWE;
wire [10:0] FAST_VRAM_ADDR;
wire [15:0] FAST_VRAM_DATA_OUT;
reg  [15:0] FAST_VRAM_DATA_IN;
wire        CWE;
always @(posedge CLK_48M) begin
	if (~BWE) svram[SLOW_VRAM_ADDR] <= SLOW_VRAM_DATA_OUT;
	SLOW_VRAM_DATA_IN <= ~BWE ? SLOW_VRAM_DATA_OUT : svram[SLOW_VRAM_ADDR];
	if (~CWE) fvram[FAST_VRAM_ADDR] <= FAST_VRAM_DATA_OUT;
	FAST_VRAM_DATA_IN <= ~CWE ? FAST_VRAM_DATA_OUT : fvram[FAST_VRAM_ADDR];
end

wire [23:0] PBUS;
wire        nPBUS_OUT_EN;
reg  [7:0]  LO_ROM_DATA;
always @(posedge CLK_48M) LO_ROM_DATA <= lorom[PBUS[15:0]];
assign PBUS[23:16] = nPBUS_OUT_EN ? LO_ROM_DATA : 8'bzzzzzzzz;

// ---------------------------------------------------------------- LSPC
wire CA4, S1H1, S2H1, LOAD, H, EVEN1, EVEN2;
wire PCK1, PCK2, PCK1_EN_N, PCK2_EN_N, PCK1_EN_P, PCK2_EN_P;
wire CHG, LD1, LD2, SS1, SS2, CHBL, nBNKB, VCS, HSync;
wire [3:0] WE, CK;
wire DOTA, DOTB;
wire [15:0] M68K_DATA;
wire [11:0] XSPR_PIXEL;
wire XSPR_OPAQUE;
wire [8:0] X_RASTERC, X_PIXELC;
wire [2:0] X_AA_COUNT;
wire X_AA_DISABLE;

lspc2_a2_sync LSPC(
	.CLK(CLK_48M), .CLK_EN_24M_P(CLK_EN_24M_P), .CLK_EN_24M_N(CLK_EN_24M_N),
	.RESET(nRESET), .nRESETP(nRESETP),
	.LSPC_8M(), .LSPC_4M(), .LSPC_EN_4M_P(), .LSPC_EN_4M_N(),
	.M68K_ADDR(3'd0), .M68K_DATA(M68K_DATA),
	.IPL0(), .IPL1(), .CD_VBLANK_IRQ_EN(1'b1), .CD_TIMER_IRQ_EN(1'b1),
	.LSPOE(1'b1), .LSPWE(1'b1),
	.PBUS_OUT(PBUS[15:0]), .PBUS_IO(PBUS[23:16]), .nPBUS_OUT_EN(nPBUS_OUT_EN),
	.DOTA(DOTA), .DOTB(DOTB),
	.CA4(CA4), .S2H1(S2H1), .S1H1(S1H1),
	.LOAD(LOAD), .H(H), .EVEN1(EVEN1), .EVEN2(EVEN2),
	.PCK1(PCK1), .PCK2(PCK2), .PCK1_EN_N(PCK1_EN_N), .PCK2_EN_N(PCK2_EN_N),
	.PCK1_EN_P(PCK1_EN_P), .PCK2_EN_P(PCK2_EN_P),
	.CHG(CHG), .LD1(LD1), .LD2(LD2), .WE(WE), .CK(CK), .SS1(SS1), .SS2(SS2),
	.HSYNC(HSync), .VSYNC(), .CHBL(CHBL), .BNKB(nBNKB), .VCS(VCS),
	.SVRAM_ADDR(SLOW_VRAM_ADDR), .SVRAM_DATA_IN({16'd0, SLOW_VRAM_DATA_IN}), .SVRAM_DATA_OUT(SLOW_VRAM_DATA_OUT),
	.BOE(BOE), .BWE(BWE),
	.FVRAM_ADDR(FAST_VRAM_ADDR), .FVRAM_DATA_IN(FAST_VRAM_DATA_IN), .FVRAM_DATA_OUT(FAST_VRAM_DATA_OUT),
	.CWE(CWE), .VMODE(vmode),
	.FIXMAP_ADDR(), .SPRMAP_ADDR(), .VRAM_ADDR(), .VRAM_CYCLE(), .SVRAM_WR(), .LO_ROM_ADDR(),
	.CPU_VRAM_BUSY(),
	.XSPR_RASTERC(X_RASTERC), .XSPR_PIXELC(X_PIXELC), .XSPR_AA_COUNT(X_AA_COUNT), .XSPR_AA_DISABLE(X_AA_DISABLE)
);

// ---------------------------------------------------------------- C ROM path
wire [19:0] C_LATCH;
reg  [3:0]  C_LATCH_EXT;
neo_273 NEO273(.CLK(CLK_48M), .PBUS(PBUS[19:0]), .PCK1B_EN(PCK1_EN_N), .PCK2B_EN(PCK2_EN_N), .C_LATCH(C_LATCH), .S_LATCH());
always @(posedge CLK_48M) if (PCK1_EN_N) C_LATCH_EXT <= PBUS[23:20];
wire [26:0] CROM_ADDR = {C_LATCH_EXT, C_LATCH, 3'b000} & CROM_MASK;

`ifndef REALSDR
// sdram_mux starts the read on the falling edge of PCK1, data about 100ns later
reg [63:0] CR_DOUBLE;
reg        pck1_d;
reg [4:0]  cr_dly = 0;
integer    cr_lat = 5;
reg [26:0] cr_addr;
always @(posedge CLK_48M) begin
	pck1_d <= PCK1;
	if (pck1_d & ~PCK1) begin cr_dly <= cr_lat; cr_addr <= CROM_ADDR; end
	else if (cr_dly != 0) begin
		cr_dly <= cr_dly - 1'd1;
		if (cr_dly == 1)
			CR_DOUBLE <= {crom[{cr_addr[20:3],2'd0}], crom[{cr_addr[20:3],2'd1}], crom[{cr_addr[20:3],2'd2}], crom[{cr_addr[20:3],2'd3}]};
	end
end

`else
`include "tb_realsdr.vh"
`endif
wire [3:0] GAD, GBD;
wire DOTA_R, DOTB_R;
zmc2_dot ZMC2(
	.CLK(CLK_48M), .CLK_EN_12M_N(CLK_EN_12M_N),
	.EVEN(EVEN1), .LOAD(LOAD), .H(H),
	.CR(CA4 ? CR_DOUBLE[63:32] : CR_DOUBLE[31:0]),
	.GAD(GAD), .GBD(GBD), .DOTA(DOTA_R), .DOTB(DOTB_R)
);
reg vmode = 0;
reg tb_nAS = 1;   // one AS pulse so B1 selects video (not CPU) on PA
reg core_spr_off = 0;       // +CORESPROFF: hide the core's own sprites (engine test)
assign DOTA = DOTA_R & ~core_spr_off;
assign DOTB = DOTB_R & ~core_spr_off;

// ---------------------------------------------------------------- NEO-B1
wire [11:0] PA;
neo_b1 B1(
	.CLK(CLK_48M), .CLK_EN_6MB(CLK_EN_6MB), .CLK_EN_1HB(CLK_EN_1HB),
	.S1H1(S1H1), .A23I(1'b0), .A22I(1'b0),
	.M68K_ADDR_U(5'd0), .M68K_ADDR_L(12'd0),
	.nLDS(1'b1), .RW(1'b1), .nAS(tb_nAS),
	.PBUS(PBUS), .FIXD(8'd0),
	.PCK1_EN(PCK1_EN_P), .PCK2_EN(PCK2_EN_P),
	.CHBL(CHBL), .BNKB(nBNKB),
	.GAD(GAD & {4{~core_spr_off}}), .GBD(GBD & {4{~core_spr_off}}),
	.WE(WE), .CK(CK),
	.TMS0(CHG), .LD1(LD1), .LD2(LD2), .SS1(SS1), .SS2(SS2),
	.PA(PA), .EN_FIX(1'b1), .DOGE(1'b0), .nRST(1'b1), .nRESET(), .nHALT(),
	.XSPR_PIXEL(XSPR_PIXEL), .XSPR_OPAQUE(XSPR_OPAQUE)
);

`ifdef XSPR
`include "tb_xspr.vh"
`else
assign XSPR_PIXEL = 0;
assign XSPR_OPAQUE = 0;
`endif
`ifdef TIMING
`include "timing.vh"
`endif

// ---------------------------------------------------------------- capture
// PA is registered on CLK_EN_6MB. Dump PA with the LSPC counters of the
// moment (the offset to screen coordinates is fixed and calibrated once).
integer fd, frame = 0, dump_frame = 3;
reg [8:0] rast_prev = 0;
always @(posedge CLK_48M) begin
	if (CLK_EN_6MB && frame == dump_frame)
		$fwrite(fd, "%0d %0d %03x %0d\n", LSPC.RASTERC, LSPC.PIXELC, PA, LSPC.AA_COUNT);
end

// frame counter: RASTERC wraps
always @(posedge CLK_48M) begin
	rast_prev <= LSPC.RASTERC;
	if (rast_prev != LSPC.RASTERC && LSPC.RASTERC == 9'h0F8) begin
		frame = frame + 1;
		if (frame > dump_frame) begin $fclose(fd); $finish; end
	end
end

string dir;
initial begin
	if (!$value$plusargs("DIR=%s", dir)) dir = ".";
	if ($value$plusargs("FRAME=%d", dump_frame)) ;
`ifndef REALSDR
	if ($value$plusargs("CRLAT=%d", cr_lat)) ;
`endif
	core_spr_off = $test$plusargs("CORESPROFF");
	vmode = $test$plusargs("PAL");
	$readmemh({dir, "/svram.hex"}, svram);
	$readmemh({dir, "/fvram.hex"}, fvram);
	$readmemh({dir, "/lorom.hex"}, lorom);
	$readmemh({dir, "/crom.hex"}, crom);
	fd = $fopen({dir, "/pa.txt"}, "w");
	repeat(100) @(posedge CLK_48M); tb_nAS = 0;
	repeat(10) @(posedge CLK_48M); tb_nAS = 1;
	repeat(100) @(posedge CLK_48M);
	nRESET = 1;
end

endmodule
