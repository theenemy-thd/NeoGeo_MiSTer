// Behavioural models of rtl/mem/dpram.v modules (altsyncram, unregistered
// output, address registered, new data on same-port read-during-write).
module dpram #(parameter ADDRWIDTH=8, DATAWIDTH=8, NUMWORDS=1<<ADDRWIDTH, MEM_INIT_FILE="")
(
	input clock_a, input [ADDRWIDTH-1:0] address_a, input [DATAWIDTH-1:0] data_a, input wren_a, output reg [DATAWIDTH-1:0] q_a,
	input clock_b, input [ADDRWIDTH-1:0] address_b, input [DATAWIDTH-1:0] data_b, input wren_b, output reg [DATAWIDTH-1:0] q_b
);
reg [DATAWIDTH-1:0] mem[0:NUMWORDS-1];
always @(posedge clock_a) begin
	if (wren_a) begin mem[address_a] <= data_a; q_a <= data_a; end
	else q_a <= mem[address_a];
end
always @(posedge clock_b) begin
	if (wren_b) begin mem[address_b] <= data_b; q_b <= data_b; end
	else q_b <= mem[address_b];
end
endmodule

module spram #(parameter ADDRWIDTH=8, DATAWIDTH=8, NUMWORDS=1<<ADDRWIDTH)
(
	input clock, input [ADDRWIDTH-1:0] address, input [DATAWIDTH-1:0] data, input wren, output reg [DATAWIDTH-1:0] q
);
reg [DATAWIDTH-1:0] mem[0:NUMWORDS-1];
always @(posedge clock) begin
	if (wren) begin mem[address] <= data; q <= data; end
	else q <= mem[address];
end
endmodule
