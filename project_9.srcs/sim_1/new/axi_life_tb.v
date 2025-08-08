`timescale 1ns / 1ps

module axis_life_v1_0_M00_AXIS_tb;

    // Parameters for the module under test
    localparam integer SIZE_X = 8;
    localparam integer SIZE_Y = 8;
    localparam integer SIZE_T = SIZE_X * SIZE_Y;
    localparam integer C_M_AXIS_TDATA_WIDTH = 32;
    localparam integer C_M_START_COUNT = 8;

    // Testbench signals (reg for driving, wire for receiving)
    reg M_AXIS_ACLK;
    reg M_AXIS_ARESETN;
    reg LOAD;
    reg [SIZE_T-1:0] INIT_DATA;
    reg M_AXIS_TREADY;

    wire [SIZE_T-1:0] Q;
    wire [SIZE_T-1:0] Q_PRIME;
    wire M_AXIS_TVALID;
    wire [C_M_AXIS_TDATA_WIDTH-1:0] M_AXIS_TDATA;
    wire [(C_M_AXIS_TDATA_WIDTH/8)-1:0] M_AXIS_TSTRB;
    wire M_AXIS_TLAST;
    
    // Internal signals from uut for debugging
    wire [1:0] mst_exec_state = uut.mst_exec_state;
    wire [1:0] read_pointer = uut.read_pointer;
    wire load_valid = uut.load_valid;
    wire [SIZE_T-1:0] life_data = uut.life_data;
    wire load_valid_delay = uut.load_valid_delay;
    wire count = uut.count;
    wire axis_tvalid = uut.axis_tvalid;
    wire axis_tvalid_delay = uut.axis_tvalid_delay;
    wire axis_tlast = uut.axis_tlast;
    wire axis_tlast_delay = uut.axis_tlast_delay;
    wire [C_M_AXIS_TDATA_WIDTH-1 : 0] stream_data_out = uut.stream_data_out;
    wire tx_en = uut.tx_en;
    wire tx_done = uut.tx_done;

    // Instantiate the Unit Under Test (UUT)
    axis_life_v1_0_M00_AXIS #(
        .SIZE_X(SIZE_X),
        .SIZE_Y(SIZE_Y),
        .C_M_AXIS_TDATA_WIDTH(C_M_AXIS_TDATA_WIDTH),
        .C_M_START_COUNT(C_M_START_COUNT)
    ) uut (
        .LOAD(LOAD),
        .INIT_DATA(INIT_DATA),
        .Q(Q),
        .Q_PRIME(Q_PRIME),
        .M_AXIS_ACLK(M_AXIS_ACLK),
        .M_AXIS_ARESETN(M_AXIS_ARESETN),
        .M_AXIS_TVALID(M_AXIS_TVALID),
        .M_AXIS_TDATA(M_AXIS_TDATA),
        .M_AXIS_TSTRB(M_AXIS_TSTRB),
        .M_AXIS_TLAST(M_AXIS_TLAST),
        .M_AXIS_TREADY(M_AXIS_TREADY)
    );
    
    life #(
        .SIZE_X(SIZE_X),
        .SIZE_Y(SIZE_Y)
    ) life_dut (
        .q(Q),
        .q_prime(Q_PRIME)
    );
        
    // Clock Generation
    initial begin
        M_AXIS_ACLK = 0;
        forever #5 M_AXIS_ACLK = ~M_AXIS_ACLK;
    end

    // Test stimulus
    initial begin
        // Initialize signals
        M_AXIS_ARESETN = 1'b0;
        LOAD = 1'b0;
        M_AXIS_TREADY = 1'b0; // Start with TREADY low
        INIT_DATA = 0;

        // Reset the DUT
        #10;
        M_AXIS_ARESETN = 1'b1;

        // Load a simple pattern
        #10;
        INIT_DATA = 64'h0x0000010101000000;
        LOAD = 1'b1;
        #10;
        LOAD = 1'b0;

        // Wait until the DUT starts transmitting data (M_AXIS_TVALID goes high)
        // Then assert TREADY to allow the first generation to pass
        wait (M_AXIS_TVALID);
        M_AXIS_TREADY = 1'b1;

        // Wait for the end of the first generation's transfer (M_AXIS_TLAST)
        @(posedge M_AXIS_TLAST);

        // Deassert TREADY to simulate the DMA getting busy
        #10; // Wait a little to ensure the last data beat is captured
        M_AXIS_TREADY = 1'b0;
        
        // Wait for a period of time to simulate DMA processing
        #100;

        // Reassert TREADY to allow the next generation to be transferred
        #10;
        M_AXIS_TREADY = 1'b1;

        // Run for a few more cycles to observe
        #600;
        $finish;
    end

    // Display useful signals for debugging
    initial begin
        $monitor("Time=%0t | State=%d | tx_en=%b | tx_done=%b | read_pointer=%d | M_AXIS_TVALID=%b | M_AXIS_TREADY=%b | M_AXIS_TDATA=%h | Q=%h",
                 $time, uut.mst_exec_state, uut.tx_en, uut.tx_done, uut.read_pointer, M_AXIS_TVALID, M_AXIS_TREADY, M_AXIS_TDATA, Q);
    end

endmodule