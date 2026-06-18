`include "common_cells/registers.svh"

module fir_datapath #(
  parameter int NumTaps = 32,
  parameter int NumMacs = 1
)
(
    input logic clk_i,
    input logic rst_ni,

    // Control Signals from FSM
    input logic read_en_i,
    input logic compute_en_i,
    input logic load_from_aux_i,

    // Incoming Sample data and Coefficients from Data SRAM via FSM
    input logic [31:0] sample_i,
    input logic signed [7:0] coeff_i [0:NumTaps-1],

    // FIR result to FIFO
    output logic [31:0] fir_result_o,
    output logic fir_valid_o
);

    // Circular buffer with 32 x 8-bit samples
    logic signed [7:0] circ_buf_d [0:31], circ_buf_q [0:31];

    // Aux Buffer with 4 x 8-bit samples (One OBI Word)
    logic signed [7:0] aux_buf_d [0:3], aux_buf_q [0:3];

    // Circular Buffer Write Pointer
    // Tracks where to write data on the Circular Buffer, from the Aux Buffer
    logic [4:0] circ_wr_ptr_d, circ_wr_ptr_q;   // 0 to 31
    
    // Aux Buffer Read Pointer
    // Tracks which data to read from the Aux Buffer into the Circular Buffer
    logic [1:0] aux_rd_ptr_d, aux_rd_ptr_q;     // 0 to 3

    `FF(circ_wr_ptr_q, circ_wr_ptr_d, '0);
    `FF(aux_rd_ptr_q, aux_rd_ptr_d, '0);

    
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < 32; i++) circ_buf_q[i] <= 8'h0;
            for (int i = 0; i < 4;  i++) aux_buf_q[i]  <= 8'h0;
        end else begin
            circ_buf_q <= circ_buf_d;
            aux_buf_q  <= aux_buf_d;
        end
    end

    // ******************** MAC Computation ********************

    logic [4:0] tap_idx_d, tap_idx_q;                   // Pointer to keep track of which taps have been procedded
    logic signed [20:0] accumulator_d,accumulator_q;    // 21-bit to prevent overflow
    logic initial_load_done_d, initial_load_done_q;

    logic signed [20:0] mac_sum;                        // 21-bit MAC Sum Accumulator

    `FF(tap_idx_q, tap_idx_d, '0);
    `FF(accumulator_q, accumulator_d, '0);
    `FF(initial_load_done_q, initial_load_done_d, '0);

    always_comb begin

        // Defaults
        tap_idx_d           = tap_idx_q;
        accumulator_d       = accumulator_q;
        fir_result_o        = '0;
        fir_valid_o         = 1'b0;
        initial_load_done_d = initial_load_done_q;
        circ_buf_d          = circ_buf_q;
        aux_buf_d           = aux_buf_q;
        circ_wr_ptr_d       = circ_wr_ptr_q;
        aux_rd_ptr_d        = aux_rd_ptr_q;
        mac_sum             = '0;

        // Parameterized Mac Computation
        if(compute_en_i) begin

            mac_sum = '0;

            // 'm' number of MAC units
            for(int m = 0; m < NumMacs; m++) begin
                mac_sum += (signed'(circ_buf_q[tap_idx_q + m]) * signed'(coeff_i[tap_idx_q + m]));
            end

            accumulator_d = accumulator_q + mac_sum;

            if(tap_idx_q == NumTaps - NumMacs) begin
                // fir_result_o = {{11{accumulator_d[20]}}, accumulator_d};
                fir_result_o = accumulator_d >>> 7;
                fir_valid_o = 1'b1;
                tap_idx_d = '0;
                accumulator_d = '0;
            end

            else begin
                tap_idx_d = tap_idx_q + NumMacs;
            end

        end

        // Load sample form Aux Buffer into the Circular buffer after calculating one result
        if (load_from_aux_i) begin
            // Kick out oldest sample, load next sample from Aux Buffer
            // Shift all existing samples to the left on the Circular Buffer
            for (int i = 0; i < 31; i++) begin
                circ_buf_d[i] = circ_buf_q[i+1];
            end

            // New Sample from Aux goes at the end
            circ_buf_d[31] = aux_buf_q[aux_rd_ptr_q];
            aux_rd_ptr_d = aux_rd_ptr_q + 1;

        end

        // If Read Enable is still active and initial load is not done, load the newly arrived samples into the Circular Buffer
        if(read_en_i && !initial_load_done_q) begin
            circ_buf_d[circ_wr_ptr_q] = sample_i[7:0];
            circ_buf_d[circ_wr_ptr_q + 1] = sample_i[15:8];
            circ_buf_d[circ_wr_ptr_q + 2] = sample_i[23:16];
            circ_buf_d[circ_wr_ptr_q + 3] = sample_i[31:24];
            circ_wr_ptr_d = circ_wr_ptr_q + 4;

            // After 28 values, we perform the 8th read, and then the circular buffer will be full
            if(circ_wr_ptr_q == 5'd28) begin
                initial_load_done_d = 1'b1;
            end
        end

        // If initial loas is done, refill Aux Buffer whenever new data arrives
        if (read_en_i && initial_load_done_q) begin
            aux_buf_d[0] = sample_i[7:0];
            aux_buf_d[1] = sample_i[15:8];
            aux_buf_d[2] = sample_i[23:16];
            aux_buf_d[3] = sample_i[31:24];
            aux_rd_ptr_d = '0;              // Reset read pointer for new aux data;
        end

    end

endmodule
