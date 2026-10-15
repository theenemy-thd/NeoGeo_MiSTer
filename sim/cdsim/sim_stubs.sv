// Simulation models for the NeoGeo core (Neo Geo CD boot test)
`timescale 1ns/1ps

// ---------------------------------------------------------------- dpram
module dpram #(parameter ADDRWIDTH=8, DATAWIDTH=8, NUMWORDS=1<<ADDRWIDTH, MEM_INIT_FILE="")
(
	input	                 clock_a,
	input	 [ADDRWIDTH-1:0] address_a,
	input	 [DATAWIDTH-1:0] data_a,
	input	                 wren_a,
	output reg [DATAWIDTH-1:0] q_a,
	input	                 clock_b,
	input	 [ADDRWIDTH-1:0] address_b,
	input	 [DATAWIDTH-1:0] data_b,
	input	                 wren_b,
	output reg [DATAWIDTH-1:0] q_b
);
reg [DATAWIDTH-1:0] m[0:NUMWORDS-1];
always @(posedge clock_a) begin if (wren_a) m[address_a] <= data_a; q_a <= m[address_a]; end
always @(posedge clock_b) begin if (wren_b) m[address_b] <= data_b; q_b <= m[address_b]; end
endmodule


module spram #(parameter ADDRWIDTH=8, DATAWIDTH=8, NUMWORDS=1<<ADDRWIDTH)
(
	input	                 clock,
	input	 [ADDRWIDTH-1:0] address,
	input	 [DATAWIDTH-1:0] data,
	input	                 wren,
	output reg [DATAWIDTH-1:0] q
);
reg [DATAWIDTH-1:0] m[0:NUMWORDS-1];
always @(posedge clock) begin if (wren) m[address] <= data; q <= m[address]; end
endmodule

module cpram(input clock, reset, wr, input [63:0] data, input rd, output [15:0] q);
assign q = 0;
endmodule

module altddio_out #(parameter extend_oe_disable="", intended_device_family="", invert_output="",
    lpm_hint="", lpm_type="", oe_reg="", power_up_high="", width=1)
  (input [width-1:0] datain_h, datain_l, input outclock, output [width-1:0] dataout,
   input aclr, aset, oe, outclocken, sclr, sset);
  assign dataout = datain_h;
endmodule

// ---------------------------------------------------------------- clocks
module pll(input refclk, rst, output reg outclk_0 = 0, output reg outclk_1 = 0, input [63:0] reconfig_to_pll,
  output [63:0] reconfig_from_pll, output reg locked = 0);
  assign reconfig_from_pll = 0;
  // 96MHz / 48MHz, rising edges aligned
  always begin #5.208 outclk_0 = 1; outclk_1 = ~outclk_1; #5.208 outclk_0 = 0; end
  initial begin #2000 locked = 1; end
endmodule

module pll_cfg(input mgmt_clk, mgmt_reset, output mgmt_waitrequest, input mgmt_read,
  output [31:0] mgmt_readdata, input mgmt_write, input [5:0] mgmt_address, input [31:0] mgmt_writedata,
  output [63:0] reconfig_to_pll, input [63:0] reconfig_from_pll);
  assign mgmt_waitrequest=0; assign mgmt_readdata=0; assign reconfig_to_pll=0;
endmodule

module CEGen(input CLK, RST_N, input integer IN_CLK, input integer OUT_CLK, output reg CE = 0);
  integer sum = 0;
  always @(negedge CLK or negedge RST_N)
    if (!RST_N) begin sum = 0; CE <= 0; end
    else begin
      CE <= 0;
      sum = sum + OUT_CLK;
      if (sum >= IN_CLK) begin sum = sum - IN_CLK; CE <= 1; end
    end
endmodule

// ---------------------------------------------------------------- Z80
// T80pa.vhd bus logic around the Verilog (ghdl) translation of the T80 core
module T80pa(input RESET_n, CLK, CEN_p, CEN_n, WAIT_n, INT_n, NMI_n, output reg MREQ_n, IORQ_n, RD_n, WR_n, output RFSH_n,
  input BUSRQ_n, output BUSAK_n, output [15:0] A, input [7:0] DI, output [7:0] DO);
  wire M1_n, IORQ, NoRead, Write, BUSAK, IntCycle_n, HALT_n;
  wire [2:0] MCycle, TState;
  wire [15:0] A_int;
  reg  [15:0] A_last;
  reg  [7:0] DI_Reg;
  reg  CEN_pol;
  reg  [1:0] IntCycleD_n;
  wire CEN = CEN_p & ~CEN_pol;
  assign BUSAK_n = BUSAK;
  assign A = (~NoRead | Write) ? A_int : A_last;
  t80_0_1_0_1_2_3_4_5_6_7 u0(.reset_n(RESET_n), .clk_n(CLK), .cen(CEN), .wait_n(1'b1), .int_n(INT_n), .nmi_n(NMI_n),
    .busrq_n(BUSRQ_n), .dinst(DI), .di(DI_Reg), .out0(1'b0), .dirset(1'b0), .dir(212'd0),
    .m1_n(M1_n), .iorq(IORQ), .noread(NoRead), .write(Write), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK),
    .a(A_int), .dout(DO), .mc(MCycle), .ts(TState), .intcycle_n(IntCycle_n), .inte(), .stop(), .regs());
  always @(posedge CLK) begin
    if (!RESET_n) begin
      WR_n <= 1; RD_n <= 1; IORQ_n <= 1; MREQ_n <= 1; DI_Reg <= 0; CEN_pol <= 0;
    end else if (CEN_p && !CEN_pol) begin
      CEN_pol <= 1;
      if (MCycle == 3'b001) begin
        if (TState == 3'b010) begin IORQ_n <= 1; MREQ_n <= 1; RD_n <= 1; end
      end else begin
        if (TState == 3'b001 && IORQ) begin WR_n <= ~Write; RD_n <= Write; IORQ_n <= 0; end
      end
    end else if (CEN_n && CEN_pol) begin
      if (TState == 3'b010) CEN_pol <= ~WAIT_n; else CEN_pol <= 0;
      if (TState == 3'b011 && BUSAK) DI_Reg <= DI;
      if (MCycle == 3'b001) begin
        if (TState == 3'b001) begin
          IntCycleD_n <= {IntCycleD_n[0], IntCycle_n};
          RD_n <= ~IntCycle_n; MREQ_n <= ~IntCycle_n; IORQ_n <= IntCycleD_n[1];
          A_last <= A_int;
        end
        if (TState == 3'b011) begin IntCycleD_n <= 2'b11; RD_n <= 1; MREQ_n <= 0; end
        if (TState == 3'b100) MREQ_n <= 1;
      end else begin
        if (!NoRead && !IORQ) begin
          if (TState == 3'b001) begin RD_n <= Write; MREQ_n <= 0; A_last <= A_int; end
        end
        if (TState == 3'b010) WR_n <= ~Write;
        if (TState == 3'b011) begin WR_n <= 1; RD_n <= 1; IORQ_n <= 1; MREQ_n <= 1; end
      end
    end
  end
  // for the testbench
  wire z80_m1 = ~M1_n;
endmodule

// ---------------------------------------------------------------- SDRAM
// Same interface and ready/dout timing as rtl/mem/sdram.sv (reads: dout valid
// when ready rises, 7 clocks per access, refresh 7 clocks). 64MB.
module sdram
(
	input             init,
	input             clk,
	inout      [15:0] SDRAM_DQ,
	output     [12:0] SDRAM_A,
	output            SDRAM_DQML,
	output            SDRAM_DQMH,
	output      [1:0] SDRAM_BA,
	output            SDRAM_nCS,
	output            SDRAM_nWE,
	output            SDRAM_nRAS,
	output            SDRAM_nCAS,
	output            SDRAM_CKE,
	output            SDRAM_CLK,
	input             SDRAM_EN,
	input             sel,
	input      [26:1] addr,
	output reg [15:0] dout,
	input      [15:0] din,
	input             wr,
	input       [1:0] bs,
	input             rd,
	output reg        ready = 0,
	input             refresh,
	input             cpsel,
	input      [26:1] cpaddr,
	input      [15:0] cpdin,
	output reg        cprd = 0,
	input             cpreq,
	output reg        cpbusy = 0
);
assign SDRAM_DQ = 16'hzzzz;
assign {SDRAM_A, SDRAM_DQML, SDRAM_DQMH, SDRAM_BA, SDRAM_CKE, SDRAM_CLK} = 0;
assign {SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS} = 4'hF;

localparam AW = 25;
reg [15:0] mem[0:(1<<AW)-1];

localparam ST_START = 0, ST_IDLE = 1, ST_WAIT = 2, ST_RW = 3, ST_I4 = 4, ST_I3 = 5, ST_I2 = 6, ST_I1 = 7, ST_RFSH = 8, ST_I5 = 9;
reg [3:0]  state = ST_START;
reg [2:0]  data_ready_delay = 0;
reg        refresh_old = 0;
reg [26:1] a;
reg        saved_wr;
reg [15:0] saved_data;
reg [1:0]  saved_bs;
reg [7:0]  startcnt = 0;
string init_f;
initial if ($value$plusargs("sdram_init=%s", init_f)) begin $readmemh(init_f, mem); $display("SDRAM preloaded from %s", init_f); end

always @(posedge clk) begin
	data_ready_delay <= data_ready_delay >> 1;
	if (data_ready_delay[0]) begin ready <= 1; dout <= mem[a[AW:1]]; end

	case (state)
		ST_START: if (!init) begin startcnt <= startcnt + 1'd1; if (&startcnt) begin state <= ST_IDLE; ready <= 1; end end
		ST_RFSH: state <= ST_I5;
		ST_I5: state <= ST_I4;
		ST_I4: state <= ST_I3;
		ST_I3: state <= ST_I2;
		ST_I2: state <= ST_I1;
		ST_I1: state <= ST_IDLE;
		ST_IDLE: begin
			if (refresh ^ refresh_old) begin
				state <= ST_RFSH;
				refresh_old <= refresh;
			end
			else if (sel & (rd | wr)) begin
				a <= addr;
				saved_wr <= wr;
				saved_data <= din;
				saved_bs <= bs;
				state <= ST_WAIT;
				ready <= 0;
			end
		end
		ST_WAIT: state <= ST_RW;
		ST_RW: begin
			state <= ST_I4;
			if (saved_wr) begin
				if (saved_bs[1]) mem[a[AW:1]][15:8] <= saved_data[15:8];
				if (saved_bs[0]) mem[a[AW:1]][7:0]  <= saved_data[7:0];
				ready <= 1;
			end
			else data_ready_delay[2] <= 1;
		end
		default: state <= ST_IDLE;
	endcase
end
endmodule

// ---------------------------------------------------------------- HPS
// Test controller in place of hps_io: sets the core up for Neo Geo CD, and
// plays the part of Main_MiSTer's Neo Geo CD drive (support/neogeo/neogeocd.cpp
// + support/megacd/megacdd.cpp) with no disc loaded.
module hps_io #(parameter CONF_STR="", CONF_STR_BRAM=0, PS2DIV=0, WIDE=0, VDNUM=1, BLKSZ=2, PS2WE=0, F12KEYMOD=0)
(
	input             clk_sys,
	inout      [45:0] HPS_BUS,
	output reg [31:0] joystick_0 = 0, joystick_1 = 0, joystick_2 = 0, joystick_3 = 0,
	output reg  [8:0] spinner_0 = 0, spinner_1 = 0,
	output reg [24:0] ps2_mouse = 0,
	output      [1:0] buttons,
	output reg [10:0] ps2_key = 0,
	output            forced_scandoubler,
	inout      [21:0] gamma_bus,
	output reg [127:0] status = 0,
	input       [15:0] status_menumask,
	output reg [64:0] RTC = 0,
	output reg [15:0] sdram_sz = 16'h8002,
	output reg [VDNUM-1:0] img_mounted = 0,
	output reg        img_readonly = 0,
	output reg [63:0] img_size = 0,
	input      [31:0] sd_lba[VDNUM],
	input  [VDNUM-1:0] sd_rd,
	input  [VDNUM-1:0] sd_wr,
	output reg [VDNUM-1:0] sd_ack = 0,
	output reg [12:0] sd_buff_addr = 0,
	output reg [15:0] sd_buff_dout = 0,
	input      [15:0] sd_buff_din[VDNUM],
	output reg        sd_buff_wr = 0,
	output reg        ioctl_download = 0,
	output reg [15:0] ioctl_index = 0,
	output reg        ioctl_wr = 0,
	output reg [26:0] ioctl_addr = 0,
	output reg [15:0] ioctl_dout = 0,
	input             ioctl_wait,
	inout      [35:0] EXT_BUS
);
assign buttons = 0;
assign forced_scandoubler = 0;
assign gamma_bus = 22'hzzzzzz;

reg [15:0] io_din = 0;
reg io_strobe = 0, io_enable = 0;
assign EXT_BUS[31:16] = io_din;
assign EXT_BUS[33] = io_strobe;
assign EXT_BUS[34] = io_enable;
assign EXT_BUS[35] = 1'b0;

integer press_ms = 0, start_ms = 0;
integer speed = 0, cdz = 0, poll_cycles = 480000;   // 10ms at 48MHz

task automatic clk(input integer n); repeat (n) @(posedge clk_sys); endtask
task automatic dl_word(input [26:0] a, input [15:0] d);
	begin
		ioctl_addr <= a; ioctl_dout <= d; ioctl_wr <= 1; clk(1);
		ioctl_wr <= 0; clk(8);
		while (ioctl_wait) clk(1);
	end
endtask
task automatic ext_word(input [15:0] d);
	begin io_din <= d; io_strobe <= 1; clk(1); io_strobe <= 0; clk(3); end
endtask

// ---- CDD model: megacdd.cpp logic, one data track (+iso=file) or no disc
localparam CD_STAT_STOP = 0, CD_STAT_PLAY = 1, CD_STAT_SEEK = 2, CD_STAT_PAUSE = 4, CD_STAT_OPEN = 5,
           CD_STAT_TOC = 9, CD_STAT_NO_DISC = 11, CD_STAT_END = 12, CD_STAT_TRAY = 14;
reg [3:0] stat[0:9];
reg [3:0] comm[0:9];
integer cdd_status = CD_STAT_STOP, latency = 10, lba = 0, index = 0;
reg need_reset = 1, has_command = 0;
integer ncmd = 0, nstat = 0, nsect_sent = 0;
reg loaded = 0;
integer nsect = 0;              // track 1 = sectors 0..nsect-1, data
integer ntracks = 1, trk_len = 3000;   // +tracks=N: tracks 2..N are audio, trk_len sectors each
function automatic integer trk_start(input integer t);   // t = 1..ntracks, ntracks+1 = leadout
	trk_start = (t <= 1) ? 0 : nsect + (t - 2) * trk_len;
endfunction
function automatic integer trk_of(input integer l);      // index (0-based) of the track holding l
	integer t;
	begin
		trk_of = ntracks;
		for (t = ntracks; t >= 1; t--) if (l < trk_start(t + 1)) trk_of = t - 1;
	end
endfunction
localparam ISO_MAX = 1<<22;
reg [7:0] iso[0:ISO_MAX-1];
string iso_f;
initial begin
	integer fd, n;
	if ($value$plusargs("iso=%s", iso_f)) begin
		fd = $fopen(iso_f, "rb");
		n = $fread(iso, fd);
		$fclose(fd);
		nsect = n / 2048; loaded = 1;
		if ($value$plusargs("nsect=%d", n)) nsect = n;
		if (!$value$plusargs("tracks=%d", ntracks)) ntracks = 1;
		$display("CD image %s: %0d sectors", iso_f, nsect);
	end
end

function automatic [7:0] bcd(input integer v); bcd = ((v / 10) << 4) | (v % 10); endfunction
function automatic [23:0] msf(input integer l);   // {M,S,F} BCD
	msf = {bcd(l / 4500), bcd((l / 75) % 60), bcd(l % 75)};
endfunction
task automatic put_msf(input integer l);
	reg [23:0] m;
	begin m = msf(l); stat[2]=m[23:20]; stat[3]=m[19:16]; stat[4]=m[15:12]; stat[5]=m[11:8]; stat[6]=m[7:4]; stat[7]=m[3:0]; end
endtask
wire [3:0] cur_type = (loaded && index == 0) ? 4'd1 : 4'd0;   // track type (1 = data)
function automatic integer last_f; last_f = loaded ? ntracks : 0; endfunction

task automatic cdd_reset;
	integer i;
	begin
		latency = 10; index = 0; lba = 0; cdd_status = CD_STAT_STOP;
		for (i = 0; i < 9; i++) stat[i] = 0;
		stat[9] = 4'hF;
	end
endtask

task automatic seek_to(input integer l, input integer play);
	integer d;
	begin
		latency = play ? 11 : 0;
		d = l - lba; if (d < 0) d = -d;
		latency = latency + (d * 120) / 270000;
		lba = l;
		index = loaded ? trk_of(l) : 0;
	end
endtask

task automatic cdd_exec;
	integer i, l, tr;
	begin
		case (comm[0])
			0: if (latency <= 3) begin
				stat[0] = cdd_status;
				if (stat[1] == 4'hF) begin stat[1] = 0; put_msf(lba + 150); stat[8] = cur_type ? 4 : 0; end
				else if (stat[1] == 0) begin put_msf(lba + 150); stat[8] = cur_type ? 4 : 0; end
				else if (stat[1] == 1) begin put_msf(lba - trk_start(index + 1) < 0 ? trk_start(index + 1) - lba : lba - trk_start(index + 1)); stat[8] = cur_type ? 4 : 0; end
				else if (stat[1] == 2) begin
					stat[2] = (index < last_f()) ? bcd(index + 1) >> 4 : 4'hA;
					stat[3] = (index < last_f()) ? bcd(index + 1) & 15 : 4'hA;
				end
			end
			1: begin cdd_status = CD_STAT_STOP; for (i = 0; i < 9; i++) stat[i] = 0; end
			2: begin
				if (cdd_status == CD_STAT_STOP) cdd_status = CD_STAT_TOC;
				stat[0] = cdd_status;
				case (comm[3])
					0: begin stat[1] = 0; put_msf(lba + 150); stat[8] = cur_type << 2; end
					1: begin stat[1] = 1; put_msf(lba - trk_start(index + 1) < 0 ? trk_start(index + 1) - lba : lba - trk_start(index + 1)); stat[8] = cur_type << 2; end
					2: begin stat[1] = 2; stat[2] = (index < last_f()) ? bcd(index + 1) >> 4 : 4'hA; stat[3] = (index < last_f()) ? bcd(index + 1) & 15 : 4'hA;
					         for (i = 4; i < 9; i++) stat[i] = 0; end
					3: begin stat[1] = 3; put_msf(trk_start(last_f() + 1) + 150); stat[8] = 0; end
					4: begin stat[1] = 4; stat[2] = 0; stat[3] = 1; stat[4] = bcd(last_f()) >> 4; stat[5] = bcd(last_f()) & 15; stat[6] = 0; stat[7] = 0; stat[8] = 0; end
					5: begin
						tr = comm[4] * 10 + comm[5];
						stat[1] = 5; put_msf(trk_start(tr) + 150);
						stat[6] = stat[6] | ((tr == 1 && loaded) ? 4'd8 : 4'd0);
						stat[8] = tr % 10;
					end
					6: begin stat[1] = 6; for (i = 2; i < 9; i++) stat[i] = 0; end
					default: ;
				endcase
			end
			3: begin
				l = (comm[2]*10 + comm[3]) * 4500 + (comm[4]*10 + comm[5]) * 75 + comm[6]*10 + comm[7] - 150;
				seek_to(l, 1);
				cdd_status = CD_STAT_PLAY;
				stat[0] = CD_STAT_SEEK; stat[1] = 4'hF; for (i = 2; i < 9; i++) stat[i] = 0;
				if ($test$plusargs("cddlog")) $display("%t CDD PLAY lba %0d latency %0d", $time, lba, latency);
			end
			4: begin
				l = (comm[2]*10 + comm[3]) * 4500 + (comm[4]*10 + comm[5]) * 75 + comm[6]*10 + comm[7] - 150;
				seek_to(l, 0);
				cdd_status = CD_STAT_SEEK; stat[0] = cdd_status; stat[1] = 4'hF; for (i = 2; i < 9; i++) stat[i] = 0;
			end
			6: begin cdd_status = CD_STAT_PAUSE; stat[0] = cdd_status; end
			7: begin cdd_status = CD_STAT_PLAY; stat[0] = cdd_status; end
			10: begin cdd_status = CD_STAT_PAUSE; stat[0] = cdd_status; end
			11: begin
				l = comm[2] * 10 + comm[3]; if (l > 0) l = l - 1;
				seek_to(trk_start(l + 1), 1); cdd_status = CD_STAT_PLAY;
				stat[0] = CD_STAT_SEEK; stat[1] = 4'hF; for (i = 2; i < 9; i++) stat[i] = 0;
			end
			12: begin cdd_status = loaded ? CD_STAT_TOC : CD_STAT_NO_DISC; stat[0] = CD_STAT_STOP; end
			13: begin cdd_status = CD_STAT_OPEN; stat[0] = CD_STAT_OPEN; end
			default: stat[0] = cdd_status;
		endcase
	end
endtask

function automatic [39:0] cdd_getstatus;
	reg [3:0] n9; integer i; reg [7:0] s;
	begin
		s = 5;
		for (i = 0; i < 9; i++) s = s + stat[i];
		n9 = ~s[3:0];
		cdd_getstatus = {n9, stat[8], stat[7], stat[6], stat[5], stat[4], stat[3], stat[2], stat[1], stat[0]};
	end
endfunction

// data sector: 12 bytes sync (0 here), header M S F mode, 2048 bytes, rest 0
task automatic send_sector;
	integer k; reg [23:0] m; reg [7:0] b0, b1;
	begin
		m = msf(lba + 150);
		ioctl_index <= 2; ioctl_download <= 1; clk(4);
		for (k = 0; k < 1176; k++) begin
			b0 = sbyte(2*k, m); b1 = sbyte(2*k+1, m);
			// the core stretches ioctl_wr to 16 clocks (ioctl_wr_x), so words
			// must come further apart than that; the HPS is much slower anyway
			ioctl_addr <= 2*k; ioctl_dout <= {b1, b0}; ioctl_wr <= 1; clk(1);
			ioctl_wr <= 0; clk(24);
			while (ioctl_wait) clk(1);
		end
		ioctl_download <= 0; clk(4);
		nsect_sent = nsect_sent + 1;
	end
endtask
function automatic [7:0] sbyte(input integer i, input [23:0] m);
	if (i == 12) sbyte = m[23:16];
	else if (i == 13) sbyte = m[15:8];
	else if (i == 14) sbyte = m[7:0];
	else if (i == 15) sbyte = 8'h01;
	else if (i >= 16 && i < 16 + 2048 && lba * 2048 + i - 16 < ISO_MAX) sbyte = iso[lba * 2048 + i - 16];
	else sbyte = 0;
endfunction

task automatic cdd_update;
	if (cdd_status == CD_STAT_STOP || cdd_status == CD_STAT_TRAY || cdd_status == CD_STAT_OPEN) begin
		if (latency > 0) latency = latency - 1;
		else if (!loaded) cdd_status = CD_STAT_NO_DISC;
	end else if (cdd_status == CD_STAT_SEEK) begin
		if (latency > 0) latency = latency - 1; else cdd_status = CD_STAT_PAUSE;
	end else if (cdd_status == CD_STAT_PLAY) begin
		if (latency > 0) latency = latency - 1;
		else if (!loaded || index >= last_f()) cdd_status = CD_STAT_END;
		else if (index != 0) begin lba = lba + 1; index = trk_of(lba); end   // audio: no data sent
		else if (tb.emu.CD_DATA_WR_READY) begin
			if ($test$plusargs("seclog")) $display("%t CDD sector %0d", $time, lba);
			send_sector;
			lba = lba + 1;
			index = trk_of(lba);
		end
	end
endtask

// command arrival (the HPS polls CD_GET continuously)
reg last_toggle = 0;
reg [47:0] cin;
always @(posedge clk_sys) begin
	if (tb.emu.cd_in[48] !== last_toggle && status[0] == 0) begin
		last_toggle <= tb.emu.cd_in[48];
		cin = tb.emu.cd_in[47:0];
		if (need_reset || cin[15:0] == 16'h00FF) begin need_reset = 0; cdd_reset; end
		begin : setc
			integer i;
			for (i = 0; i < 10; i++) comm[i] = cin[i*4 +: 4];
		end
		cdd_exec;
		has_command = 1;
		ncmd = ncmd + 1;
		if ($test$plusargs("cddlog") && (cin[3:0] != 0 || $test$plusargs("cddnop")))
			$display("%t CDD cmd %h -> stat %h (status %0d)", $time, cin[39:0], cdd_getstatus(), cdd_status);
	end
end

// 10ms timer: send status, update drive
initial begin
	reg [39:0] s;
	wait (status[0] == 0);
	forever begin
		clk(poll_cycles);
		if (has_command) begin
			s = cdd_getstatus();
			io_enable <= 1; clk(2);
			ext_word(16'h35);
			ext_word(s[15:0]);
			ext_word(s[31:16]);
			ext_word({8'h00, s[39:32]});
			io_enable <= 0; clk(4);
			has_command = 0;
			nstat = nstat + 1;
		end
		cdd_update;
	end
end

// ---- set-up: CD system, same order as neogeo_romset_tx()
initial begin
	if (!$value$plusargs("speed=%d", speed)) speed = 0;
	if (!$value$plusargs("cdz=%d", cdz)) cdz = 0;
	status[0] = 1;
	status[2] = cdz[0];
	status[46:45] = speed[1:0];
	clk(200);
	// notify_conf: cfg = cd_en
	ioctl_index <= 10; ioctl_download <= 1; clk(4);
	dl_word(0, 16'h8000); dl_word(2, 16'h0000); dl_word(4, 16'h8000); dl_word(6, 0); dl_word(8, 0);
	ioctl_download <= 0; clk(20);
	// (BIOS is preloaded into the SDRAM model by the testbench)
	// notify_conf again
	ioctl_index <= 10; ioctl_download <= 1; clk(4);
	dl_word(0, 16'h8000); dl_word(2, 16'h0000); dl_word(4, 16'h8000); dl_word(6, 0); dl_word(8, 0);
	ioctl_download <= 0; clk(20);
	status[0] = 0;
	if ($value$plusargs("press_ms=%d", press_ms)) fork begin
		clk(press_ms * 48000); joystick_0[4] <= 1; $display("%t HPS: button A down", $time);
		clk(100 * 48000); joystick_0[4] <= 0;
	end join_none
	if ($value$plusargs("start_ms=%d", start_ms)) fork begin
		clk(start_ms * 48000); joystick_0[8] <= 1; $display("%t HPS: START down", $time);
		clk(100 * 48000); joystick_0[8] <= 0;
		clk(500 * 48000); joystick_0[8] <= 1; $display("%t HPS: START down", $time);
		clk(100 * 48000); joystick_0[8] <= 0;
	end join_none
	$display("%t HPS: core released from reset, speed %0d, CDZ %0d", $time, speed, cdz);
end
endmodule
