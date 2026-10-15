wire cd_reg_acc = SYSTEM_CDx & ~nAS & (M68K_ADDR[23:12] == 12'hFF0);
reg  cd_reg_armed = 0;
reg  [1:0] cd_reg_cnt = 0;
always @(posedge CLK_48M) begin
	if (!cd_reg_acc) begin
		cd_reg_armed <= 0;
		cd_reg_cnt   <= 0;
	end else if (CLK_EN_68K_P) begin
		cd_reg_armed <= 1;
		if (cd_reg_armed && cd_reg_cnt != 2'd3) cd_reg_cnt <= cd_reg_cnt + 2'd1;
	end
end
wire cd_reg_mask = CPU_OVERCLOCK & cd_reg_acc & ~cd_reg_armed;
wire cd_dtack_wait = CPU_OVERCLOCK & cd_reg_acc & (cd_reg_cnt < 2'd2);
wire cd_nAS  = nAS  | cd_reg_mask;
wire cd_nLDS = nLDS | cd_reg_mask;
wire cd_nUDS = nUDS | cd_reg_mask;
