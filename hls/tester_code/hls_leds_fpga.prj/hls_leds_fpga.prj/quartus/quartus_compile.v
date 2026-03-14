module quartus_compile (
	  input logic resetn
	, input logic clock
	, input logic [0:0] switch_to_led_start
	, output logic [0:0] switch_to_led_busy
	, output logic [0:0] switch_to_led_done
	, input logic [0:0] switch_to_led_stall
	, output logic [31:0] switch_to_led_returndata
	, input logic [0:0] switch_to_led_button_n
	, input logic [0:0] switch_to_led_reset_button_n
	);

	logic [0:0] switch_to_led_start_reg;
	logic [0:0] switch_to_led_busy_reg;
	logic [0:0] switch_to_led_done_reg;
	logic [0:0] switch_to_led_stall_reg;
	logic [31:0] switch_to_led_returndata_reg;
	logic [0:0] switch_to_led_button_n_reg;
	logic [0:0] switch_to_led_reset_button_n_reg;


	always @(posedge clock) begin
		switch_to_led_start_reg <= switch_to_led_start;
		switch_to_led_busy <= switch_to_led_busy_reg;
		switch_to_led_done <= switch_to_led_done_reg;
		switch_to_led_stall_reg <= switch_to_led_stall;
		switch_to_led_returndata <= switch_to_led_returndata_reg;
		switch_to_led_button_n_reg <= switch_to_led_button_n;
		switch_to_led_reset_button_n_reg <= switch_to_led_reset_button_n;
	end


	reg [2:0] sync_resetn;
	always @(posedge clock or negedge resetn) begin
		if (!resetn) begin
			sync_resetn <= 3'b0;
		end else begin
			sync_resetn <= {sync_resetn[1:0], 1'b1};
		end
	end


	switch_to_led switch_to_led_inst (
		  .resetn(sync_resetn[2])
		, .clock(clock)
		, .start(switch_to_led_start_reg)
		, .busy(switch_to_led_busy_reg)
		, .done(switch_to_led_done_reg)
		, .stall(switch_to_led_stall_reg)
		, .returndata(switch_to_led_returndata_reg)
		, .button_n(switch_to_led_button_n_reg)
		, .reset_button_n(switch_to_led_reset_button_n_reg)
	);



endmodule
