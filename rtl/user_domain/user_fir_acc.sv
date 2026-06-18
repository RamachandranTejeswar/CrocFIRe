`include "common_cells/registers.svh"

module user_fir_acc #(
  parameter obi_pkg::obi_cfg_t SbrObiCfg    = obi_pkg::ObiDefaultConfig,
  parameter obi_pkg::obi_cfg_t MgrObiCfg    = obi_pkg::ObiDefaultConfig,
  parameter type               sbr_obi_req_t = logic,
  parameter type               sbr_obi_rsp_t = logic,
  parameter type               mgr_obi_req_t = logic,
  parameter type               mgr_obi_rsp_t = logic,
  parameter int unsigned       NumTaps       = 32,
  parameter int unsigned       NumMacs       = 1
)(
  input  logic     clk_i,
  input  logic     rst_ni,

  // OBI Subordinate Port (CPU -> Accelerator configuration)
  input  sbr_obi_req_t  obi_cfg_req_i,
  output sbr_obi_rsp_t  obi_cfg_rsp_o,

  // OBI Master Port (Accelerator -> Data SRAM, read)
  output mgr_obi_req_t  obi_mem_req_o,
  input  mgr_obi_rsp_t  obi_mem_rsp_i,

  // Output signal indicating all computations are done
  output logic done_o
);

    // Interconnect wires - FSM <-> Datapath
    logic        read_en;
    logic        compute_en;
    logic        load_from_aux;
    logic [31:0] fir_result;
    logic        fir_valid;
    
    logic signed [7:0] coefficients_o [0:31];

    // Interconnect wires - FSM <-> FIFO
    logic        fifo_push;
    logic [31:0] fifo_data;
    logic        fifo_pop;
    logic        fifo_full;
    logic        fifo_empty;
    logic [31:0] fifo_rdata;

    // FSM
    fir_fsm #(
    .SbrObiCfg    (SbrObiCfg),
    .MgrObiCfg    (MgrObiCfg),
    .sbr_obi_req_t(sbr_obi_req_t),
    .sbr_obi_rsp_t(sbr_obi_rsp_t),
    .mgr_obi_req_t(mgr_obi_req_t),
    .mgr_obi_rsp_t(mgr_obi_rsp_t),
    .NumTaps      (NumTaps),
    .NumMacs      (NumMacs)
    )  i_fir_fsm (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .obi_cfg_req_i   (obi_cfg_req_i),
        .obi_cfg_rsp_o   (obi_cfg_rsp_o),
        .obi_mem_req_o   (obi_mem_req_o),
        .obi_mem_rsp_i   (obi_mem_rsp_i),
        .read_en_o       (read_en),
        .compute_en_o    (compute_en),
        .load_from_aux_o (load_from_aux),
        .coeff_o         (coefficients_o),
        .fir_valid_i     (fir_valid),
        .fir_result_i    (fir_result),
        .fifo_push_o     (fifo_push),
        .fifo_data_o     (fifo_data),
        .fifo_pop_o      (fifo_pop),
        .fifo_full_i     (fifo_full),
        .fifo_empty_i    (fifo_empty),
        .fifo_rdata_i    (fifo_rdata),
        .done_o          (done_o)
    );

    // Datapath
    fir_datapath #(
        .NumTaps(NumTaps),
        .NumMacs(NumMacs)
    ) i_fir_datapath (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .read_en_i      (read_en),
        .compute_en_i   (compute_en),
        .load_from_aux_i(load_from_aux),
        .sample_i       (obi_mem_rsp_i.r.rdata),
        .coeff_i        (coefficients_o),
        .fir_result_o   (fir_result),
        .fir_valid_o    (fir_valid)
    );

    // FIFO
    fir_fifo i_fir_fifo (
        .clk_i   (clk_i),
        .rst_ni  (rst_ni),
        .push_i  (fifo_push),
        .wdata_i (fifo_data),
        .pop_i   (fifo_pop),
        .rdata_o (fifo_rdata),
        .full_o  (fifo_full),
        .empty_o (fifo_empty)
    );

endmodule
