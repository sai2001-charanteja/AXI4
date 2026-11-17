`timescale 1ns/1ps
// =============================================================================
// axi4_if.sv
//
// Full AXI4 (non-Lite) signal bundle as a SystemVerilog interface, with
// modports for a driving master, a responding slave, and a passive monitor.
// Wiring the testbench through one interface (instead of ~30 loose wires)
// is also exactly how you'll want to connect a UVM driver/monitor later.
//
// USER/REGION signals are intentionally omitted to keep the signal list
// focused on the core protocol; add them if your own testbench needs them.
// =============================================================================
interface axi4_if #(
  parameter int ID_WIDTH   = 4,
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
) (
  input logic ACLK
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;
  logic ARESETN;
  // Write address channel
  logic [ID_WIDTH-1:0]   AWID;
  logic [ADDR_WIDTH-1:0] AWADDR;
  logic [7:0]            AWLEN;
  logic [2:0]            AWSIZE;
  logic [1:0]            AWBURST;
  logic                  AWLOCK;
  logic [3:0]            AWCACHE;
  logic [2:0]            AWPROT;
  logic [3:0]            AWQOS;
  logic                  AWVALID;
  logic                  AWREADY;

  // Write data channel
  logic [DATA_WIDTH-1:0] WDATA;
  logic [STRB_WIDTH-1:0] WSTRB;
  logic                  WLAST;
  logic                  WVALID;
  logic                  WREADY;

  // Write response channel
  logic [ID_WIDTH-1:0]   BID;
  logic [1:0]            BRESP;
  logic                  BVALID;
  logic                  BREADY;

  // Read address channel
  logic [ID_WIDTH-1:0]   ARID;
  logic [ADDR_WIDTH-1:0] ARADDR;
  logic [7:0]            ARLEN;
  logic [2:0]            ARSIZE;
  logic [1:0]            ARBURST;
  logic                  ARLOCK;
  logic [3:0]            ARCACHE;
  logic [2:0]            ARPROT;
  logic [3:0]            ARQOS;
  logic                  ARVALID;
  logic                  ARREADY;

  // Read data channel
  logic [ID_WIDTH-1:0]   RID;
  logic [DATA_WIDTH-1:0] RDATA;
  logic [1:0]            RRESP;
  logic                  RLAST;
  logic                  RVALID;
  logic                  RREADY;

  // ---------------------------------------------------------------------
  // Modports
  // ---------------------------------------------------------------------
  modport master (
    input  ACLK, ARESETN,
    output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWVALID,
    input  AWREADY,
    output WDATA, WSTRB, WLAST, WVALID,
    input  WREADY,
    input  BID, BRESP, BVALID,
    output BREADY,
    output ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARVALID,
    input  ARREADY,
    input  RID, RDATA, RRESP, RLAST, RVALID,
    output RREADY
  );

  modport slave (
    input  ACLK, ARESETN,
    input  AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWVALID,
    output AWREADY,
    input  WDATA, WSTRB, WLAST, WVALID,
    output WREADY,
    output BID, BRESP, BVALID,
    input  BREADY,
    input  ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARVALID,
    output ARREADY,
    output RID, RDATA, RRESP, RLAST, RVALID,
    input  RREADY
  );

  modport monitor (
    input ACLK, ARESETN,
    input AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWVALID, AWREADY,
    input WDATA, WSTRB, WLAST, WVALID, WREADY,
    input BID, BRESP, BVALID, BREADY,
    input ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARVALID, ARREADY,
    input RID, RDATA, RRESP, RLAST, RVALID, RREADY
  );

endinterface
