
`timescale 1 ns / 1 ps

	module axis_life_v1_0_M00_AXIS #
	(
		// Users to add parameters here
        parameter integer SIZE_X = 8,
		parameter integer SIZE_Y = 8,
		parameter integer SIZE_T = SIZE_X * SIZE_Y,
		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXIS address bus. The slave accepts the read and write addresses of width C_M_AXIS_TDATA_WIDTH.
		parameter integer C_M_AXIS_TDATA_WIDTH	= 32,
		// Start count is the number of clock cycles the master will wait before initiating/issuing any transaction.
		parameter integer C_M_START_COUNT	= 8
	)
	(
		// Users to add ports here
        input wire LOAD,
        input wire [SIZE_T-1:0] INIT_DATA,
        output wire [SIZE_T-1:0] Q,
        input wire [SIZE_T-1:0] NEXT,
		// User ports ends
		// Do not modify the ports beyond this line

		// Global ports
		input wire  M_AXIS_ACLK,
		// 
		input wire  M_AXIS_ARESETN,
		// Master Stream Ports. TVALID indicates that the master is driving a valid transfer, A transfer takes place when both TVALID and TREADY are asserted. 
		output wire  M_AXIS_TVALID,
		// TDATA is the primary payload that is used to provide the data that is passing across the interface from the master.
		output wire [C_M_AXIS_TDATA_WIDTH-1 : 0] M_AXIS_TDATA,
		// TSTRB is the byte qualifier that indicates whether the content of the associated byte of TDATA is processed as a data byte or a position byte.
		output wire [(C_M_AXIS_TDATA_WIDTH/8)-1 : 0] M_AXIS_TSTRB,
		// TLAST indicates the boundary of a packet.
		output wire  M_AXIS_TLAST,
		// TREADY indicates that the slave can accept a transfer in the current cycle.
		input wire  M_AXIS_TREADY
	);
	// Total number of output data                                                 
	localparam NUMBER_OF_OUTPUT_WORDS = SIZE_T / C_M_AXIS_TDATA_WIDTH ;                                               
	                                                                                     
	// function called clogb2 that returns an integer which has the                      
	// value of the ceiling of the log base 2.                                           
	function integer clogb2 (input integer bit_depth);                                   
	  begin                                                                              
	    for(clogb2=0; bit_depth>0; clogb2=clogb2+1)                                      
	      bit_depth = bit_depth >> 1;                                                    
	  end                                                                                
	endfunction                                                                          
	                                                                                     
	// WAIT_COUNT_BITS is the width of the wait counter.                                 
	localparam integer WAIT_COUNT_BITS = clogb2(C_M_START_COUNT-1);                      
	                                                                                     
	// bit_num gives the minimum number of bits needed to address 'depth' size of FIFO.  
	localparam bit_num  = clogb2(NUMBER_OF_OUTPUT_WORDS);                                
	                                                                                     
	// Define the states of state machine                                                
	// The control state machine oversees the writing of input streaming data to the FIFO,
	// and outputs the streaming data from the FIFO                                      
	parameter [1:0] IDLE = 2'b00,        // This is the initial/idle state               
	                                                                                     
	                INIT_COUNTER  = 2'b01, // This state initializes the counter, once   
	                                // the counter reaches C_M_START_COUNT count,        
	                                // the state machine changes state to SEND_STREAM     
	                SEND_STREAM   = 2'b10; // In this state the                          
	                                     // stream data is output through M_AXIS_TDATA   
	// State variable                                                                    
	reg [1:0] mst_exec_state;                                                            
	// Example design FIFO read pointer                                                  
	reg [bit_num-1:0] read_pointer;     
	
	// Life internal signals
	wire load_valid;
	reg [SIZE_T-1:0] life_data;    
	reg load_valid_delay;                                          

	// AXI Stream internal signals
	//wait counter. The master waits for the user defined number of clock cycles before initiating a transfer.
	reg [WAIT_COUNT_BITS-1 : 0] 	count;
	//streaming data valid
	wire  	axis_tvalid;
	//streaming data valid delayed by one clock cycle
	reg  	axis_tvalid_delay;
	//Last of the streaming data 
	wire  	axis_tlast;
	//Last of the streaming data delayed by one clock cycle
	reg  	axis_tlast_delay;
	//FIFO implementation signals
	reg [C_M_AXIS_TDATA_WIDTH-1 : 0] 	stream_data_out;
	wire  	tx_en;
	//The master has issued all the streaming data stored in FIFO
	reg  	tx_done;
	
	reg tx_done_prev;
	wire tx_done_rising_edge;


    // Life I/O Connections assignments
    assign Q = life_data;

	// AXIS I/O Connections assignments
	assign M_AXIS_TVALID	= axis_tvalid_delay;
	assign M_AXIS_TDATA	= stream_data_out;
	assign M_AXIS_TLAST	= axis_tlast_delay;
	assign M_AXIS_TSTRB	= {(C_M_AXIS_TDATA_WIDTH/8){1'b1}};
	                           
	always @(posedge M_AXIS_ACLK)                                             
	begin                                                                     
	  if (!M_AXIS_ARESETN)                                                                                         
	    begin                                                                 
	      mst_exec_state <= IDLE;                                             
	      count    <= 0;                                                      
	    end                                                                   
	  else                                                                    
	    case (mst_exec_state)                                                 
	      IDLE:                                                                                          
            if (LOAD || life_data != 0)
              mst_exec_state <= INIT_COUNTER;
            else
              mst_exec_state <= IDLE;                                                           
	                                                                          
	      INIT_COUNTER:                                                                                    
	        if ( count == C_M_START_COUNT - 1 )                               
	          begin                                                           
	            mst_exec_state  <= SEND_STREAM;                               
	          end                                                             
	        else                                                              
	          begin                                                           
	            count <= count + 1;                                           
	            mst_exec_state  <= INIT_COUNTER;                              
	          end                                                             
	                                                                          
	      SEND_STREAM:                                                                                 
	        if (tx_done)                                                      
	          begin                                                           
	            mst_exec_state <= IDLE;
	            count <= 0;                            
	          end                                                             
	        else                                                              
	          begin                                                           
	            mst_exec_state <= SEND_STREAM;                                
	          end                                                             
	    endcase                                                               
	end                                                                       

	assign axis_tvalid = ((mst_exec_state == SEND_STREAM) && (read_pointer < NUMBER_OF_OUTPUT_WORDS));                                                                                                                                                        
	assign axis_tlast = (read_pointer == NUMBER_OF_OUTPUT_WORDS-1);                                                                                                                             
	                                                                                                                                                      
	always @(posedge M_AXIS_ACLK)                                                                  
	begin                                                                                          
	  if (!M_AXIS_ARESETN)                                                                         
	    begin                                                                                      
	      axis_tvalid_delay <= 1'b0;                                                               
	      axis_tlast_delay <= 1'b0;                                                             
	    end                                                                                        
	  else                                                                                         
	    begin                                                                                      
	      axis_tvalid_delay <= axis_tvalid;                                                        
	      axis_tlast_delay <= axis_tlast;                                                          
	    end                                                                                        
	end                                                                                            

    always@(posedge M_AXIS_ACLK)                                               
    begin                                                                            
      if(!M_AXIS_ARESETN)                                                            
        begin                                                                        
          read_pointer <= 0;                                                         
          tx_done <= 1'b0;                                                           
        end                                                                          
      else                                                                           
        begin
          if (tx_done)  // Reset read_pointer when tx_done is asserted
            begin
              read_pointer <= 0;
              tx_done <= 1'b0;  // Clear tx_done after reset
            end
          else if (read_pointer <= NUMBER_OF_OUTPUT_WORDS-1)                                
            begin                                                                 
              if (tx_en)                                                                                             
                begin                                                                  
                  read_pointer <= read_pointer + 1;                                    
                  tx_done <= 1'b0;                                                     
                end                                                                    
            end                                                                        
          else if (read_pointer == NUMBER_OF_OUTPUT_WORDS)                             
            begin                                                                                                                               
              tx_done <= 1'b1;                                                        
            end   
        end                                                                     
    end                                                                            


	//FIFO read enable generation 

	assign tx_en = M_AXIS_TREADY && axis_tvalid;   
	                                                     
	    // Streaming output data is read from FIFO       
	    always @( posedge M_AXIS_ACLK )                  
	    begin                                            
	      if(!M_AXIS_ARESETN)                            
	        begin                                        
	          stream_data_out <= 0;                      
	        end                                          
	      else if (tx_en)  
	        begin                                        
	          stream_data_out <= life_data[read_pointer * C_M_AXIS_TDATA_WIDTH +: C_M_AXIS_TDATA_WIDTH];    
	        end                                        
	    end                                              

	// Add user logic here
	assign tx_done_rising_edge = tx_done && !tx_done_prev;
	
	always @(posedge M_AXIS_ACLK) begin
        if (!M_AXIS_ARESETN) begin
            tx_done_prev <= 1'b0;
        end else begin
            tx_done_prev <= tx_done;
        end
    end
    
    assign load_valid = LOAD && (mst_exec_state == IDLE);
    
    always @( posedge M_AXIS_ACLK )                  
    begin                                            
      if(!M_AXIS_ARESETN)                            
        begin                                        
          life_data <= 0;                      
        end                                          
      else if (tx_done_rising_edge)
        begin                                        
          life_data <= NEXT; 
        end        
      else if (load_valid)  
        begin                                        
          life_data <= INIT_DATA; 
        end                                      
    end 
	// User logic ends

	endmodule
