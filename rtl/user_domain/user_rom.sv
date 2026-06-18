// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Cyril Koenig <cykoenig@iis.ee.ethz.ch>
// - Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

// Simple ROM
module user_rom #(
  // The OBI configuration for all ports
  parameter obi_pkg::obi_cfg_t ObiCfg    = obi_pkg::ObiDefaultConfig,
  parameter type               obi_req_t = logic,
  parameter type               obi_rsp_t = logic
) (
  input  logic     clk_i,
  input  logic     rst_ni,
  input  obi_req_t obi_req_i,
  output obi_rsp_t obi_rsp_o
);

  // Define some registers to hold the requests fields
  logic req_d, req_q;                          // Request valid
  logic we_d, we_q;                            // Write enable
  logic [ObiCfg.AddrWidth-1:0] addr_d, addr_q; // Internal address of the word to read
  logic [ObiCfg.IdWidth-1:0] id_d, id_q;       // Id of the request, must be same for the response

  // Signals used to create the response
  logic [ObiCfg.DataWidth-1:0] rsp_data; // Data field of the obi response
  logic rsp_err;                         // Error field of the obi response

  // Wire the registers holding the request
  assign req_d  = obi_req_i.req;
  assign id_d   = obi_req_i.a.aid;
  assign we_d   = obi_req_i.a.we;
  assign addr_d = obi_req_i.a.addr;
  logic req_q_int, we_q_int;
  logic [ObiCfg.AddrWidth-1:0] addr_q_int;
  logic [ObiCfg.IdWidth-1:0] id_q_int;

  // Flip-flops
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      req_q_int  <= '0;
      id_q_int   <= '0;
      we_q_int   <= '0;
      addr_q_int <= '0;
    end else begin
      req_q_int  <= req_d;
      id_q_int   <= id_d;
      we_q_int   <= we_d;
      addr_q_int <= addr_d;
    end
  end

    // Flip-flops
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      req_q  <= '0;
      id_q   <= '0;
      we_q   <= '0;
      addr_q <= '0;
    end else begin
      req_q  <= req_q_int;
      id_q   <= id_q_int;
      we_q   <= we_q_int;
      addr_q <= addr_q_int;
    end
  end

  

  // // Assign the OBI response data
  // hold in your initials in the form: "JD&JD's ASIC\0"
  logic [4:0] word_addr;
  always_comb begin
    rsp_data = '0;
    rsp_err  = '0;
    word_addr = addr_q[6:2];

    if(req_q) begin
      if(~we_q) begin
        case(word_addr)
          5'd0: rsp_data = 32'h54;
          5'd1: rsp_data = 32'h65;
          5'd2: rsp_data = 32'h6A;
          5'd3: rsp_data = 32'h65;
          5'd4: rsp_data = 32'h73;
          5'd5: rsp_data = 32'h77;
          5'd6: rsp_data = 32'h61;
          5'd7: rsp_data = 32'h72;

          5'd8: rsp_data = 32'h20;
          
          5'd9: rsp_data = 32'h61;
          5'd10: rsp_data = 32'h6E;
          5'd11: rsp_data = 32'h64;
          
          5'd12: rsp_data = 32'h20;

          5'd13: rsp_data = 32'h56;
          5'd14: rsp_data = 32'h69;
          5'd15: rsp_data = 32'h6B;
          5'd16: rsp_data = 32'h61;
          5'd17: rsp_data = 32'h73;
          5'd18: rsp_data = 32'h68;
          5'd19: rsp_data = 32'h27;
          5'd20: rsp_data = 32'h73;
          
          5'd21: rsp_data = 32'h20;
          
          5'd22:  rsp_data = 32'h41;
          5'd23:  rsp_data = 32'h53;
          5'd24:  rsp_data = 32'h49;
          5'd25:  rsp_data = 32'h43;
          
          5'd26:  rsp_data = 32'h00;
          
          default: rsp_data = 32'h0;
        endcase
      end else begin
        rsp_err = '1;
      end
    end
  end

  // Assign the OBI response signals
  // A channel
  assign obi_rsp_o.gnt = obi_req_i.req;
  // R channel
  assign obi_rsp_o.rvalid       = req_q;
  assign obi_rsp_o.r.rdata      = rsp_data;
  assign obi_rsp_o.r.rid        = id_q;
  assign obi_rsp_o.r.err        = rsp_err;
  assign obi_rsp_o.r.r_optional = '0;

endmodule
