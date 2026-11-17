`timescale 1ns/1ps
// =============================================================================
// axi4_pkg.sv
//
// Shared types, response/burst encodings, and address helper functions for the
// axi4_slave lab DUT and its testbench. Keeping these in a package means the
// DUT and any verification code (this testbench, or a UVM env you build later)
// agree on the same encodings and burst-address math instead of duplicating it.
// =============================================================================
package axi4_RTL_pkg;

 
  // ---------------------------------------------------------------------
  // AXI4 encodings (from the AMBA AXI protocol specification)
  // ---------------------------------------------------------------------
  typedef enum logic [1:0] {
    BURST_FIXED = 2'b00,
    BURST_INCR  = 2'b01,
    BURST_WRAP  = 2'b10
    // 2'b11 is Reserved
  } axi_burst_e;

  typedef enum logic [1:0] {
    RESP_OKAY   = 2'b00,
    RESP_EXOKAY = 2'b01,
    RESP_SLVERR = 2'b10,
    RESP_DECERR = 2'b11
  } axi_resp_e;

  // Region a decoded address falls into inside axi4_slave's own address map.
  typedef enum logic [1:0] {
    REGION_FAST,      // low-latency memory
    REGION_FAST_PROT, // same array as FAST, but privileged-access-only
    REGION_SLOW,      // high-latency memory (models a slow peripheral/DRAM)
    REGION_ERR        // unmapped hole inside this slave's decode window
  } axi_region_e;

  // ---------------------------------------------------------------------
  // axi4_slave's address map. Defined once here so the DUT and any
  // testbench/verification code reference the same numbers instead of
  // two copies that can silently drift apart.
  // ---------------------------------------------------------------------
  localparam logic [31:0] FAST_BASE      = 32'h0000_0000;
  localparam logic [31:0] FAST_SIZE      = 32'h0000_4000;                       // 16KB
  localparam logic [31:0] FAST_TOP       = FAST_BASE + FAST_SIZE - 1;           // 0x3FFF
  localparam logic [31:0] FAST_PROT_SIZE = 32'h0000_0100;                       // top 256B, privileged-only
  localparam logic [31:0] FAST_PROT_BASE = FAST_TOP - FAST_PROT_SIZE + 1;       // 0x3F00

  localparam logic [31:0] HOLE_BASE = FAST_TOP + 1;                             // 0x4000
  localparam logic [31:0] HOLE_SIZE = 32'h0000_4000;                            // 16KB, unmapped -> SLVERR
  localparam logic [31:0] HOLE_TOP  = HOLE_BASE + HOLE_SIZE - 1;                // 0x7FFF

  localparam logic [31:0] SLOW_BASE = HOLE_TOP + 1;                             // 0x8000
  localparam logic [31:0] SLOW_SIZE = 32'h0000_4000;                            // 16KB
  localparam logic [31:0] SLOW_TOP  = SLOW_BASE + SLOW_SIZE - 1;                // 0xBFFF

  // ---------------------------------------------------------------------
  // Outstanding-transaction bookkeeping used by axi4_slave's write and
  // read tables. Some fields only matter for one of the two channels
  // (e.g. `seq` is only used to order write-data consumption) but sharing
  // one struct keeps the DUT code shorter.
  // ---------------------------------------------------------------------
  typedef struct packed {
    logic        valid;
    logic [3:0]  id;
    logic [31:0] addr;      // burst start address
    logic [7:0]  len;       // AxLEN  (burst_length = len + 1)
    logic [2:0]  size;      // AxSIZE (bytes_per_beat = 1 << size)
    logic [1:0]  burst;     // AxBURST
    logic        lock;      // AxLOCK (exclusive access request)
    logic [3:0]  qos;       // AxQOS
    logic        prot_unpriv; // AxPROT[0] (1 = unprivileged access)
    logic [7:0]  beat_cnt;  // beats produced/consumed so far
    logic        data_done; // (write only) all W beats received
    logic        resp_err;  // sticky: any beat hit an unmapped/protected addr
    logic        excl_fail; // (write only) exclusive write did not match monitor
    logic [15:0] seq;       // (write only) issue order, used for W-data routing
    logic [3:0]  latency;   // cycles left before response/read-data may start
  } axi_xact_t;

  // ---------------------------------------------------------------------
  // Per-beat address generator for FIXED / INCR / WRAP bursts.
  // `beat_idx` is 0-based (0 = the address of the first beat).
  // ---------------------------------------------------------------------
  function automatic logic [31:0] axi_beat_addr(
    input logic [31:0] start_addr,
    input logic [2:0]  size,
    input logic [1:0]  burst,
    input logic [7:0]  len,
    input logic [7:0]  beat_idx
  );
    logic [31:0] bytes_per_beat;
    logic [31:0] wrap_bytes;
    logic [31:0] wrap_base;
    logic [31:0] lin_addr;
    begin
      bytes_per_beat = 32'h1 << size;
      case (burst)
        BURST_FIXED: axi_beat_addr = start_addr;
        BURST_WRAP: begin
          wrap_bytes = bytes_per_beat * (len + 1); // total bytes in the wrap window
          wrap_base  = (start_addr / wrap_bytes) * wrap_bytes;
          lin_addr   = start_addr + beat_idx * bytes_per_beat;
          if (lin_addr >= wrap_base + wrap_bytes)
            axi_beat_addr = wrap_base + (lin_addr - (wrap_base + wrap_bytes));
          else
            axi_beat_addr = lin_addr;
        end
        default: /* BURST_INCR */ axi_beat_addr = start_addr + beat_idx * bytes_per_beat;
      endcase
    end
  endfunction

  // Decode a byte address into one of the regions above. Shared by the DUT
  // (to decide how to service a beat) and by the testbench (to pick target
  // addresses for each scenario without hardcoding numbers twice).
  function automatic axi_region_e get_region(input logic [31:0] addr);
    if (addr >= FAST_PROT_BASE && addr <= FAST_TOP)      get_region = REGION_FAST_PROT;
    else if (addr < FAST_PROT_BASE)                      get_region = REGION_FAST;
    else if (addr >= SLOW_BASE && addr <= SLOW_TOP)       get_region = REGION_SLOW;
    else                                                  get_region = REGION_ERR;
  endfunction

 
  
endpackage
