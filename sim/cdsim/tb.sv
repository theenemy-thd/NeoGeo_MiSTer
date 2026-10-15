// Full NeoGeo core (emu) booting the Neo Geo CD BIOS, no disc.
`timescale 1ns/1ps
module tb;
integer wr_req = 0, wr_late = 0, wr_wait = 0, wr_maxwait = 0;
integer ntr = 0, max_tr = 4000, z80_m1 = 0, snd_w = 0;
reg [15:0] zmin = 16'hffff, zmax = 0;

reg CLK_50M = 0;
always #10 CLK_50M = ~CLK_50M;

wire [45:0] HPS_BUS;

// ---------------------------------------------------------------- DDRAM model
wire        DDRAM_CLK;
wire  [7:0] DDRAM_BURSTCNT;
wire [28:0] DDRAM_ADDR;
reg  [63:0] DDRAM_DOUT = 0;
reg         DDRAM_DOUT_READY = 0;
wire        DDRAM_RD;
wire [63:0] DDRAM_DIN;
wire  [7:0] DDRAM_BE;
wire        DDRAM_WE;

logic [63:0] ddr [bit [28:0]];
reg   [28:0] rd_a;
reg    [7:0] rd_left = 0;
reg    [3:0] rd_dly = 0;
always @(posedge DDRAM_CLK) begin
	DDRAM_DOUT_READY <= 0;
	if (DDRAM_WE) begin : w
		logic [63:0] v; integer i;
		v = ddr.exists(DDRAM_ADDR) ? ddr[DDRAM_ADDR] : 64'd0;
		for (i = 0; i < 8; i++) if (DDRAM_BE[i]) v[i*8 +: 8] = DDRAM_DIN[i*8 +: 8];
		ddr[DDRAM_ADDR] = v;
	end
	if (DDRAM_RD && rd_left == 0) begin
		rd_a <= DDRAM_ADDR; rd_left <= DDRAM_BURSTCNT; rd_dly <= 6;
	end else if (rd_left != 0) begin
		if (rd_dly != 0) rd_dly <= rd_dly - 1'd1;
		else begin
			DDRAM_DOUT <= ddr.exists(rd_a) ? ddr[rd_a] : 64'd0;
			DDRAM_DOUT_READY <= 1;
			rd_a <= rd_a + 1'd1;
			rd_left <= rd_left - 1'd1;
		end
	end
end

// ---------------------------------------------------------------- core
wire [15:0] SDRAM_DQ;
wire [35:0] dummy_ext;
emu emu(
	.CLK_50M(CLK_50M),
	.RESET(1'b0),
	.HPS_BUS(HPS_BUS),
	.CLK_VIDEO(), .CE_PIXEL(), .VIDEO_ARX(), .VIDEO_ARY(),
	.VGA_R(), .VGA_G(), .VGA_B(), .VGA_HS(), .VGA_VS(), .VGA_DE(), .VGA_F1(), .VGA_SL(),
	.VGA_SCALER(), .VGA_DISABLE(),
	.HDMI_WIDTH(12'd0), .HDMI_HEIGHT(12'd0), .HDMI_FREEZE(), .HDMI_BLACKOUT(), .HDMI_BOB_DEINT(),
	.LED_USER(), .LED_POWER(), .LED_DISK(), .BUTTONS(),
	.CLK_AUDIO(1'b0), .AUDIO_L(), .AUDIO_R(), .AUDIO_S(), .AUDIO_MIX(),
	.ADC_BUS(),
	.SD_SCK(), .SD_MOSI(), .SD_MISO(1'b0), .SD_CS(), .SD_CD(1'b0),
	.DDRAM_CLK(DDRAM_CLK), .DDRAM_BUSY(1'b0), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
	.SDRAM_CLK(), .SDRAM_CKE(), .SDRAM_A(), .SDRAM_BA(), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(), .SDRAM_DQMH(),
	.SDRAM_nCS(), .SDRAM_nCAS(), .SDRAM_nRAS(), .SDRAM_nWE(),
	.UART_CTS(1'b0), .UART_RTS(), .UART_RXD(1'b0), .UART_TXD(), .UART_DTR(), .UART_DSR(1'b0),
	.USER_IN(7'h7f), .USER_OUT(),
	.OSD_STATUS(1'b0)
);

// ---------------------------------------------------------------- 68K activity
// Instruction fetches (FC = program space) are logged per window, so a hang
// shows up as the same small address range over and over.
integer win_cycles = 4800000;   // 100ms
integer n_enp = 0, n_as = 0, in_user = 0;
integer fetches = 0, cdreg = 0, cyc = 0, ms = 0, stop_ms = 3000;
reg [23:0] fmin = 24'hffffff, fmax = 0, flast = 0;
reg old_as = 1;
wire [23:0] A = {emu.M68K_ADDR, 1'b0};
always @(posedge emu.CLK_48M) begin
	old_as <= emu.nAS;
	if (old_as & ~emu.nAS) begin
		if (emu.FC1 & ~emu.FC0) begin
			fetches = fetches + 1;
			if (A < fmin) fmin = A;
			if (A > fmax) fmax = A;
			flast = A;
			if (A >= 24'h400 && A < 24'h420) in_user = in_user + 1;
		end
		if (A[23:12] == 12'hFF0) cdreg = cdreg + 1;
	end
	cyc = cyc + 1;
	if (emu.CPU_EN_P) n_enp = n_enp + 1;
	if (old_as & ~emu.nAS) n_as = n_as + 1;
	if (cyc == win_cycles) begin
		cyc = 0; ms = ms + win_cycles / 48000;
		$display("[%5d ms] fetch %6d  pc %06x..%06x last %06x  cdreg %5d  frames %0d  cdd cmd/stat %0d/%0d  sectors %0d  user %0d  z80 %0d %04x..%04x snd_w %0d  cdwr %0d late %0d maxwait %0d",
			ms, fetches, fmin, fmax, flast, cdreg, frame, emu.hps_io.ncmd, emu.hps_io.nstat, emu.hps_io.nsect_sent, in_user, z80_m1, zmin, zmax, snd_w, wr_req, wr_late, wr_maxwait);
		z80_m1 = 0; zmin = 16'hffff; zmax = 0; snd_w = 0;
		$fflush;
		if ($test$plusargs("dbg")) $display("   nRESET_CORE %b nRESET %b cd_en %b en_p %0d as %0d locked %b nDTACK %b A %06x", emu.nRESET_CORE, emu.nRESET, emu.cd_en, n_enp, n_as, emu.locked, emu.nDTACK_ADJ, A);
		n_enp = 0; n_as = 0;
		fetches = 0; cdreg = 0; fmin = 24'hffffff; fmax = 0;
		if (ms >= stop_ms) $finish;
	end
end


// ---------------------------------------------------------------- traces
// 68K bus: sound latch and (+cdtrace) CD registers; Z80: fetch count
reg [15:0] rdat;
reg [23:0] cyc_a; reg cyc_rw;
reg z_m1_old = 0;
always @(posedge emu.CLK_48M) begin
	if (~emu.nAS) begin cyc_a <= A; cyc_rw <= emu.M68K_RW; if (~emu.nDTACK_ADJ) rdat <= emu.FX68K_DATAIN; end
	if (~old_as & emu.nAS) begin
		if (cyc_a[23:16] == 8'h32 && !cyc_rw) snd_w = snd_w + 1;
		if ((cyc_a[23:16] == 8'h32 || ($test$plusargs("cdtrace") && cyc_a[23:12] == 12'hFF0)) && ntr < max_tr) begin
			ntr = ntr + 1;
			$display("%t 68K %s %06x %04x", $time, cyc_rw ? "R" : "W", cyc_a, cyc_rw ? rdat : emu.FX68K_DATAOUT);
		end
	end
	z_m1_old <= emu.Z80CPU.cpu.z80_m1;
	if (emu.Z80CPU.cpu.z80_m1 & ~z_m1_old) begin
		z80_m1 = z80_m1 + 1;
		if (emu.Z80CPU.cpu.A < zmin) zmin = emu.Z80CPU.cpu.A;
		if (emu.Z80CPU.cpu.A > zmax) zmax = emu.Z80CPU.cpu.A;
	end
end


// ---------------------------------------------------------------- CD RAM write race
// A 68000 write to CD RAM starts in SDRAM some time after it is requested; it
// reads address and data off the bus then, so the 68000 must still be in the
// write cycle. Count writes that started too late.
reg wr_old = 0, wr_pend = 0;
always @(posedge emu.CLK_96M) begin
	wr_old <= emu.SDRAM_MUX.SDRAM_WR;
	if (emu.SDRAM_MUX.REQ_CD_WR & ~emu.DMA_RUNNING) begin wr_pend <= 1; wr_wait = 0; wr_req = wr_req + 1; end
	else if (wr_pend) wr_wait = wr_wait + 1;
	if (~wr_old & emu.SDRAM_MUX.SDRAM_WR & emu.SDRAM_MUX.CD_TR_RUN & ~emu.DMA_RUNNING & wr_pend) begin
		wr_pend <= 0;
		if (wr_wait > wr_maxwait) wr_maxwait = wr_wait;
		if (~emu.SDRAM_MUX.CD_WR_SDRAM_SIG) begin
			wr_late = wr_late + 1;
			if (wr_late <= 20) $display("%t late CD RAM write (waited %0d clocks at 96MHz)", $time, wr_wait);
		end
	end
end

// ---------------------------------------------------------------- frames
integer frame = 0, x = 0, y = 0, dump_every = 30, fd;
reg old_vbl = 1, old_hbl = 0;
reg [23:0] fb[0:320*240-1];
string fname, prefix;
always @(posedge emu.CLK_VIDEO) if (emu.ce_pix) begin
	old_hbl <= emu.HBlank[0];
	old_vbl <= emu.nBNKB;
	if (~emu.HBlank[0] & emu.nBNKB) begin
		if (x < 320 && y < 240) fb[y*320 + x] = {emu.R8, emu.G8, emu.B8};
		x = x + 1;
	end
	if (~old_hbl & emu.HBlank[0]) begin if (x > 0) y = y + 1; x = 0; end
	if (old_vbl & ~emu.nBNKB) begin
		if (y > 0 && (frame % dump_every) == 0) begin : dump
			integer i;
			fname = $sformatf("%s_%04d.ppm", prefix, frame);
			fd = $fopen(fname, "wb");
			$fwrite(fd, "P6\n320 224\n255\n");
			for (i = 0; i < 320*224; i++) $fwrite(fd, "%c%c%c", fb[i][23:16], fb[i][15:8], fb[i][7:0]);
			$fclose(fd);
		end
		frame = frame + 1; y = 0;
	end
end

initial begin
	if (!$value$plusargs("stop_ms=%d", stop_ms)) stop_ms = 3000;
	if (!$value$plusargs("dump_every=%d", dump_every)) dump_every = 30;
	if (!$value$plusargs("prefix=%s", prefix)) prefix = "frame";
end

endmodule
