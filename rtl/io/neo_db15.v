// DB15 splitter (Antonio Villena design) reader for the MiSTer user port.
// Same bit order and timing as joydb15.v by Aitor Pelaez (NeuroRulez), as used
// by jtframe, but clocked from clk_sys with a clock enable instead of using a
// counter bit as a clock. joy_clk = clk/16 (3 MHz at 48 MHz).
// Outputs are active high: {Select,Start,F,E,D,C,B,A,Up,Down,Left,Right}.
module neo_db15
(
	input             clk,
	output            joy_clk,
	output            joy_load,
	input             joy_data,
	output     [11:0] joystick1,
	output     [11:0] joystick2
);

reg  [3:0] div = 4'd0;
always @(posedge clk) div <= div + 4'd1;
assign joy_clk = div[3];
wire tick = (div == 4'd7);	// joy_clk rises on the next clk

reg [11:0] joy1 = 12'hFFF, joy2 = 12'hFFF;
reg  [4:0] cnt  = 5'd0;
reg        load = 1'b1;
assign joy_load = load;

always @(posedge clk) if (tick) begin
	load <= (cnt != 5'd0);
	cnt  <= (cnt == 5'd25) ? 5'd0 : cnt + 5'd1;
	case (cnt)
		5'd2 : joy1[7]  <= joy_data;	// P1 D
		5'd3 : joy1[6]  <= joy_data;	// P1 C
		5'd4 : joy1[5]  <= joy_data;	// P1 B
		5'd5 : joy1[4]  <= joy_data;	// P1 A
		5'd6 : joy1[0]  <= joy_data;	// P1 Right
		5'd7 : joy1[1]  <= joy_data;	// P1 Left
		5'd8 : joy1[2]  <= joy_data;	// P1 Down
		5'd9 : joy1[3]  <= joy_data;	// P1 Up
		5'd10: joy2[0]  <= joy_data;	// P2 Right
		5'd11: joy2[1]  <= joy_data;	// P2 Left
		5'd12: joy2[2]  <= joy_data;	// P2 Down
		5'd13: joy2[3]  <= joy_data;	// P2 Up
		5'd14: joy1[9]  <= joy_data;	// P1 F
		5'd15: joy1[8]  <= joy_data;	// P1 E
		5'd16: joy1[11] <= joy_data;	// P1 Select
		5'd17: joy1[10] <= joy_data;	// P1 Start
		5'd18: joy2[9]  <= joy_data;	// P2 F
		5'd19: joy2[8]  <= joy_data;	// P2 E
		5'd20: joy2[11] <= joy_data;	// P2 Select
		5'd21: joy2[10] <= joy_data;	// P2 Start
		5'd22: joy2[7]  <= joy_data;	// P2 D
		5'd23: joy2[6]  <= joy_data;	// P2 C
		5'd24: joy2[5]  <= joy_data;	// P2 B
		5'd25: joy2[4]  <= joy_data;	// P2 A
		default: ;
	endcase
end

assign joystick1 = ~joy1;
assign joystick2 = ~joy2;

endmodule
