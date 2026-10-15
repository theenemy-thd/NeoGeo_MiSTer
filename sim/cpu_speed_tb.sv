// fx68k + cpu_speed: runs a 68000 program at 12, 18 and 24MHz and checks the
// results match. Memory has a 1-clock read latency like the core's BRAMs.
// +WAITS adds random DTACK delays like the SDRAM ROM path.
`timescale 1ns/1ps

module tb;

reg clk=0;
always #10.4167 clk = ~clk;   // 48MHz

// original 12MHz enables (neogeo.sv + clocks.v)
reg CLK_EN_24M_N=0, CLK_EN_24M_P=0, CLK_68KCLK=0;
always @(posedge clk) begin
    CLK_EN_24M_N <= ~CLK_EN_24M_N;
    CLK_EN_24M_P <= CLK_EN_24M_N;
end
always @(posedge clk) if (CLK_EN_24M_P) CLK_68KCLK <= ~CLK_68KCLK;
wire CLK_EN_68K_P = ~CLK_68KCLK & CLK_EN_24M_P;
wire CLK_EN_68K_N =  CLK_68KCLK & CLK_EN_24M_P;

reg  [1:0] speed_sel = 0;
// +SLOWTOG: toggle SLOW at random times (as the sound sync does)
reg slow = 0, slowtog = 0; integer sseed = 7;
always @(posedge clk) if (slowtog && ($urandom % 97) == 0) slow <= ~slow;
reg        nRESET = 0;
wire       en_p, en_n;

cpu_speed uut(
    .CLK(clk), .nRESET(nRESET), .SPEED(speed_sel), .SLOW(slow),
    .CLK_EN_68K_P(CLK_EN_68K_P), .CLK_EN_68K_N(CLK_EN_68K_N),
    .CPU_EN_P(en_p), .CPU_EN_N(en_n)
);

// the CPU, as in cpu_68k.v
reg reset=1;
always @(posedge clk) if (en_n) reset <= ~nRESET;

wire        RW, ASn, UDSn, LDSn, BGn, FC0, FC1, FC2;
wire [23:1] A;
wire [15:0] dout;
reg  [15:0] din;
reg         dtack_n = 1;

fx68k cpu(
    .clk(clk), .extReset(reset), .pwrUp(reset),
    .enPhi1(en_p), .enPhi2(en_n),
    .eRWn(RW), .ASn(ASn), .UDSn(UDSn), .LDSn(LDSn),
    .BGn(BGn), .BRn(1'b1), .BGACKn(1'b1), .HALTn(1'b1),
    .DTACKn(dtack_n), .VPAn(1'b1), .BERRn(1'b1),
    .IPL0n(1'b1), .IPL1n(1'b1), .IPL2n(1'b1),
    .FC0(FC0), .FC1(FC1), .FC2(FC2),
    .iEdb(din), .oEdb(dout), .eab(A),
    .E(), .VMAn(), .oRESETn(), .oHALTEDn()
);

// memory: 32k words, registered read
reg [15:0] mem[0:32767];
integer    seed = 3, wait_cnt = 0;
reg        waits = 0;
always @(posedge clk) begin
    din <= mem[A[15:1]];
    if (!ASn && !RW) begin
        if (!UDSn) mem[A[15:1]][15:8] <= dout[15:8];
        if (!LDSn) mem[A[15:1]][ 7:0] <= dout[ 7:0];
    end
    // DTACK: at once, or after a random delay (SDRAM-like) when +WAITS
    if (ASn) begin
        dtack_n  <= 1;
        wait_cnt <= waits ? ($urandom(seed) % 24) : 0;
    end else if (wait_cnt != 0) wait_cnt <= wait_cnt - 1;
    else dtack_n <= 0;
end

// program (hand assembled)
task load_program;
    integer i;
    begin
        for (i=0; i<32768; i=i+1) mem[i] = 16'h4E71; // NOP
        mem[0] = 16'h0000; mem[1] = 16'h3000;         // SSP = $3000
        mem[2] = 16'h0000; mem[3] = 16'h0100;         // PC  = $100
        i = 16'h100 >> 1;
        mem[i] = 16'h41F9; mem[i+1] = 16'h0000; mem[i+2] = 16'h1000; i=i+3; // LEA $1000,A0
        mem[i] = 16'h761F; i=i+1;                     // MOVEQ #31,D3
        mem[i] = 16'h7001; i=i+1;                     // MOVEQ #1,D0
        mem[i] = 16'h7203; i=i+1;                     // MOVEQ #3,D1
        // loop @ $10C
        mem[i] = 16'hD081; i=i+1;                     // ADD.L  D1,D0
        mem[i] = 16'h2400; i=i+1;                     // MOVE.L D0,D2
        mem[i] = 16'hC4C1; i=i+1;                     // MULU.W D1,D2
        mem[i] = 16'h5241; i=i+1;                     // ADDQ.W #1,D1
        mem[i] = 16'h84C1; i=i+1;                     // DIVU.W D1,D2
        mem[i] = 16'h20C2; i=i+1;                     // MOVE.L D2,(A0)+
        mem[i] = 16'hE388; i=i+1;                     // LSL.L  #1,D0
        mem[i] = 16'h51CB; mem[i+1] = 16'hFFF0; i=i+2; // DBRA D3,loop
        mem[i] = 16'h23C0; mem[i+1] = 16'h0000; mem[i+2] = 16'h2000; i=i+3; // MOVE.L D0,$2000
        mem[i] = 16'h33FC; mem[i+1] = 16'hABCD; mem[i+2] = 16'h0000; mem[i+3] = 16'h2004; i=i+4; // MOVE.W #$ABCD,$2004
        mem[i] = 16'h60FE;                            // BRA.S *
        mem[16'h2004>>1] = 0;
    end
endtask

reg  [15:0] result[0:66];
reg  [15:0] ref_res[0:66];
integer     cycles[0:2];
integer     errors = 0;

task run( input [1:0] sp, output integer ncyc );
    integer n, j;
    begin
        nRESET = 0;                 // stop the CPU before touching memory
        speed_sel = sp;
        repeat(200) @(posedge clk);
        load_program;
        repeat(20) @(posedge clk);
        nRESET = 1;
        n = 0;
        while (mem[16'h2004>>1] != 16'hABCD && n < 2000000) begin
            @(posedge clk); n = n + 1;
        end
        ncyc = n;
        for (j=0; j<64; j=j+1) result[j] = mem[(16'h1000>>1)+j];
        result[64] = mem[16'h2000>>1]; result[65] = mem[16'h2002>>1];
        result[66] = (n < 2000000);
    end
endtask

integer s, j, w;
reg [8*6-1:0] name;
initial begin
    slowtog = $test$plusargs("SLOWTOG");
    for (w=0; w<2; w=w+1) begin
        waits = w;
        for (s=0; s<3; s=s+1) begin
            run(s[1:0], cycles[s]);
            if (s==0) for (j=0; j<67; j=j+1) ref_res[j] = result[j];
            else for (j=0; j<67; j=j+1) if (result[j] !== ref_res[j]) begin
                if (errors < 5) $display("MISMATCH speed %0d word %0d: %04X vs %04X", s, j, result[j], ref_res[j]);
                errors = errors + 1;
            end
            $display("%s %2dMHz: %s in %0d clocks (%.2f us)", w ? "waits   " : "no waits",
                s==0 ? 12 : s==1 ? 18 : 24, result[66] ? "finished" : "TIMEOUT",
                cycles[s], cycles[s]*20.8333/1000.0);
            if (!result[66]) errors = errors + 1;
        end
        $display("  speedup 18MHz: %.2fx  24MHz: %.2fx", cycles[0]*1.0/cycles[1], cycles[0]*1.0/cycles[2]);
    end
    $display("result D0 at end = %04X%04X", ref_res[64], ref_res[65]);
    if (errors==0) $display("ALL SPEEDS GIVE THE SAME RESULTS"); else $display("%0d ERRORS", errors);
    $finish;
end

endmodule
