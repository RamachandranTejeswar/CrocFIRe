`include "common_cells/registers.svh"

module fir_fifo(
    input logic clk_i,
    input logic rst_ni,

    input logic push_i,
    input logic [31:0] wdata_i,
    input logic pop_i,
    
    output logic [31:0] rdata_o,
    output logic full_o,
    output logic empty_o
);

  logic [31:0] fifo_mem [0:3];        // 4 entry FIFO
  logic [1:0] wr_ptr_d, wr_ptr_q;     // Write Pointer
  logic [1:0] rd_ptr_d, rd_ptr_q;     // Read Pointer
  logic [2:0] count_d, count_q;       // Counter to store number of elements in FIFO (0 - 4)

  `FF(wr_ptr_q, wr_ptr_d, '0);
  `FF(rd_ptr_q, rd_ptr_d, '0);
  `FF(count_q, count_d, '0);

  assign full_o = (count_q == 4);
  assign empty_o = (count_q == 0);
  assign rdata_o = fifo_mem[rd_ptr_q];
 

  always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
          for (int i = 0; i < 4; i++) fifo_mem[i] <= '0;
      end else begin
          if (push_i && !full_o) begin
              fifo_mem[wr_ptr_q] <= wdata_i;
          end
      end
  end

  always_comb begin

    wr_ptr_d = wr_ptr_q;
    rd_ptr_d = rd_ptr_q;
    count_d = count_q;

    if(push_i && !full_o) begin
        wr_ptr_d = wr_ptr_q + 1;
        count_d = count_q + 1;
    end
  
    if (pop_i && !empty_o) begin
      rd_ptr_d = rd_ptr_q + 1;
      count_d  = count_d - 1;
    end

  end

endmodule
