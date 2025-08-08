
    
    module rule (
        input [7:0] neigh,
        input current,
        output reg q_prime );
    
        wire [3:0] pop;
        assign pop = neigh[0] + neigh[1] + neigh[2] + neigh[3] + 
                     neigh[4] + neigh[5] + neigh[6] + neigh[7];

    
        always @(*) begin
            case (pop)
                4'b0010 : q_prime = current;
                4'b0011 : q_prime = 1'b1;
                default : q_prime = 1'b0;
            endcase
        end
    endmodule
