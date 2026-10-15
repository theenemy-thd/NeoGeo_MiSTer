localparam SND_RESET_SLOW = 24'd12000000;	// 250ms at 48MHz
localparam SND_POLL_SLOW  = 24'd96000;		// 2ms
localparam SND_POLL_GAP   = 15'd24000;		// 0.5ms
localparam CD_REG_SLOW    = 24'd48000;		// 1ms

wire snd_acc = ~nAS & ~nUDS & (M68K_ADDR[23:17] == 7'b0011_001);	// $320000-$33FFFF
reg  snd_acc_d = 0;
reg  cd_acc_d = 0;
reg  [23:0] snd_slow_cnt = 0;
reg  [14:0] snd_poll_gap = 15'h7FFF;
always @(posedge CLK_48M) begin
	snd_acc_d <= snd_acc;
	cd_acc_d  <= cd_reg_acc;
	if (snd_slow_cnt != 0) snd_slow_cnt <= snd_slow_cnt - 24'd1;
	if (snd_poll_gap != 15'h7FFF) snd_poll_gap <= snd_poll_gap + 15'd1;
	if (!nRESET || !CPU_OVERCLOCK) begin
		snd_slow_cnt <= 0;
		snd_poll_gap <= 15'h7FFF;
	end else if (snd_acc & ~snd_acc_d) begin
		if (!M68K_RW) begin
			if (FX68K_DATAOUT[15:8] == 8'h01 || FX68K_DATAOUT[15:8] == 8'h03)
				snd_slow_cnt <= SND_RESET_SLOW;
		end else begin
			if (snd_poll_gap < SND_POLL_GAP && snd_slow_cnt < SND_POLL_SLOW)
				snd_slow_cnt <= SND_POLL_SLOW;
			snd_poll_gap <= 0;
		end
	end
	else if (cd_reg_acc & ~cd_acc_d) begin
		if (snd_slow_cnt < CD_REG_SLOW) snd_slow_cnt <= CD_REG_SLOW;
	end
end
assign CPU_SLOW = (snd_slow_cnt != 0);
