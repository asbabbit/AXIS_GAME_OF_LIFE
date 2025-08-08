
`timescale 1 ns / 1 ps

	module axis_life_v1_0 #
	(
		// Users to add parameters here
		// Users to add parameters here
        parameter integer SIZE_X = 8,
		parameter integer SIZE_Y = 8,
		parameter integer SIZE_T = SIZE_X * SIZE_Y,
		// User parameters ends
		// Do not modify the parameters beyond this line

		// Parameters of Axi Master Bus Interface M00_AXIS
		parameter integer C_M00_AXIS_TDATA_WIDTH	= 32,
		parameter integer C_M00_AXIS_START_COUNT	= 32
	)
	(
		// Users to add ports here
        input wire LOAD,
        input wire [SIZE_T-1:0] INIT_DATA,
        output wire [SIZE_T-1:0] Q,
        input wire [SIZE_T-1:0] Q_PRIME,
        output wire [1:0] state,
		// User ports ends
		// Do not modify the ports beyond this line

		// Ports of Axi Master Bus Interface M00_AXIS
		input wire  m00_axis_aclk,
		input wire  m00_axis_aresetn,
		output wire  m00_axis_tvalid,
		output wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata,
		output wire [(C_M00_AXIS_TDATA_WIDTH/8)-1 : 0] m00_axis_tstrb,
		output wire  m00_axis_tlast,
		input wire  m00_axis_tready
	);

// Instantiation of Axi Bus Interface M00_AXIS
	axis_life_v1_0_M00_AXIS # ( 
		.C_M_AXIS_TDATA_WIDTH(C_M00_AXIS_TDATA_WIDTH),
		.C_M_START_COUNT(C_M00_AXIS_START_COUNT),
		.SIZE_X(SIZE_X),
		.SIZE_Y(SIZE_Y)
	) axis_life_v1_0_M00_AXIS_inst (
		.M_AXIS_ACLK(m00_axis_aclk),
		.M_AXIS_ARESETN(m00_axis_aresetn),
		.M_AXIS_TVALID(m00_axis_tvalid),
		.M_AXIS_TDATA(m00_axis_tdata),
		.M_AXIS_TSTRB(m00_axis_tstrb),
		.M_AXIS_TLAST(m00_axis_tlast),
		.M_AXIS_TREADY(m00_axis_tready),
		.LOAD(LOAD),
		.INIT_DATA(INIT_DATA),
		.Q(Q),
		.Q_PRIME(Q_PRIME),
		.state(state)
	);

	// Add user logic here

	// User logic ends

	endmodule
