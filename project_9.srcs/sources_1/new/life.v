`timescale 1ns / 1ps
`include "rule.v"

module life #(
parameter SIZE_X = 8,
parameter SIZE_Y = 8,
parameter SIZE_T = SIZE_X * SIZE_Y
)(
    input wire [SIZE_T-1:0] q,
    output wire [SIZE_T-1:0] q_prime
  ); 
    
    genvar x, y;
    generate
        for (x=0; x<SIZE_X; x=x+1) begin : gen_x
            for (y=0; y<SIZE_Y; y=y+1) begin : gen_y
                rule fate (
                    .neigh({q[(x==0 ? SIZE_X-1 : x-1)   + (y==0 ? SIZE_Y-1 : y-1)*SIZE_X],
                            q[(x==0 ? SIZE_X-1 : x-1)   + y                *SIZE_X],
                            q[(x==0 ? SIZE_X-1 : x-1)   + (y==SIZE_Y-1 ? 0 : y+1)*SIZE_X],
                            q[x                         + (y==0 ? SIZE_Y-1 : y-1)*SIZE_X],
                            q[x                         + (y==SIZE_Y-1 ? 0 : y+1)*SIZE_X],
                            q[(x==SIZE_X-1 ? 0 : x+1)   + (y==0 ? SIZE_Y-1 : y-1)*SIZE_X],
                            q[(x==SIZE_X-1 ? 0 : x+1)   + y                *SIZE_X],
                            q[(x==SIZE_X-1 ? 0 : x+1)   + (y==SIZE_Y-1 ? 0 : y+1)*SIZE_X]}),
                    .current(q[(x + y*SIZE_X)]),
                    .q_prime(q_prime[(x + y*SIZE_X)])
                );
            end
        end
    endgenerate
endmodule