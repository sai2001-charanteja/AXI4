// =============================================================================
// axi4_slave_tb.sv
//
// A small, self-checking, plain-SystemVerilog testbench (no UVM) whose only
// job is to prove axi4_slave.sv is functionally correct BEFORE you invest
// time building a full UVM environment around it. It doubles as a worked
// example of how to drive/monitor axi4_if.
//
// It is deliberately written as blocking-assignment "bus-functional" code,
// not a synthesizable model or a UVM-quality BFM -- that layered, reusable
// structure (driver/monitor/sequencer/scoreboard) is exactly what you should
// build next, using this as your reference for what "correct" looks like.
//
// Run with:
//   iverilog -g2012 -o sim axi4_pkg.sv axi4_if.sv axi4_slave.sv axi4_slave_tb.sv
//   vvp sim
// =============================================================================
`timescale 1ns/1ps

module axi4_slave_tb;
  import axi4_RTL_pkg::*;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  
  import axi4_pkg::*;
  // ---------------------------------------------------------------------
  // Clock / reset
  // ---------------------------------------------------------------------
  localparam time CLK_PERIOD = 10; // ns, matches the #5 half-period below
  logic clk = 0;
  always #5 clk = ~clk; // 100MHz

  axi4_if #(.ID_WIDTH(4), .ADDR_WIDTH(32), .DATA_WIDTH(32)) axi (.ACLK(clk) );

  // axi4_slave takes a flat port list (see the note in axi4_slave.sv); we
  // wire each port to the matching signal on the axi4_if instance by
  // hierarchical reference. A simulator with full interface-port support
  // would let you write this as a single `.axi(axi.slave)` connection.
  axi4_slave #(
    .ID_WIDTH    (4),
    .ADDR_WIDTH  (32),
    .DATA_WIDTH  (32),
    .OUTSTANDING (4),
    .SLOW_LATENCY(6)
  ) dut (
    .ACLK(clk), .ARESETN(axi.ARESETN),
    .AWID(axi.AWID), .AWADDR(axi.AWADDR), .AWLEN(axi.AWLEN), .AWSIZE(axi.AWSIZE),
    .AWBURST(axi.AWBURST), .AWLOCK(axi.AWLOCK), .AWCACHE(axi.AWCACHE), .AWPROT(axi.AWPROT),
    .AWQOS(axi.AWQOS), .AWVALID(axi.AWVALID), .AWREADY(axi.AWREADY),
    .WDATA(axi.WDATA), .WSTRB(axi.WSTRB), .WLAST(axi.WLAST), .WVALID(axi.WVALID), .WREADY(axi.WREADY),
    .BID(axi.BID), .BRESP(axi.BRESP), .BVALID(axi.BVALID), .BREADY(axi.BREADY),
    .ARID(axi.ARID), .ARADDR(axi.ARADDR), .ARLEN(axi.ARLEN), .ARSIZE(axi.ARSIZE),
    .ARBURST(axi.ARBURST), .ARLOCK(axi.ARLOCK), .ARCACHE(axi.ARCACHE), .ARPROT(axi.ARPROT),
    .ARQOS(axi.ARQOS), .ARVALID(axi.ARVALID), .ARREADY(axi.ARREADY),
    .RID(axi.RID), .RDATA(axi.RDATA), .RRESP(axi.RRESP), .RLAST(axi.RLAST),
    .RVALID(axi.RVALID), .RREADY(axi.RREADY)
  );
   axi4_protocol_checker #(
    .ID_WIDTH    (4),
    .ADDR_WIDTH  (32),
    .DATA_WIDTH  (32)
   ) axi4_checker (
  .axi(axi.monitor)
);
  initial begin
    uvm_config_db#(virtual axi4_if)::set(null,"","vif",axi);
    uvm_root::get().set_report_default_file("uvm.log");
    run_test("axi4_test");
  end

endmodule
