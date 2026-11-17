package axi4_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter ID_WIDTH = 4;
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter STRB_WIDTH = DATA_WIDTH/8;
    parameter OUTSTANDING  = 4;

    enum logic [1:0] {
    BURST_FIXED = 2'b00,
    BURST_INCR  = 2'b01,
    BURST_WRAP  = 2'b10
    // 2'b11 is Reserved
    } burst_types;

    enum logic [1:0] {
    RESP_OKAY   = 2'b00,
    RESP_EXOKAY = 2'b01,
    RESP_SLVERR = 2'b10,
    RESP_DECERR = 2'b11
  } axi_resp_e;

     // Transaction
  `include "axi4_transaction.sv"

  // Seqeunces
  `include "axi4_wr_seq.sv"
  `include "axi4_rd_seq.sv"
  `include "axi4_reset_seq.sv"
  `include "axi4_rd_wr_seq.sv"
  `include "axi4_directed_seq.sv"
  
  `include "axi4_main_seq.sv"
  

  //driver
  `include "axi4_driver.sv"
  
  // Monitor
  `include "axi4_monitor.sv"

  // scoreboard
  `include "axi4_scb.sv"
  
  // Agent
  `include "axi4_agent.sv"

  // Environment
  `include "axi4_env.sv"

  // Test
  `include "axi4_test.sv"
  
endpackage