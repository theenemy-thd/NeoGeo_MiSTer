// fx68k writing/reading CD registers back to back at 12/18/24MHz. The CD side
// is modelled as cd.sv/lc8951.v do it: strobe edges sampled at the stock
// 12MHz 68K enable. cd_pacing.vh is copied from neogeo.sv.
`timescale 1ns/1ps
module tb;
reg CLK_48M=0; always #10.4167 CLK_48M=~CLK_48M;
reg CLK_EN_24M_N=0, CLK_EN_24M_P=0, CLK_68KCLK=0;
always @(posedge CLK_48M) begin CLK_EN_24M_N<=~CLK_EN_24M_N; CLK_EN_24M_P<=CLK_EN_24M_N; end
always @(posedge CLK_48M) if (CLK_EN_24M_P) CLK_68KCLK<=~CLK_68KCLK;
wire CLK_EN_68K_P = ~CLK_68KCLK & CLK_EN_24M_P;
wire CLK_EN_68K_N =  CLK_68KCLK & CLK_EN_24M_P;
reg [1:0] speed_sel=0; reg nRESET=0; reg SYSTEM_CDx=1;
wire CPU_EN_P, CPU_EN_N, CPU_OVERCLOCK;
cpu_speed CPU_SPEED(.CLK(CLK_48M),.nRESET(nRESET),.SPEED(speed_sel), .SLOW(1'b0),.CLK_EN_68K_P(CLK_EN_68K_P),
  .CLK_EN_68K_N(CLK_EN_68K_N),.CPU_EN_P(CPU_EN_P),.CPU_EN_N(CPU_EN_N),.OVERCLOCK(CPU_OVERCLOCK));
reg reset=1; always @(posedge CLK_48M) if (CPU_EN_N) reset<=~nRESET;
wire M68K_RW, nAS, nUDS, nLDS; wire [23:1] M68K_ADDR; wire [15:0] DOUT; wire [15:0] DIN;
wire nDTACK_ADJ;
fx68k cpu(.clk(CLK_48M),.extReset(reset),.pwrUp(reset),.enPhi1(CPU_EN_P),.enPhi2(CPU_EN_N),
  .eRWn(M68K_RW),.ASn(nAS),.UDSn(nUDS),.LDSn(nLDS),.BGn(),.BRn(1'b1),.BGACKn(1'b1),.HALTn(1'b1),
  .DTACKn(nDTACK_ADJ),.VPAn(1'b1),.BERRn(1'b1),.IPL0n(1'b1),.IPL1n(1'b1),.IPL2n(1'b1),
  .FC0(),.FC1(),.FC2(),.iEdb(DIN),.oEdb(DOUT),.eab(M68K_ADDR),.E(),.VMAn(),.oRESETn(),.oHALTEDn());
`include "cd_pacing.vh"
`ifdef NOPACE
assign nDTACK_ADJ = nAS;
`else
assign nDTACK_ADJ = nAS | cd_dtack_wait;
`endif
// CD register model (cd.sv style): writes to FF0002 logged, reads of FF0006
// return a counter that advances on each read edge (like the LC8951 register pointer)
reg nLDS_PREV=1, nUDS_PREV=1, nAS_PREV=1;
reg [15:0] wlog[0:255]; integer wn=0; reg [15:0] rd_cnt=0;
wire READING = ~cd_nAS & M68K_RW & (M68K_ADDR[23:12]==12'hFF0);
always @(posedge CLK_48M) if (CLK_EN_68K_P) begin
  nLDS_PREV<=cd_nLDS; nUDS_PREV<=cd_nUDS; nAS_PREV<=cd_nAS;
  if ((nLDS_PREV & ~cd_nLDS) | (nUDS_PREV & ~cd_nUDS))
    if (M68K_ADDR[23:12]==12'hFF0 && !M68K_RW && M68K_ADDR[11:1]==11'h001) begin wlog[wn[7:0]]<=DOUT; wn<=wn+1; end
  if (nAS_PREV & ~cd_nAS & READING && M68K_ADDR[11:1]==11'h003) rd_cnt<=rd_cnt+1;
end
reg [15:0] mem[0:32767]; reg [15:0] ram_q;
wire nRAM = ~(M68K_ADDR[23:16]==8'h00) | nAS;
always @(posedge CLK_48M) begin
  ram_q<=mem[M68K_ADDR[15:1]];
  if (!nRAM && !M68K_RW) begin if(!nUDS) mem[M68K_ADDR[15:1]][15:8]<=DOUT[15:8]; if(!nLDS) mem[M68K_ADDR[15:1]][7:0]<=DOUT[7:0]; end
end
assign DIN = (M68K_ADDR[23:12]==12'hFF0) ? rd_cnt : ram_q;
localparam N=40;
task load_program; integer i; begin
  for (i=0;i<32768;i=i+1) mem[i]=16'h4E71;
  mem[0]=0; mem[1]=16'h3000; mem[2]=0; mem[3]=16'h0100; i=16'h100>>1;
  mem[i]=16'h41F9; mem[i+1]=16'h00FF; mem[i+2]=16'h0000; i=i+3;  // LEA $FF0000,A0
  mem[i]=16'h43F9; mem[i+1]=16'h0000; mem[i+2]=16'h1000; i=i+3;  // LEA $1000,A1
  mem[i]=16'h7000; i=i+1;                                        // MOVEQ #0,D0
  mem[i]=16'h7600|(N-1); i=i+1;                                  // MOVEQ #N-1,D3
  mem[i]=16'h3140; mem[i+1]=16'h0002; i=i+2;                     // loop: MOVE.W D0,2(A0)
  mem[i]=16'h5240; i=i+1;                                        // ADDQ.W #1,D0
  mem[i]=16'h3140; mem[i+1]=16'h0002; i=i+2;                     // MOVE.W D0,2(A0)  (back to back)
  mem[i]=16'h5240; i=i+1;                                        // ADDQ.W #1,D0
  mem[i]=16'h32E8; mem[i+1]=16'h0006; i=i+2;                     // MOVE.W 6(A0),(A1)+
  mem[i]=16'h51CB; mem[i+1]=16'hFFEE; i=i+2;                     // DBRA D3,loop
  mem[i]=16'h33FC; mem[i+1]=16'hABCD; mem[i+2]=16'h0000; mem[i+3]=16'h2004; i=i+4;
  mem[i]=16'h60FE; mem[16'h2004>>1]=0;
end endtask
integer s,k,n,err,tot=0,ofs,bad;
initial begin
  for (s=0;s<3;s=s+1) begin bad=0;
    for (ofs=0;ofs<32;ofs=ofs+1) begin
      nRESET=0; speed_sel=s; repeat(300) @(posedge CLK_48M); load_program; wn=0; rd_cnt=0;
      repeat(20+ofs*5) @(posedge CLK_48M); nRESET=1; n=0;
      while (mem[16'h2004>>1]!=16'hABCD && n<2000000) begin @(posedge CLK_48M); n=n+1; end
      err=0;
      if (wn!=2*N) err=err+1;
      for (k=0;k<2*N;k=k+1) if (wlog[k]!==k) err=err+1;
      for (k=0;k<N;k=k+1) if (mem[(16'h1000>>1)+k]!==k+1) err=err+1;   // each read seen once, returns count before it
      if (err) bad=bad+1;
      if (ofs==0) $display("w: %h %h %h %h %h %h  r: %h %h %h %h", wlog[0],wlog[1],wlog[2],wlog[3],wlog[4],wlog[5], mem[16'h800],mem[16'h801],mem[16'h802],mem[16'h803]);
      if (ofs==0) $display("%2dMHz: %0d us, %0d writes seen (expected %0d), %0d errors", s==0?12:s==1?18:24, (n*21)/1000, wn, 2*N, err);
      tot=tot+err;
    end
    $display("%2dMHz: %0d of 32 phase offsets wrong", s==0?12:s==1?18:24, bad);
  end
  if (tot==0) $display("ALL SPEEDS CORRECT"); else $display("ERRORS %0d", tot);
  $finish;
end
endmodule
