// Behavioural model of rtl/mem/sdram.sv (same FSM and ready/dout timing),
// with the SDRAM chip replaced by a word array. Reads: burst of 4, CAS 2:
// dout gets word 0 on the same clock ready goes high, then words 1-3.
module sdram_beh #(parameter AW = 21) (
	input             clk,
	input      [26:1] addr,
	output reg [15:0] dout,
	input      [15:0] din,
	input             wr,
	input       [1:0] bs,
	input             rd,
	output reg        ready = 1,
	input             refresh
);
reg [15:0] mem[0:(1<<AW)-1];

localparam ST_IDLE = 0, ST_WAIT = 1, ST_RW = 2, ST_I4 = 3, ST_I3 = 4, ST_I2 = 5, ST_I1 = 6, ST_RFSH = 7, ST_I5 = 8;
reg [3:0]  state = ST_IDLE;
reg [2:0]  data_ready_delay = 0;
reg        refresh_old = 0;
reg [26:1] a;
reg        saved_wr;
reg [15:0] saved_data;
reg [1:0]  saved_bs;
reg        bact = 0;
reg [1:0]  bdly, bword;
reg [26:1] bbase;
integer    nrefresh = 0, nread = 0;

always @(posedge clk) begin
	data_ready_delay <= data_ready_delay >> 1;
	if (data_ready_delay[0]) ready <= 1;

	if (bact) begin
		if (bdly > 1) bdly <= bdly - 1'd1;
		else begin
			dout <= mem[{bbase[AW:3], bbase[2:1] + bword}];
			bword <= bword + 1'd1;
			if (bword == 3) bact <= 0;
		end
	end

	case (state)
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
				nrefresh = nrefresh + 1;
			end
			else if (rd | wr) begin
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
			else begin
				data_ready_delay[2] <= 1;
				bact <= 1; bdly <= 3; bword <= 0; bbase <= a;
				nread = nread + 1;
			end
		end
		default: state <= ST_IDLE;
	endcase
end
endmodule
