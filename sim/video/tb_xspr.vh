// neo_xspr in the bench: VRAM/LO second ports and an SDRAM responder
reg        xs_enable = 0;
reg  [8:0] xs_skip = 9'd96;
integer    xs_lat = 12;          // C ROM read latency in 48MHz clocks
wire [10:0] XFV_ADDR; reg [15:0] XFV_Q;
wire [14:0] XSV_ADDR; reg [15:0] XSV_Q;
wire [15:0] XLO_ADDR; reg [7:0]  XLO_Q;
always @(posedge CLK_48M) begin
	XFV_Q <= fvram[XFV_ADDR];
	XSV_Q <= svram[XSV_ADDR];
	XLO_Q <= lorom[XLO_ADDR];
end
wire        XS_REQ;
wire [26:0] XS_ADDR;
`ifndef REALSDR
reg         XS_ACK = 0;
reg  [63:0] XS_DATA;
integer     xs_cnt = 0;
reg         xs_pend = 0;
always @(posedge CLK_48M) begin
	if (!xs_pend && XS_REQ != XS_ACK) begin xs_pend <= 1; xs_cnt <= xs_lat; end
	else if (xs_pend) begin
		if (xs_cnt > 1) xs_cnt <= xs_cnt - 1;
		else begin
			XS_DATA <= {crom[{XS_ADDR[20:3],2'd0}], crom[{XS_ADDR[20:3],2'd1}], crom[{XS_ADDR[20:3],2'd2}], crom[{XS_ADDR[20:3],2'd3}]};
			XS_ACK <= XS_REQ;
			xs_pend <= 0;
		end
	end
end

`endif
neo_xspr XSPR(
	.CLK(CLK_48M), .nRESET(nRESET), .ENABLE(xs_enable), .SKIP(xs_skip),
	.RASTERC(X_RASTERC), .PIXELC(X_PIXELC), .AA_COUNT(X_AA_COUNT), .AA_DISABLE(X_AA_DISABLE),
	.FV_ADDR(XFV_ADDR), .FV_Q(XFV_Q), .SV_ADDR(XSV_ADDR), .SV_Q(XSV_Q), .LO_ADDR(XLO_ADDR), .LO_Q(XLO_Q),
	.CROM_MASK(CROM_MASK), .CROM_BASE(7'd0), .SDRAM_OK(xs_sdram_ok),
	.XS_REQ(XS_REQ), .XS_ADDR(XS_ADDR), .XS_ACK(XS_ACK), .XS_DATA(XS_DATA),
	.PIXEL(XSPR_PIXEL), .OPAQUE(XSPR_OPAQUE)
);

`ifndef REALSDR
wire xs_sdram_ok = 1'b1;
`endif
integer xs_tmp;
initial begin
	xs_enable = $test$plusargs("XSPR");
	if ($value$plusargs("SKIP=%d", xs_tmp)) xs_skip = xs_tmp;
	if ($value$plusargs("XLAT=%d", xs_tmp)) xs_lat = xs_tmp;
end

// statistics: entries not drawn when a line ended, 68K cycles
integer xs_short_lines = 0, xs_max_cnt = 0, xs_drawn_total = 0, m68k_cycles = 0;
always @(posedge CLK_48M) begin
	if (XSPR.new_line && XSPR.run && frame == dump_frame) begin
		if (XSPR.ast != 0 || XSPR.b_full || XSPR.b_busy || XSPR.c_full) xs_short_lines = xs_short_lines + 1;
		if (XSPR.rcnt > xs_max_cnt) xs_max_cnt = XSPR.rcnt;
	end
end
`ifdef REALSDR
always @(posedge CLK_48M) if (m_state == 2 && frame == dump_frame) m68k_cycles = m68k_cycles + 1;
`endif
final $display("XSPR: max extra sprites on a line %0d, lines not finished %0d, 68K bus cycles in frame %0d, SDRAM reads %0d",
               xs_max_cnt, xs_short_lines, m68k_cycles,
`ifdef REALSDR
               SDR.nread
`else
               0
`endif
               );
integer xs_t = 0, xs_tdone = 0, xs_tmax = 0, xs_pdone = 0, xs_pmax = 0;
always @(posedge CLK_48M) begin
	if (XSPR.new_line) begin
		if (frame == dump_frame && xs_tdone > xs_tmax) xs_tmax = xs_tdone;
		if (frame == dump_frame && xs_pdone > xs_pmax) xs_pmax = xs_pdone;
		xs_t = 0; xs_tdone = 0; xs_pdone = 0;
	end else begin
		xs_t = xs_t + 1;
		if (XSPR.ast != 0 || XSPR.b_full || XSPR.b_busy || XSPR.c_full) xs_tdone = xs_t;
		if (XSPR.pst != 0) xs_pdone = xs_t;
	end
end
final $display("XSPR: busiest line: render done after %0d clocks, parse after %0d (line = 3072)", xs_tmax, xs_pmax);
