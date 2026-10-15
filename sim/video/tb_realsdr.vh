// Real sdram_mux + behavioural SDRAM (sdram.sv timing) + 68000 ROM traffic
wire        SDRAM_WR, SDRAM_RD, SDRAM_RFSH, SDRAM_READY;
wire [26:1] SDRAM_ADDR;
wire [15:0] SDRAM_DOUT, SDRAM_DIN;
wire  [1:0] SDRAM_BS;
wire [63:0] CR_DOUBLE;
wire [15:0] PROM_DATA;
wire        PROM_DATA_READY;
`ifndef XSPR
wire        XS_REQ = 0;
wire [26:0] XS_ADDR = 0;
`endif
wire        XS_ACK;
wire [63:0] XS_DATA;

// 68000 at 24MHz reading ROM: bus cycles as fast as the SDRAM allows
reg        m_nas = 1, m_nromoe = 1;
reg [19:0] m_addr = 0;
integer    m_state = 0, m_gap = 0, m_on = 0;
always @(posedge CLK_48M) begin
	if (!m_on || !nRESET) begin m_nas <= 1; m_nromoe <= 1; m_state <= 0; end
	else case (m_state)
		0: if (m_gap > 0) m_gap <= m_gap - 1; else begin
			m_addr <= $urandom; m_nas <= 0; m_nromoe <= 0; m_state <= 1; end
		1: if (PROM_DATA_READY) m_state <= 2;
		2: begin m_nas <= 1; m_nromoe <= 1; m_state <= 3; end
		3: begin m_gap <= $urandom % 4; m_state <= 0; end
	endcase
end

// refresh in the lines outside 12..243 (like the core, only in vblank)
wire RFSH = (LSPC.RASTERC < 9'd268) || (LSPC.RASTERC > 9'd499);

sdram_mux MUX(
	.CLK(CLK_96M), .nRESET(nRESET), .nSYSTEM_G(1'b1), .SYSTEM_CDx(1'b0),
	.M68K_ADDR(m_addr), .M68K_DATA(16'd0), .nAS(m_nas), .nLDS(1'b0), .nUDS(1'b0),
	.DATA_TYPE(1'b0), .nROMOE(m_nromoe), .nPORTOE(1'b1), .nSROMOE(1'b1), .P2ROM_ADDR(27'd0),
	.PROM_DATA(PROM_DATA), .PROM_DATA_READY(PROM_DATA_READY),
	.PCK2(PCK2), .S_LATCH(16'd0), .FIX_BANK(2'd0), .FIX_EN(1'b1), .SROM_DATA(),
	.PCK1(PCK1), .CROM_ADDR(CROM_ADDR), .SPR_EN(1'b1), .CR_DOUBLE(CR_DOUBLE),
	.REFRESH_EN(RFSH),
	.SDRAM_WR(SDRAM_WR), .SDRAM_RD(SDRAM_RD), .SDRAM_ADDR(SDRAM_ADDR), .SDRAM_DOUT(SDRAM_DOUT),
	.SDRAM_DIN(SDRAM_DIN), .SDRAM_READY(SDRAM_READY), .SDRAM_BS(SDRAM_BS), .SDRAM_RFSH(SDRAM_RFSH),
	.DL_EN(1'b0), .DL_DATA(16'd0), .DL_ADDR(27'd0), .DL_WR(1'b0),
	.DMA_RUNNING(1'b0), .DMA_ADDR_IN(24'd0), .DMA_ADDR_OUT(24'd0), .DMA_DATA_OUT(16'd0), .DMA_SDRAM_BUSY(),
	.CD_TR_AREA(3'd0), .CD_EXT_WR(1'b0), .CD_EXT_RD(1'b0), .CD_BANK_SPR(2'd0), .CD_USE_SPR(1'b0),
	.CD_TR_RD_SPR(1'b0), .CD_TR_WR_SPR(1'b0), .CD_USE_FIX(1'b0), .CD_TR_RD_FIX(1'b0), .CD_TR_WR_FIX(1'b0),
	.XS_REQ(XS_REQ), .XS_ADDR(XS_ADDR), .XS_ACK(XS_ACK), .XS_DATA(XS_DATA)
);

sdram_beh #(21) SDR(
	.clk(CLK_96M), .addr(SDRAM_ADDR), .dout(SDRAM_DOUT), .din(SDRAM_DIN), .wr(SDRAM_WR), .bs(SDRAM_BS),
	.rd(SDRAM_RD), .ready(SDRAM_READY), .refresh(SDRAM_RFSH)
);
wire xs_sdram_ok = ~RFSH;

integer k;
initial begin
	m_on = $test$plusargs("M68K");
	#1;
	for (k = 0; k < (1<<20); k = k + 1) SDR.mem[k] = crom[k];
	for (k = (1<<20); k < (1<<21); k = k + 1) SDR.mem[k] = 16'h4E71;
end
