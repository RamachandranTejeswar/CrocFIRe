`include "common_cells/registers.svh"

module fir_fsm #(
  parameter obi_pkg::obi_cfg_t SbrObiCfg    = obi_pkg::ObiDefaultConfig,
  parameter obi_pkg::obi_cfg_t MgrObiCfg    = obi_pkg::ObiDefaultConfig,
  parameter type               sbr_obi_req_t = logic,
  parameter type               sbr_obi_rsp_t = logic,
  parameter type               mgr_obi_req_t = logic,
  parameter type               mgr_obi_rsp_t = logic,
  parameter int unsigned       NumTaps       = 32,
  parameter int unsigned       NumMacs       = 1
)
(
    input logic clk_i,
    input logic rst_ni, 

    // OBI Subordinate Port (CPU -> Accelerator configuration)
    input  sbr_obi_req_t  obi_cfg_req_i,
    output sbr_obi_rsp_t  obi_cfg_rsp_o,

    // OBI Master Port (Accelerator -> Data SRAM, read)
    output mgr_obi_req_t  obi_mem_req_o,
    input  mgr_obi_rsp_t  obi_mem_rsp_i,

    // Datapath Control Signals
    output logic        read_en_o,
    output logic        compute_en_o,
    output logic        load_from_aux_o,

    output logic signed [7:0] coeff_o [0:31],

    input logic         fir_valid_i,
    input logic [31:0]  fir_result_i,

    // FIFO Signals
    output logic        fifo_push_o,
    output logic [31:0] fifo_data_o,
    output logic        fifo_pop_o,

    input  logic        fifo_full_i,
    input  logic        fifo_empty_i,
    input  logic [31:0] fifo_rdata_i,

    //  Status
    output logic done_o
);

    // Start signal must arrive from the CPU
    logic start_d, start_q;
    `FF(start_q, start_d, '0);

    // ******************** OBI data from the CPU - Start signal ********************

    // Fields to hold the Sampled OBI Request from Manager
    logic req_d, req_q;
    logic we_d, we_q;
    logic [SbrObiCfg.AddrWidth-1:0] addr_d, addr_q;
    logic [  SbrObiCfg.IdWidth-1:0] id_d, id_q;
    logic [SbrObiCfg.DataWidth-1:0] wdata_d, wdata_q;
    logic signed [7:0] coeff_d [0:31], coeff_q [0:31];

    // Connect the OBI inputs to the appropriate pins within the Accelerator
    assign req_d =  obi_cfg_req_i.req;

    assign obi_cfg_rsp_o.gnt = obi_cfg_req_i.req;
    assign obi_cfg_rsp_o.rvalid     = req_q;

    assign we_d = obi_cfg_req_i.a.we;
    assign addr_d = obi_cfg_req_i.a.addr;
    assign wdata_d = obi_cfg_req_i.a.wdata;

    // Coefficients
    assign coeff_o = coeff_q;

    // Sample OBI Request into the Accelerator
    `FF(req_q, req_d, '0);
    `FF(we_q, we_d, '0);
    `FF(addr_q, addr_d, '0);
    `FF(wdata_q, wdata_d, '0);

    // Coefficients
    for (genvar i = 0; i < 32; i++) begin
        `FF(coeff_q[i], coeff_d[i], 8'h0);
    end

    // ******************** Memory Mapped Registers ********************

    always_comb begin

        start_d = start_q;
        num_samples_d = num_samples_q;
                
        obi_cfg_rsp_o.r.rdata    = '0;
        obi_cfg_rsp_o.r.rid      = id_q;
    	obi_cfg_rsp_o.r.err      = '0;
    	obi_cfg_rsp_o.r.r_optional = '0;

        for (int i = 0; i < 32; i++) begin
            coeff_d[i] = coeff_q[i];
        end

        // Coefficients at offsets 0x10 to 0x8C (one per coefficient)
        for (int i = 0; i < 32; i++) begin
            if (req_q && we_q && (addr_q[7:2] == (4 + i))) begin
                coeff_d[i] = wdata_q[7:0];
            end
        end

        // Status register for compute initiation at offset 0x00
        if (req_q && we_q && (addr_q[7:2] == 2'h0)) begin
            start_d = wdata_q[0];
        end

        // Status register for compute completion at offset 0x04
        if (req_q && !we_q && (addr_q[7:2] == 2'h1)) begin
            obi_cfg_rsp_o.r.rdata = {31'b0, done_check_q};
        end

        // Register for storing Number of Samples at offset 0x08
        if (req_q && we_q && (addr_q[7:2] == 2'h2)) begin
            num_samples_d = wdata_q[15:0];
        end

        // Status Register for invalid length at offset 0x0C
        if (req_q && !we_q && (addr_q[7:2] == 2'h3)) begin
            obi_cfg_rsp_o.r.rdata = {31'b0, invalid_len_q};
        end

        if ((state_q == IDLE) && start_q) begin
            start_d = 1'b0;
        end
    end

    // ******************** Progress Tracking Variables ********************

    logic [15:0] num_samples_d, num_samples_q;              // Will never exceed 540 (0 - 540)
    logic [31:0] base_addr_q;                               // Hard Coded 0x2000_2028 (Leaving the first 10 words for MM-Registers)
    logic [31:0] curr_addr_d, curr_addr_q;                  // Current Read Address on Data SRAM
    logic [15:0] samples_remaining_d, samples_remaining_q;  // Number of Samples remaining to be read
    logic [31:0] output_count_d, output_count_q;            // Number of Outputs generated
    logic [7:0] fill_count_d, fill_count_q;                 // Number of bytes of data filled in the Aux and Circular buffers
    logic rvalid_seen_d, rvalid_seen_q;
    logic first_aux_done_d, first_aux_done_q;               // Track whether the first Aux Read is done or not
    logic invalid_len_d, invalid_len_q;                     // Check whether a minimum of 36 samples are available

    logic [2:0] aux_count_d, aux_count_q;                   // Number of bytes remaining in the Aux Buffer
    logic aux_refill_pending_d, aux_refill_pending_q;       // Track whether OBI read is done or not

    logic done_check_d, done_check_q;                       // Sticky flag for done_o Memory mapped register

    logic [1:0] stall_count_d, stall_count_q;               


    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // num_samples_q  <= 64;                        // Initial test with 64 samples
            base_addr_q    <= 32'h1000_1000;                // Data to be stored from 0x1000_0800 on Data SRAM
        end else begin
        // nothing needed here since FF macro handles the rest
        end
    end

    `FF(output_count_q, output_count_d, '0);
    `FF(curr_addr_q, curr_addr_d, base_addr_q);
    `FF(samples_remaining_q, samples_remaining_d, num_samples_q);
    `FF(rvalid_seen_q, rvalid_seen_d, '0);
    `FF(fill_count_q, fill_count_d, '0);
    `FF(num_samples_q, num_samples_d, '0);
    `FF(invalid_len_q, invalid_len_d, '0);

    `FF(aux_count_q, aux_count_d, '0);
    `FF(aux_refill_pending_q, aux_refill_pending_d, '0);
    `FF(first_aux_done_q, first_aux_done_d, '0);
    `FF(done_check_q, done_check_d, '0);
    
    
    `FF(stall_count_q, stall_count_d, 2'd1);
    
    typedef enum logic [1:0] {FIFO_IDLE, FIFO_WRITEBACK} fifo_state_t;
    fifo_state_t fifo_state_d, fifo_state_q;

    logic [31:0] out_addr_d, out_addr_q;

    `FF(fifo_state_q, fifo_state_d, FIFO_IDLE);
    `FF(out_addr_q, out_addr_d, '0);

    typedef enum logic [3:0] {IDLE, READ_DATA, COMPUTE, COMPUTE_COMPLETE} state_t;
    state_t state_d, state_q;
    `FF(state_q, state_d, IDLE);

    always_comb begin
        
        // State and Counter Defaults
        state_d = state_q;

        curr_addr_d = curr_addr_q;
        samples_remaining_d = samples_remaining_q;
        fill_count_d         = fill_count_q;
        aux_count_d          = aux_count_q;
        output_count_d       = output_count_q;
        aux_refill_pending_d = aux_refill_pending_q;
        rvalid_seen_d        = rvalid_seen_q;
        invalid_len_d        = invalid_len_q;
        
        done_check_d = done_check_q;
        stall_count_d = stall_count_q;

        // Output signal defaults
        read_en_o       = 1'b0;
        compute_en_o    = 1'b0;
        fifo_push_o     = 1'b0;
        fifo_data_o     = '0;
        load_from_aux_o = 1'b0;
        done_o          = 1'b0;
 
        // OBI master port defaults
        obi_mem_req_o.req    = 1'b0;
        obi_mem_req_o.a.addr = '0;
        obi_mem_req_o.a.we   = 1'b0;
        obi_mem_req_o.a.wdata = '0;
        obi_mem_req_o.a.aid  = '0;
        obi_mem_req_o.a.be   = 4'hF;

        // FIFO FSM Defaults
        fifo_state_d = fifo_state_q;
        out_addr_d   = out_addr_q;       
        fifo_pop_o   = 1'b0;

        // ******************** Main FSM ********************
        case (state_q)

            IDLE: begin
                if(start_q && (num_samples_q >= 36) && (num_samples_q <= 540)) begin
                    state_d = READ_DATA;
                    curr_addr_d = base_addr_q;              // Start reading from here on Data SRAM
                    samples_remaining_d = num_samples_q;    // Total number of samples to be read
                    out_addr_d  = 32'h1000_1800;            // initialize output address once here
                    done_o = 1'b0;
                    done_check_d = 1'b0;
                    stall_count_d = (NumMacs == 32) ? 2'd3 : 2'd1;                   
                end

                if(start_q && (num_samples_q < 36 || (num_samples_q > 540))) begin
                    invalid_len_d = 1'b1;  // set error flag
                end
            end

            READ_DATA: begin

                obi_mem_req_o.req = !rvalid_seen_q; // Send out a request when reception of valid data stops
                obi_mem_req_o.a.addr = curr_addr_q; // Address to read from on Data SRAM
                obi_mem_req_o.a.we = 1'b0;          // WE = 0 since it is a read request
                obi_mem_req_o.a.wdata = '0;         // Irrelevant, no write data
                obi_mem_req_o.a.aid = '0;
                obi_mem_req_o.a.be = 4'hF;

                // gnt received - stop requesting, wait for rvalid
                if (obi_mem_rsp_i.gnt) begin
                    rvalid_seen_d = 1'b1;
                end

                if (obi_mem_rsp_i.rvalid && rvalid_seen_q) begin

                    curr_addr_d = curr_addr_q + 4;          // Increment Data SRAM read address by 4 bytes 
                    fill_count_d =  fill_count_q + 1;       // Increment fill_count by 1 after reading every 4 bytes
                    read_en_o = 1'b1;                       // Notify the local datapath to latch on the newly received data
                    rvalid_seen_d = 1'b0;                   // Clear rvalid_seen to allow next request

                    if (samples_remaining_q >= 4) begin
                        samples_remaining_d = samples_remaining_q - 4;
                    end
                    else begin
                        samples_remaining_d = 0;
                    end

                end

                // 8 reads will fill the Circular Buffer
                // 9th read will fill the Aux Buffer
                // After 9 reads, move to compute

                if (fill_count_q == 9) begin
                    state_d = COMPUTE;
                    fill_count_d = 0;
                end
                
            end

            COMPUTE: begin

                // In COMPUTE state:
                if (fir_valid_i) begin
                    stall_count_d = (NumMacs == 32) ? 2'd3 : 2'd1;  // stall for 1 cycle
                end else if (stall_count_q > 0) begin
                    stall_count_d = stall_count_q - 1;
                end

                // compute_en_o = (stall_count_q == 0) && !fifo_full_i;
                compute_en_o = (NumMacs >= 16) ? ((stall_count_q == 0) && !fifo_full_i) : 1'b1;

                if (aux_count_q == 0 && !aux_refill_pending_q) begin
                    // If the Aux Buffer is empty, issue read request
                    obi_mem_req_o.req = 1'b1;
                    obi_mem_req_o.a.addr = curr_addr_q;
                    obi_mem_req_o.a.we = 1'b0;
                    obi_mem_req_o.a.wdata = '0;
                    obi_mem_req_o.a.aid = '0;
                    obi_mem_req_o.a.be = 4'hF;
                    aux_refill_pending_d = 1'b1;
                end

                if (obi_mem_rsp_i.rvalid && aux_refill_pending_q) begin

                    aux_count_d = 4;  // always 4, padding zeros are safe
                    if (samples_remaining_q >= 4)
                        samples_remaining_d = samples_remaining_q - 4;
                    else
                        samples_remaining_d = 0;

                    aux_refill_pending_d = 1'b0;
                    
                    if (first_aux_done_q) begin
                        curr_addr_d = curr_addr_q + 4;
                        read_en_o = 1'b1;
                    end
                    first_aux_done_d = 1'b1;
                end

                // One FIR output done - Shift the circular buffer and load one value from the Aux Buffer
                if(fir_valid_i && output_count_q < (num_samples_q - NumTaps + 1)) begin
                    fifo_push_o = 1'b1;                     // Signal to Push the result into the FIFO
                    fifo_data_o = fir_result_i;             // Data to be pushed into the FIFO
                    output_count_d = output_count_q + 1;    // Increment number of outputs computed by 1
                end

                // Everytime a valid result is generated, load the next value from the Aux Buffer into the Circular Buffer
                if(fir_valid_i && (aux_count_q > 0)) begin
                    aux_count_d = aux_count_q - 1;          // One sample consumed from the Aux Buffer, so decrement count by 1
                    load_from_aux_o = 1'b1;                 // Load one value from the Aux Buffer into the Circular Buffer
                end

                // FIFO Backpressure
                if (fifo_full_i) begin
                    compute_en_o = 1'b0;
                end

                // All outputs Produced
                if (output_count_q == (num_samples_q - NumTaps + 1)) begin
                    state_d = COMPUTE_COMPLETE;
                    compute_en_o = 1'b0;
                end
            end

            COMPUTE_COMPLETE: begin
                compute_en_o = 1'b0;        // Disable Compute units since computation is done
                fifo_push_o = 1'b0;         // Stop pushing any data into the FIFO - disable the push control signal
                aux_refill_pending_d = 1'b0;// Clear any stuck pending refill

                if (fifo_empty_i) begin
                    // Reset all counters and flags once all the results are moved back to Data SRAM
                    done_o = 1'b1;          // Once all the final results are moved to Data SRAM and the FIFO is empty assert done_o to the CPU
                    done_check_d = 1'b1;

                    state_d = IDLE;         // Return back to IDLE state
                    fill_count_d = '0;      // The Auxiliary and Circular buffer are considered to be empty now. Count is reset to 0 
                    aux_count_d = '0;       // Auxiliary Buffer is empty now. Count is reset to 0
                    output_count_d = '0;    // Number of Outputs generated is reset to 0
                end
            end

        endcase

        // ******************** FIFO FSM ********************
        case (fifo_state_q)

            FIFO_IDLE: begin
                if(!fifo_empty_i) begin                 // If FIFO is not empty
                    fifo_state_d = FIFO_WRITEBACK;

                    // Results expected to be stored in 0x1000_1000 to 0x1000_1800
                end
            end

            FIFO_WRITEBACK: begin
                if (!aux_refill_pending_q && state_q != READ_DATA) begin
                    obi_mem_req_o.req     = !fifo_empty_i;
                    obi_mem_req_o.a.we    = 1'b1;
                    obi_mem_req_o.a.addr  = out_addr_q;
                    obi_mem_req_o.a.wdata = fifo_rdata_i;
                    obi_mem_req_o.a.aid   = '0;
                    obi_mem_req_o.a.be    = 4'hF;

                    if (fifo_empty_i) begin
                        fifo_state_d = FIFO_IDLE;
                    end
                    else if (obi_mem_rsp_i.gnt) begin
                        fifo_pop_o = 1'b1;
                        out_addr_d = out_addr_q + 32'h4;
                    end
                end
            end

        endcase

    end
    
endmodule
