// Sound sync: fx68k sends $03 to REG_SOUND, runs a 12MHz-timed delay loop,
// polls REG_SOUND, then runs plain code. Measures each part at 12/18/24MHz.
// snd_sync.vh is copied from neogeo.sv.
`timescale 1ns/1ps
module tb;
reg CLK_48M=0; always #10.4167 CLK_48M=~CLK_48M;
reg CLK_EN_24M_N=0, CLK_EN_24M_P=0, CLK_68KCLK=0;
always @(posedge CLK_48M) begin CLK_EN_24M_N<=~CLK_EN_24M_N; CLK_EN_24M_P<=CLK_EN_24M_N; end
always @(posedge CLK_48M) if (CLK_EN_24M_P) CLK_68KCLK<=~CLK_68KCLK;
wire CLK_EN_68K_P = ~CLK_68KCLK & CLK_EN_24M_P;
wire CLK_EN_68K_N =  CLK_68KCLK & CLK_EN_24M_P;
reg [1:0] speed_sel=0; reg nRESET=0;
wire CPU_EN_P, CPU_EN_N, CPU_OVERCLOCK, CPU_SLOW;
cpu_speed CPU_SPEED(.CLK(CLK_48M),.nRESET(nRESET),.SPEED(speed_sel),.SLOW(CPU_SLOW),.CLK_EN_68K_P(CLK_EN_68K_P),
  .CLK_EN_68K_N(CLK_EN_68K_N),.CPU_EN_P(CPU_EN_P),.CPU_EN_N(CPU_EN_N),.OVERCLOCK(CPU_OVERCLOCK));
reg reset=1; always @(posedge CLK_48M) if (CPU_EN_N) reset<=~nRESET;
wire M68K_RW, nAS, nUDS, nLDS; wire [23:1] M68K_ADDR; wire [15:0] FX68K_DATAOUT; wire [15:0] DIN;
fx68k cpu(.clk(CLK_48M),.extReset(reset),.pwrUp(reset),.enPhi1(CPU_EN_P),.enPhi2(CPU_EN_N),
  .eRWn(M68K_RW),.ASn(nAS),.UDSn(nUDS),.LDSn(nLDS),.BGn(),.BRn(1'b1),.BGACKn(1'b1),.HALTn(1'b1),
  .DTACKn(nAS),.VPAn(1'b1),.BERRn(1'b1),.IPL0n(1'b1),.IPL1n(1'b1),.IPL2n(1'b1),
  .FC0(),.FC1(),.FC2(),.iEdb(DIN),.oEdb(FX68K_DATAOUT),.eab(M68K_ADDR),.E(),.VMAn(),.oRESETn(),.oHALTEDn());
wire SYSTEM_CDx = 1'b1;
wire cd_reg_acc = SYSTEM_CDx & ~nAS & (M68K_ADDR[23:12] == 12'hFF0);
`include "snd_sync.vh"
reg [15:0] mem[0:32767]; reg [15:0] ram_q;
wire nRAM = ~(M68K_ADDR[23:16]==8'h00) | nAS;
always @(posedge CLK_48M) begin
  ram_q<=mem[M68K_ADDR[15:1]];
  if (!nRAM && !M68K_RW) begin if(!nUDS) mem[M68K_ADDR[15:1]][15:8]<=FX68K_DATAOUT[15:8]; if(!nLDS) mem[M68K_ADDR[15:1]][7:0]<=FX68K_DATAOUT[7:0]; end
end
assign DIN = (M68K_ADDR[23:16]==8'h00) ? ram_q : 16'h0000;   // REG_SOUND reads 0 (no reply)
task load_program; integer i; begin
  for (i=0;i<32768;i=i+1) mem[i]=16'h4E71;
  mem[0]=0; mem[1]=16'h3000; mem[2]=0; mem[3]=16'h0100; i=16'h100>>1;
  mem[i]=16'h203C; mem[i+1]=16'h0000; mem[i+2]=16'h4E20; i=i+3; mem[i]=16'h5380; i=i+1; mem[i]=16'h66FC; i=i+1;
  mem[i]=16'h33FC; mem[i+1]=16'h0001; mem[i+2]=16'h0000; mem[i+3]=16'h2000; i=i+4;
  mem[i]=16'h323C; mem[i+1]=16'd5000; i=i+2; mem[i]=16'h1439; mem[i+1]=16'h0032; mem[i+2]=16'h0000; i=i+3; mem[i]=16'h51C9; mem[i+1]=16'hFFF8; i=i+2;
  mem[i]=16'h33FC; mem[i+1]=16'h0002; mem[i+2]=16'h0000; mem[i+3]=16'h2000; i=i+4;
  mem[i]=16'h13FC; mem[i+1]=16'h0003; mem[i+2]=16'h0032; mem[i+3]=16'h0000; i=i+4;
  mem[i]=16'h203C; mem[i+1]=16'h0000; mem[i+2]=16'h4E20; i=i+3; mem[i]=16'h5380; i=i+1; mem[i]=16'h66FC; i=i+1;
  mem[i]=16'h33FC; mem[i+1]=16'h0003; mem[i+2]=16'h0000; mem[i+3]=16'h2000; i=i+4;
  mem[i]=16'h203C; mem[i+1]=16'h0009; mem[i+2]=16'h27C0; i=i+3; mem[i]=16'h5380; i=i+1; mem[i]=16'h66FC; i=i+1;
  mem[i]=16'h33FC; mem[i+1]=16'h0004; mem[i+2]=16'h0000; mem[i+3]=16'h2000; i=i+4;
  mem[i]=16'h203C; mem[i+1]=16'h0000; mem[i+2]=16'h4E20; i=i+3; mem[i]=16'h5380; i=i+1; mem[i]=16'h66FC; i=i+1;
  mem[i]=16'h33FC; mem[i+1]=16'h0005; mem[i+2]=16'h0000; mem[i+3]=16'h2000; i=i+4;
  mem[i]=16'h13FC; mem[i+1]=16'h0001; mem[i+2]=16'h00FF; mem[i+3]=16'h0165; i=i+4;
  mem[i]=16'h203C; mem[i+1]=16'h0000; mem[i+2]=16'h01F4; i=i+3; mem[i]=16'h5380; i=i+1; mem[i]=16'h66FC; i=i+1;
  mem[i]=16'h33FC; mem[i+1]=16'h0006; mem[i+2]=16'h0000; mem[i+3]=16'h2000; i=i+4;
  mem[i]=16'h203C; mem[i+1]=16'h0000; mem[i+2]=16'h4E20; i=i+3; mem[i]=16'h5380; i=i+1; mem[i]=16'h66FC; i=i+1;
  mem[i]=16'h33FC; mem[i+1]=16'h0007; mem[i+2]=16'h0000; mem[i+3]=16'h2000; i=i+4;
  mem[i]=16'h60FE; mem[16'h2000>>1]=0;
end endtask
integer s, n, m, t[0:7], tt[0:2][0:7];
initial begin
  for (s=0;s<3;s=s+1) begin
    nRESET=0; speed_sel=s; repeat(300) @(posedge CLK_48M); load_program;
    repeat(20) @(posedge CLK_48M); nRESET=1; n=0; m=0; t[0]=0;
    while (m<7 && n<80000000) begin @(posedge CLK_48M); n=n+1; if (mem[16'h2000>>1]!=m) begin m=mem[16'h2000>>1]; t[m]=n; end end
    for (m=1;m<=7;m=m+1) tt[s][m]=t[m]-t[m-1];
  end
  $display("part                          12MHz      18MHz      24MHz   (ms)");
  $display("plain loop                     %7.2f   %7.2f   %7.2f", tt[0][1]/48000.0, tt[1][1]/48000.0, tt[2][1]/48000.0);
  $display("REG_SOUND poll loop            %7.2f   %7.2f   %7.2f", tt[0][2]/48000.0, tt[1][2]/48000.0, tt[2][2]/48000.0);
  $display("$03 + delay loop (12MHz-timed) %7.2f   %7.2f   %7.2f", tt[0][3]/48000.0, tt[1][3]/48000.0, tt[2][3]/48000.0);
  $display("long loop, crosses 250ms end   %7.2f   %7.2f   %7.2f", tt[0][4]/48000.0, tt[1][4]/48000.0, tt[2][4]/48000.0);
  $display("plain loop after the window    %7.2f   %7.2f   %7.2f", tt[0][5]/48000.0, tt[1][5]/48000.0, tt[2][5]/48000.0);
  $display("CD register write + short loop  %7.2f   %7.2f   %7.2f", tt[0][6]/48000.0, tt[1][6]/48000.0, tt[2][6]/48000.0);
  $display("plain loop after the CD window %7.2f   %7.2f   %7.2f", tt[0][7]/48000.0, tt[1][7]/48000.0, tt[2][7]/48000.0);
  $finish;
end
endmodule
