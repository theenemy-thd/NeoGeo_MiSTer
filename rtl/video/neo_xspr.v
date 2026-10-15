//============================================================================
//  SNK NeoGeo for MiSTer - extra sprite renderer (no 96 sprites per line limit)
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// The LSPC draws at most 96 sprites per line: the first 96 sprites (in sprite
// number order) that cross the line. This module draws the ones after those
// into its own line buffers, and NEO-B1 shows its pixels on top of the LSPC's
// sprites (later sprites have priority on the Neo Geo) and under the fix layer.
//
// It works one line ahead of the display, like the LSPC:
//   during line s:  parse   line s+2 (all 381 sprites, keep the actives after
//                                     the first SKIP of them)
//                   render  line s+1 (from the list parsed during line s-1)
//                   display line s
// Parsing reads sprite attributes from a second port of the fast VRAM,
// rendering reads the tile map from a second port of the slow VRAM, the LO
// (vertical shrink) ROM through its spare port, and sprite graphics from
// SDRAM through the SDRAM mux (lowest priority, between the LSPC's fetches).
// It follows the core's LSPC exactly (same shrink tables, "continuous"
// sprites, auto-animation, chaining), which is checked in simulation by
// making it draw every sprite with the LSPC's sprites hidden.
//
// If a line has more extra sprites than can be fetched in one line time, the
// last ones are not drawn (as without this module).

module neo_xspr #(
	parameter MAXOVF = 192             // extra sprites per line (after the first 96)
)(
	input             CLK,             // 48MHz
	input             nRESET,
	input             ENABLE,
	input       [8:0] SKIP,            // 96; 0 to draw everything (test)

	input       [8:0] RASTERC,
	input       [8:0] PIXELC,
	input       [2:0] AA_COUNT,
	input             AA_DISABLE,

	output reg [10:0] FV_ADDR,         // fast VRAM (SCB2-4), 1 clock latency
	input      [15:0] FV_Q,
	output reg [14:0] SV_ADDR,         // slow VRAM (SCB1), 1 clock latency
	input      [15:0] SV_Q,
	output reg [15:0] LO_ADDR,         // LO ROM, 1 clock latency
	input       [7:0] LO_Q,

	input      [26:0] CROM_MASK,
	input       [6:0] CROM_BASE,       // C ROM position in SDRAM (MB)
	input             SDRAM_OK,        // sprites enabled, no refresh period
	output reg        XS_REQ = 0,      // toggle
	output reg [26:0] XS_ADDR,
	input             XS_ACK,          // toggles when XS_DATA is valid
	input      [63:0] XS_DATA,

	output     [11:0] PIXEL,           // to NEO-B1, valid on CLK_EN_6MB
	output            OPAQUE
);

localparam [8:0] LAST_SPRITE = 9'd380;

// ------------------------------------------------------------- line timing
// RASTERC changes at the start of each line period (PIXELC 256). LC counts
// the periods; its LSB selects the list and line buffer banks.
reg  [8:0] rast_d;
reg        lc = 0;
wire       new_line = (RASTERC != rast_d);
always @(posedge CLK) begin
	rast_d <= RASTERC;
	if (new_line) lc <= ~lc;
end

wire [8:0] line_disp = RASTERC ^ 9'h100;         // scanline shown in this period
wire [8:0] line_rend = line_disp + 9'd1;
wire [8:0] line_pars = line_disp + 9'd2;
// banks, used on the new_line clock (LC still holds the previous period's value)
wire       lc_rend   = lc;           // this period + 1
wire       lc_pars   = ~lc;          // this period + 2

function visible(input [8:0] l);
	visible = (l >= 9'd16) && (l < 9'd240);
endfunction

// ------------------------------------------------------------- lists
// Entry: sprite # (9), X (9), h-shrink (4), v-shrink (8), SCB3 Y (9), size (6)
localparam EW = 45;
localparam LW = $clog2(MAXOVF);
reg  [EW-1:0] list[0:(2<<LW)-1];
reg  [LW:0]   list_cnt[0:1];
reg  [EW-1:0] list_q;
reg  [LW:0]   list_rd;
reg           list_we;
reg  [LW:0]   list_wa;
reg  [EW-1:0] list_wd;
reg           list_wbank, list_rbank;
always @(posedge CLK) begin
	if (list_we) list[{list_wbank, list_wa[LW-1:0]}] <= list_wd;
	list_q <= list[{list_rbank, list_rd[LW-1:0]}];
end

// ------------------------------------------------------------- parser
localparam P_IDLE = 2'd0, P_Y = 2'd1, P_Z = 2'd2, P_X = 2'd3;
reg  [1:0] pst = P_IDLE;
reg  [8:0] pn;                 // sprite #
reg  [8:0] ppos;               // actives so far
reg  [LW:0] povf;
reg  [8:0] pline;
reg        pbank;
reg  [8:0] ld_ys;  reg [5:0] ld_rows;   // last non-sticky SCB3 (for on-line test)
reg  [8:0] ch_x;   reg [3:0] ch_zx;     // chaining state over the active list
reg  [7:0] ch_zy;  reg [8:0] ch_ys; reg [5:0] ch_rows;
reg        p_sticky;
reg        pwait;
reg [15:0] p_zc;

wire       y_sticky = FV_Q[6];
wire [8:0] y_ys     = y_sticky ? ld_ys   : FV_Q[15:7];
wire [5:0] y_rows   = y_sticky ? ld_rows : FV_Q[5:0];
wire [8:0] y_sl     = pline + y_ys;
wire       y_active = (y_rows != 0) && (y_rows[5] || (y_sl < {y_rows[4:0], 4'd0}));

always @(posedge CLK) begin
	list_we <= 0;
	if (!nRESET || !ENABLE) begin
		pst <= P_IDLE;
		list_cnt[0] <= 0;
		list_cnt[1] <= 0;
	end
	else if (new_line) begin
		// start parsing line s+2 (the previous parse has always finished)
		pline <= line_pars;
		pbank <= lc_pars;
		list_cnt[lc_pars] <= 0;
		pn <= 0; ppos <= 0; povf <= 0;
		ld_ys <= 0; ld_rows <= 0;
		ch_x <= 0; ch_zx <= 0; ch_zy <= 0; ch_ys <= 0; ch_rows <= 0;
		FV_ADDR <= 11'h200;
		pwait <= 1;
		pst <= visible(line_pars) ? P_Y : P_IDLE;
	end
	else if (pwait) pwait <= 0;        // memory read of the new address
	else case (pst)
		P_Y: begin     // FV_Q = SCB3[pn]
			if (!y_sticky) begin
				ld_ys <= FV_Q[15:7];
				ld_rows <= FV_Q[5:0];
			end
			p_sticky <= y_sticky;
			if (y_active) begin
				FV_ADDR <= {2'b00, pn};            // SCB2
				pwait <= 1;
				pst <= P_Z;
				if (!y_sticky) begin ch_ys <= y_ys; ch_rows <= y_rows; end
			end
			else if (pn == LAST_SPRITE) begin
				list_cnt[pbank] <= povf;
				pst <= P_IDLE;
			end
			else begin
				pn <= pn + 1'd1;
				FV_ADDR <= {2'b01, pn + 1'd1};     // SCB3
				pwait <= 1;
			end
		end
		P_Z: begin     // FV_Q = SCB2[pn]
			p_zc <= FV_Q;
			FV_ADDR <= {2'b10, pn};                // SCB4
			pwait <= 1;
			pst <= P_X;
		end
		P_X: begin     // FV_Q = SCB4[pn]
			if (p_sticky) begin
				ch_x  <= ch_x + {5'd0, ch_zx} + 1'd1;
				ch_zx <= p_zc[11:8];
			end
			else begin
				ch_x  <= FV_Q[15:7];
				ch_zx <= p_zc[11:8];
				ch_zy <= p_zc[7:0];
			end
			if (ppos >= SKIP && povf != MAXOVF) begin
				list_we    <= 1;
				list_wbank <= pbank;
				list_wa    <= povf;
				list_wd    <= {pn,
				               p_sticky ? ch_x + {5'd0, ch_zx} + 1'd1 : FV_Q[15:7],
				               p_zc[11:8],
				               p_sticky ? ch_zy : p_zc[7:0],
				               ch_ys, ch_rows};
				povf <= povf + 1'd1;
			end
			ppos <= ppos + 1'd1;
			if (pn == LAST_SPRITE) begin
				list_cnt[pbank] <= (ppos >= SKIP && povf != MAXOVF) ? povf + 1'd1 : povf;
				pst <= P_IDLE;
			end
			else begin
				pn <= pn + 1'd1;
				FV_ADDR <= {2'b01, pn + 1'd1};
				pwait <= 1;
				pst <= P_Y;
			end
		end
		default: ;
	endcase
end

// ------------------------------------------------------------- renderer
// Stage A: list entry -> LO ROM -> tile map -> C ROM address
// Stage B: C ROM fetch through the SDRAM mux
// Stage C: 16 pixels into the line buffer (h-shrink, h-flip, transparency),
//          2 per clock (even and odd X are in separate RAMs)
localparam A_IDLE = 3'd0, A_LIST = 3'd1, A_ENT = 3'd2, A_LO = 3'd3, A_T0 = 3'd4, A_T1 = 3'd5, A_T2 = 3'd6, A_T3 = 3'd7;
reg  [2:0] ast = A_IDLE;
reg  [8:0] rline;
reg        rbank;
reg  [LW:0] rcnt;

reg  [8:0] a_n, a_x; reg [3:0] a_zx;
reg        a_inv;
reg  [3:0] a_sy0;
reg [15:0] a_code_lo;

// A -> B
reg        b_full = 0;
reg [26:0] b_addr; reg [7:0] b_pal; reg b_hflip; reg [3:0] b_zx; reg [8:0] b_x;
// B (request in flight / data waiting for C)
reg        b_busy = 0, b_got = 0, b_discard = 0;
reg [63:0] b_data; reg [7:0] bb_pal; reg bb_hflip; reg [3:0] bb_zx; reg [8:0] bb_x;
// C
reg        c_full = 0;
reg [63:0] c_data; reg [7:0] c_pal; reg c_hflip; reg [3:0] c_zx;
reg  [2:0] c_k;                 // pixel pair
reg  [8:0] c_xx;
reg        lbe_we, lbo_we;
reg  [8:0] lbe_wa, lbo_wa;
reg [11:0] lbe_wd, lbo_wd;

// Y -> LO ROM address (as the LSPC: SPR_Y_ADD, LO_LINE_A/B, SPR_CONTINUOUS)
wire [8:0] e_sl   = rline + list_q[14:6];
wire       e_inv  = e_sl[8];
wire [7:0] e_zl   = e_sl[7:0] ^ {8{e_inv}};
wire [7:0] e_zy   = list_q[22:15];
wire [5:0] e_rows = list_q[5:0];
wire       e_cont = e_rows[5] & e_rows[0] & (e_zl > e_zy);
wire [7:0] e_zlb  = e_zl + {~e_zy[6:0], 1'b0};
wire [7:0] e_zl2  = e_cont ? ~e_zlb : e_zl;

// tile attributes -> C ROM address
wire [15:0] t_attr = SV_Q;
wire        t_aa3  = t_attr[3] & ~AA_DISABLE;
wire        t_aa2  = (t_attr[2] & ~AA_DISABLE) | t_aa3;
wire [19:0] t_code = {t_attr[7:4], a_code_lo[15:3],
                      t_aa3 ? AA_COUNT[2] : a_code_lo[2],
                      t_aa2 ? AA_COUNT[1:0] : a_code_lo[1:0]};
wire  [3:0] t_sy   = a_sy0 ^ {4{t_attr[1]}};
wire [26:0] c_addr_masked = {t_code, t_sy, 3'b000} & CROM_MASK;

// h-shrink tables measured on the core: source pixels drawn for each value
function [15:0] zoom_row(input [3:0] z);
	case (z)
		4'd0:  zoom_row = 16'b0000000100000000;
		4'd1:  zoom_row = 16'b0000000100010000;
		4'd2:  zoom_row = 16'b0001000100010000;
		4'd3:  zoom_row = 16'b0001000100010100;
		4'd4:  zoom_row = 16'b0101000100010100;
		4'd5:  zoom_row = 16'b0101000101010100;
		4'd6:  zoom_row = 16'b0101010101010100;
		4'd7:  zoom_row = 16'b0101010101010101;
		4'd8:  zoom_row = 16'b0101011101010101;
		4'd9:  zoom_row = 16'b0101011101011101;
		4'd10: zoom_row = 16'b1101011101011101;
		4'd11: zoom_row = 16'b1101011111011101;
		4'd12: zoom_row = 16'b1111011111011101;
		4'd13: zoom_row = 16'b1111011111011111;
		4'd14: zoom_row = 16'b1111111111011111;
		4'd15: zoom_row = 16'b1111111111111111;
	endcase
endfunction

// colour of pixel k (screen order) of the fetched line
function [3:0] pix(input [63:0] d, input hflip, input [3:0] k);
	reg [3:0] src; reg [31:0] h;
	begin
		src = hflip ? ~k : k;
		h = src[3] ? d[31:0] : d[63:32];
		pix = {h[24 + src[2:0]], h[16 + src[2:0]], h[8 + src[2:0]], h[src[2:0]]};
	end
endfunction

wire [15:0] c_zrow = zoom_row(c_zx);
wire        c_s0   = c_zrow[{c_k, 1'b0}];            // pixel 2j drawn
wire        c_s1   = c_zrow[{c_k, 1'b1}];            // pixel 2j+1 drawn
wire  [3:0] c_col0 = pix(c_data, c_hflip, {c_k, 1'b0});
wire  [3:0] c_col1 = pix(c_data, c_hflip, {c_k, 1'b1});
wire  [8:0] c_x0   = c_xx;                           // where they go
wire  [8:0] c_x1   = c_xx + {8'd0, c_s0};
wire        c_w0   = c_s0 & (c_col0 != 0);
wire        c_w1   = c_s1 & (c_col1 != 0);

wire run = nRESET & ENABLE;

always @(posedge CLK) begin
	lbe_we <= 0;
	lbo_we <= 0;

	// ---- stage A
	if (!run || new_line) begin
		ast <= A_IDLE;
		b_full <= 0;
		if (run && new_line && visible(line_rend)) begin
			rline <= line_rend;
			rbank <= lc_rend;
			rcnt  <= list_cnt[lc_rend];
			list_rbank <= lc_rend;
			list_rd <= 0;
			ast <= A_LIST;
		end
	end
	else begin
		case (ast)
			A_LIST: ast <= (list_rd == rcnt) ? A_IDLE : A_ENT;   // list_q loads
			A_ENT: begin                                           // list_q valid
				a_n  <= list_q[44:36];
				a_x  <= list_q[35:27];
				a_zx <= list_q[26:23];
				LO_ADDR <= {e_zy, e_zl2};
				a_inv <= e_inv ^ e_cont;
				ast <= A_LO;
			end
			A_LO: ast <= A_T0;                                     // LO ROM read
			A_T0: begin                                            // LO_Q valid
				a_sy0   <= LO_Q[3:0] ^ {4{a_inv}};
				SV_ADDR <= {a_n, a_inv, LO_Q[7:4] ^ {4{a_inv}}, 1'b0};
				ast <= A_T1;
			end
			A_T1: begin                                            // tile code read
				SV_ADDR[0] <= 1'b1;
				ast <= A_T2;
			end
			A_T2: begin                                            // SV_Q = tile code
				a_code_lo <= SV_Q;
				ast <= A_T3;
			end
			A_T3: if (!b_full) begin                               // SV_Q = attributes
				b_addr  <= c_addr_masked + {CROM_BASE, 20'd0};
				b_pal   <= t_attr[15:8];
				b_hflip <= t_attr[0];
				b_zx    <= a_zx;
				b_x     <= a_x;
				b_full  <= 1;
				list_rd <= list_rd + 1'd1;
				ast <= A_LIST;
			end
			default: ;
		endcase
	end

	// ---- stage B: one SDRAM read at a time. A request in flight is always
	// completed (its data dropped if the line changed meanwhile).
	if (!b_busy) begin
		if (run && !new_line && b_full && SDRAM_OK) begin
			XS_ADDR  <= b_addr;
			XS_REQ   <= ~XS_REQ;
			b_busy   <= 1;
			b_got    <= 0;
			b_discard <= 0;
			bb_pal   <= b_pal; bb_hflip <= b_hflip; bb_zx <= b_zx; bb_x <= b_x;
			b_full   <= 0;
		end
	end
	else begin
		if (!run || new_line) b_discard <= 1;
		if (!b_got && (XS_ACK == XS_REQ)) begin
			b_data <= XS_DATA;
			b_got  <= 1;
		end
		if (b_got) begin
			if (b_discard || !run || new_line) b_busy <= 0;
			else if (!c_full) begin
				c_data <= b_data; c_pal <= bb_pal; c_hflip <= bb_hflip; c_zx <= bb_zx;
				c_xx <= bb_x; c_k <= 0;
				c_full <= 1;
				b_busy <= 0;
			end
		end
	end

	// ---- stage C: two source pixels per clock; two drawn ones always have
	// consecutive X, so they go to different RAMs
	if (!run || new_line) c_full <= 0;
	else if (c_full) begin
		if (c_w0) begin
			if (c_x0[0]) begin lbo_we <= 1; lbo_wa <= {rbank, c_x0[8:1]}; lbo_wd <= {c_pal, c_col0}; end
			else         begin lbe_we <= 1; lbe_wa <= {rbank, c_x0[8:1]}; lbe_wd <= {c_pal, c_col0}; end
		end
		if (c_w1) begin
			if (c_x1[0]) begin lbo_we <= 1; lbo_wa <= {rbank, c_x1[8:1]}; lbo_wd <= {c_pal, c_col1}; end
			else         begin lbe_we <= 1; lbe_wa <= {rbank, c_x1[8:1]}; lbe_wd <= {c_pal, c_col1}; end
		end
		c_xx <= c_xx + {8'd0, c_s0} + {8'd0, c_s1};
		c_k <= c_k + 1'd1;
		if (c_k == 3'd7) c_full <= 0;
	end
end

// ------------------------------------------------------------- line buffers
// Two 512-pixel buffers (palette + colour; colour 0 = empty), each split in
// even and odd X. The display side reads each pixel for NEO-B1 and then
// clears it.
// PIXEL/OPAQUE must be valid at NEO-B1's CLK_EN_6MB, 3 clocks after PIXELC
// changes, and NEO-B1 registers the pixel for the next PIXELC value: so the
// buffer is read at the screen X of PIXELC + 1.
wire [8:0] pix_next = (PIXELC == 9'd511) ? 9'd128 : PIXELC + 1'd1;
wire       x_ok     = (pix_next >= 9'd271) || (pix_next >= 9'd128 && pix_next <= 9'd206);
wire [8:0] x_out    = (pix_next >= 9'd271) ? pix_next - 9'd271 : pix_next - 9'd128 + 9'd241;

reg  [8:0] pix_d;
reg  [2:0] pix_age;            // clocks since PIXELC changed
always @(posedge CLK) begin
	pix_d <= PIXELC;
	pix_age <= (PIXELC != pix_d) ? 3'd0 : (pix_age == 3'd7 ? 3'd7 : pix_age + 1'd1);
end
// clear the pixel 5 clocks after PIXELC changed (NEO-B1 took it at 3)
wire       lb_clr = (pix_age == 3'd4) && x_ok;

wire [11:0] lbe_q, lbo_q;
reg         x_ok_r, x_odd_r;
dpram #(9, 12) LBE(
	.clock_a(CLK), .address_a(lbe_wa), .data_a(lbe_wd), .wren_a(lbe_we), .q_a(),
	.clock_b(CLK), .address_b({lc, x_out[8:1]}), .data_b(12'd0), .wren_b(lb_clr & ~x_out[0]), .q_b(lbe_q)
);
dpram #(9, 12) LBO(
	.clock_a(CLK), .address_a(lbo_wa), .data_a(lbo_wd), .wren_a(lbo_we), .q_a(),
	.clock_b(CLK), .address_b({lc, x_out[8:1]}), .data_b(12'd0), .wren_b(lb_clr & x_out[0]), .q_b(lbo_q)
);
always @(posedge CLK) begin
	x_ok_r  <= x_ok & ENABLE & visible(line_disp);
	x_odd_r <= x_out[0];
end
wire [11:0] lb_q = x_odd_r ? lbo_q : lbe_q;

assign PIXEL  = lb_q;
assign OPAQUE = x_ok_r && (lb_q[3:0] != 4'd0);

endmodule
