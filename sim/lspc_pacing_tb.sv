// fx68k + real LSPC: a BIOS-like VRAM write loop and read-back at 12/18/24MHz
// with the LSPC access pacing from neogeo.sv (pacing_block.vh is copied from it).
// Define NOPACE to force the pacing off (reproduces the overclock glitch).
`timescale 1ns/1ps

module tb;

reg CLK_48M = 0;
always #10.4167 CLK_48M = ~CLK_48M;

// clock enables as in neogeo.sv / clocks.v
reg CLK_EN_24M_N=0, CLK_EN_24M_P=0, CLK_68KCLK=0;
always @(posedge CLK_48M) begin
    CLK_EN_24M_N <= ~CLK_EN_24M_N;
    CLK_EN_24M_P <= CLK_EN_24M_N;
end
always @(posedge CLK_48M) if (CLK_EN_24M_P) CLK_68KCLK <= ~CLK_68KCLK;
wire CLK_EN_68K_P = ~CLK_68KCLK & CLK_EN_24M_P;
wire CLK_EN_68K_N =  CLK_68KCLK & CLK_EN_24M_P;

reg  [1:0] speed_sel = 0;
reg        nRESET = 0;
wire       CPU_EN_P, CPU_EN_N, CPU_OVERCLOCK;

cpu_speed CPU_SPEED(
    .CLK(CLK_48M), .nRESET(nRESET), .SPEED(speed_sel), .SLOW(1'b0),
    .CLK_EN_68K_P(CLK_EN_68K_P), .CLK_EN_68K_N(CLK_EN_68K_N),
    .CPU_EN_P(CPU_EN_P), .CPU_EN_N(CPU_EN_N), .OVERCLOCK(CPU_OVERCLOCK)
);

// ---------------- 68000
reg reset = 1;
always @(posedge CLK_48M) if (CPU_EN_N) reset <= ~nRESET;

wire        M68K_RW, nAS, nUDS, nLDS;
wire [23:1] M68K_ADDR;
wire [15:0] FX68K_DATAOUT;
wire [15:0] FX68K_DATAIN;
wire        nDTACK_ADJ;

fx68k cpu(
    .clk(CLK_48M), .extReset(reset), .pwrUp(reset),
    .enPhi1(CPU_EN_P), .enPhi2(CPU_EN_N),
    .eRWn(M68K_RW), .ASn(nAS), .UDSn(nUDS), .LDSn(nLDS),
    .BGn(), .BRn(1'b1), .BGACKn(1'b1), .HALTn(1'b1),
    .DTACKn(nDTACK_ADJ), .VPAn(1'b1), .BERRn(1'b1),
    .IPL0n(1'b1), .IPL1n(1'b1), .IPL2n(1'b1),
    .FC0(), .FC1(), .FC2(),
    .iEdb(FX68K_DATAIN), .oEdb(FX68K_DATAOUT), .eab(M68K_ADDR),
    .E(), .VMAn(), .oRESETn(), .oHALTEDn()
);

// ---------------- NEO-C1 style decode (LSPC at $3C0000-$3DFFFF)
wire nLSPC_ZONE = ~(M68K_ADDR[23:17] == 7'b0011_110) | nAS;
wire nLSPWE = M68K_RW  | nUDS | nLSPC_ZONE;
wire nLSPOE = ~M68K_RW | nUDS | nLSPC_ZONE;
wire nRAM   = ~(M68K_ADDR[23:16] == 8'h00) | nAS;

// ---------------- pacing logic, verbatim from neogeo.sv
`include "pacing_block.vh"

// ---------------- LSPC with its VRAMs (1-clock latency like spram)
wire [15:0] M68K_DATA;
wire [14:0] SVRAM_ADDR;
wire [15:0] SVRAM_DATA_OUT;
reg  [15:0] SVRAM_Q;
wire [10:0] FVRAM_ADDR;
wire [15:0] FVRAM_DATA_OUT;
reg  [15:0] FVRAM_Q;
wire        BWE, CWE, BOE;
wire        LSPC_BUSY_RAW, LSPC_WR_BUSY_RAW;
`ifdef NOPACE
assign LSPC_VRAM_BUSY = 1'b0;
assign LSPC_VRAM_WR_BUSY = 1'b0;
`else
assign LSPC_VRAM_BUSY = LSPC_BUSY_RAW;
`ifdef OLDPACE
assign LSPC_VRAM_WR_BUSY = LSPC_BUSY_RAW;
`else
assign LSPC_VRAM_WR_BUSY = LSPC_WR_BUSY_RAW;
`endif
`endif

reg [15:0] svram[0:32767];
reg [15:0] fvram[0:2047];
always @(posedge CLK_48M) begin
    if (~BWE) svram[SVRAM_ADDR] <= SVRAM_DATA_OUT;
    SVRAM_Q <= svram[SVRAM_ADDR];
    if (~CWE) fvram[FVRAM_ADDR] <= FVRAM_DATA_OUT;
    FVRAM_Q <= fvram[FVRAM_ADDR];
end

wire nRESETP;
wire [23:16] PBUS_IO;

lspc2_a2_sync LSPC(
    .CLK(CLK_48M), .CLK_EN_24M_P(CLK_EN_24M_P), .CLK_EN_24M_N(CLK_EN_24M_N),
    .RESET(nRESET), .nRESETP(nRESETP),
    .PBUS_OUT(), .PBUS_IO(PBUS_IO),
    .M68K_ADDR(M68K_ADDR[3:1]), .M68K_DATA(M68K_DATA),
    .LSPOE(nLSPOE | lspc_hold), .LSPWE(nLSPWE | lspc_hold),
    .DOTA(1'b0), .DOTB(1'b0),
    .CA4(), .S2H1(), .S1H1(), .LOAD(), .H(), .EVEN1(), .EVEN2(),
    .IPL0(), .IPL1(), .CD_VBLANK_IRQ_EN(1'b1), .CD_TIMER_IRQ_EN(1'b1),
    .CHG(), .LD1(), .LD2(), .PCK1(), .PCK2(),
    .PCK1_EN_P(), .PCK2_EN_P(), .PCK1_EN_N(), .PCK2_EN_N(),
    .WE(), .CK(), .SS1(), .SS2(),
    .HSYNC(), .VSYNC(), .CHBL(), .BNKB(), .VCS(),
    .LSPC_8M(), .LSPC_4M(), .LSPC_EN_4M_P(), .LSPC_EN_4M_N(),
    .SVRAM_ADDR(SVRAM_ADDR), .SVRAM_DATA_IN({16'd0,SVRAM_Q}), .SVRAM_DATA_OUT(SVRAM_DATA_OUT),
    .BOE(BOE), .BWE(BWE),
    .FVRAM_ADDR(FVRAM_ADDR), .FVRAM_DATA_IN(FVRAM_Q), .FVRAM_DATA_OUT(FVRAM_DATA_OUT),
    .CWE(CWE), .nPBUS_OUT_EN(), .VMODE(1'b0),
    .FIXMAP_ADDR(), .SPRMAP_ADDR(), .VRAM_ADDR(), .VRAM_CYCLE(), .SVRAM_WR(), .LO_ROM_ADDR(),
    .CPU_VRAM_BUSY(LSPC_BUSY_RAW), .CPU_VRAM_WR_BUSY(LSPC_WR_BUSY_RAW)
);

// ---------------- work RAM / program
reg  [15:0] mem[0:32767];
reg  [15:0] ram_q;
always @(posedge CLK_48M) begin
    ram_q <= mem[M68K_ADDR[15:1]];
    if (!nRAM && !M68K_RW) begin
        if (!nUDS) mem[M68K_ADDR[15:1]][15:8] <= FX68K_DATAOUT[15:8];
        if (!nLDS) mem[M68K_ADDR[15:1]][ 7:0] <= FX68K_DATAOUT[ 7:0];
    end
end

// CPU data in / out: the LSPC drives M68K_DATA on reads
assign M68K_DATA    = (!M68K_RW && !nLSPC_ZONE) ? FX68K_DATAOUT : 16'hzzzz;
assign FX68K_DATAIN = !nLSPC_ZONE ? M68K_DATA : ram_q;

// DTACK: immediate for RAM and LSPC (as NEO-C1), plus the pacing hold
wire   nDTACK = nAS;
assign nDTACK_ADJ = nDTACK | lspc_dtack_wait;

// ---------------- program
localparam N = 64;
task load_program;
    integer i;
    begin
        for (i=0; i<32768; i=i+1) mem[i] = 16'h4E71;
        mem[0]=16'h0000; mem[1]=16'h3000; mem[2]=16'h0000; mem[3]=16'h0100;
        i = 16'h100>>1;
        mem[i]=16'h41F9; mem[i+1]=16'h003C; mem[i+2]=16'h0000; i=i+3;   // LEA $3C0000,A0
        mem[i]=16'h317C; mem[i+1]=16'h0001; mem[i+2]=16'h0004; i=i+3;   // MOVE.W #1,4(A0)     VRAMMOD=1
        mem[i]=16'h30BC; mem[i+1]=16'h7000; i=i+2;                      // MOVE.W #$7000,(A0)  VRAMADDR
        mem[i]=16'h303C; mem[i+1]=16'h1234; i=i+2;                      // MOVE.W #$1234,D0
        mem[i]=16'h7600 | (N-1); i=i+1;                                 // MOVEQ #N-1,D3
        mem[i]=16'h3140; mem[i+1]=16'h0002; i=i+2;                      // loop1: MOVE.W D0,2(A0)
        mem[i]=16'h5240; i=i+1;                                         // ADDQ.W #1,D0
        mem[i]=16'h51CB; mem[i+1]=16'hFFF8; i=i+2;                      // DBRA D3,loop1
        mem[i]=16'h323C; mem[i+1]=16'h7000; i=i+2;                      // MOVE.W #$7000,D1
        mem[i]=16'h43F9; mem[i+1]=16'h0000; mem[i+2]=16'h1000; i=i+3;   // LEA $1000,A1
        mem[i]=16'h7600 | (N-1); i=i+1;                                 // MOVEQ #N-1,D3
        mem[i]=16'h3081; i=i+1;                                         // loop2: MOVE.W D1,(A0)
        mem[i]=16'h32E8; mem[i+1]=16'h0002; i=i+2;                      // MOVE.W 2(A0),(A1)+
        mem[i]=16'h5241; i=i+1;                                         // ADDQ.W #1,D1
        mem[i]=16'h51CB; mem[i+1]=16'hFFF6; i=i+2;                      // DBRA D3,loop2
        mem[i]=16'h33FC; mem[i+1]=16'hABCD; mem[i+2]=16'h0000; mem[i+3]=16'h2004; i=i+4; // MOVE.W #$ABCD,$2004
        mem[i]=16'h60FE;                                                // BRA.S *
        mem[16'h2004>>1] = 0;
    end
endtask

integer errors_run, total_errors=0, s, k, n, holds, ofs, maxh, bad_runs;
always @(posedge CLK_48M) if (lspc_hold && !lspc_waited) holds = holds + 1;

initial begin
    for (s=0; s<3; s=s+1) begin
      maxh=0; bad_runs=0;
      for (ofs=0; ofs<48; ofs=ofs+1) begin
        nRESET = 0; speed_sel = s;
        repeat(400) @(posedge CLK_48M);
        load_program;
        for (k=0; k<32768; k=k+1) svram[k] = 16'hDEAD;
        repeat(20+ofs*7) @(posedge CLK_48M);   // vary the CPU/LSPC phase
        nRESET = 1; holds = 0;
        n = 0;
        while (mem[16'h2004>>1] != 16'hABCD && n < 3000000) begin @(posedge CLK_48M); n = n + 1; end
        errors_run = 0;
        for (k=0; k<N; k=k+1) begin
            if (svram[16'h7000+k] !== 16'h1234+k) errors_run = errors_run + 1;       // VRAM contents
            if (mem[(16'h1000>>1)+k] !== 16'h1234+k) errors_run = errors_run + 1;    // CPU read-back
        end
        if (n >= 3000000) errors_run = errors_run + 1000;
        if (errors_run) bad_runs = bad_runs + 1;
        if (ofs==0 || errors_run) $display("%2dMHz ofs %2d: %s, %0d us, %0d held accesses, %0d wrong words (VRAM + read-back)",
            s==0 ? 12 : s==1 ? 18 : 24, ofs, n<3000000 ? "finished" : "TIMEOUT", (n*21)/1000, holds, errors_run);
        if (errors_run) begin
            $display("   VRAM[7000..7007]: %h %h %h %h %h %h %h %h", svram[16'h7000], svram[16'h7001],
                svram[16'h7002], svram[16'h7003], svram[16'h7004], svram[16'h7005], svram[16'h7006], svram[16'h7007]);
            $display("   read-back       : %h %h %h %h %h %h %h %h", mem[16'h800], mem[16'h801],
                mem[16'h802], mem[16'h803], mem[16'h804], mem[16'h805], mem[16'h806], mem[16'h807]);
        end
        total_errors = total_errors + errors_run;
      end
      $display("%2dMHz: %0d of 48 CPU/LSPC phase offsets wrong", s==0 ? 12 : s==1 ? 18 : 24, bad_runs);
    end
    if (total_errors==0) $display("ALL SPEEDS CORRECT"); else $display("ERRORS: %0d", total_errors);
    $finish;
end

endmodule
