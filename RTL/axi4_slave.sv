`timescale 1ns/1ps
// =============================================================================
// axi4_slave.sv
//
// A memory-mapped AXI4 slave built specifically to be a rich, non-trivial DUT
// for verification practice. It is intentionally NOT area/timing-optimized --
// it is a teaching/lab-grade design meant to exercise every protocol corner a
// hiring manager might ask about, so a UVM environment built against it has
// real things to find and check.
//
// Address map (byte addresses, defaults with ADDR_WIDTH=32):
//   0x0000_0000 - 0x0000_3EFF  FAST region       (low-latency memory)
//   0x0000_3F00 - 0x0000_3FFF  FAST_PROT region   (same array, privileged-only:
//                               AxPROT[0]=1 "unprivileged" access -> SLVERR)
//   0x0000_4000 - 0x0000_7FFF  unmapped hole      -> SLVERR
//   0x0000_8000 - 0x0000_BFFF  SLOW region        (high-latency "peripheral")
//   anything else               unmapped          -> SLVERR
//
// Features implemented (see README.md for the verification plan these map to):
//   - Full AXI4 5-channel signaling, all listed AxCACHE/AxPROT/AxQOS signals
//   - FIXED / INCR / WRAP bursts with correct wrap-boundary math
//   - Narrow / unaligned transfers via WSTRB byte-lane writes
//   - Multiple outstanding transactions (OUTSTANDING per channel), with
//     genuine out-of-order completion across different IDs, driven by the
//     FAST vs SLOW region latency difference
//   - In-order completion guarantee for repeated use of the same ID (a new
//     AW/AR with an ID already outstanding is simply not accepted yet)
//   - QoS-aware arbitration: among responses/read-bursts ready to go out in
//     the same cycle, the highest AxQOS is served first
//   - Exclusive access (AWLOCK/ARLOCK): single-beat only (see README) with a
//     one-entry global monitor, EXOKAY/OKAY handling, and monitor invalidation
//     on any write that touches the reserved address
//   - SLVERR generation for unmapped addresses and privilege violations
//   - Explicit reset handling: all VALID outputs held low while ARESETN is low
//
// IMPLEMENTATION NOTE ON STORAGE: outstanding-transaction state is kept as
// several parallel per-field arrays (wr_valid[i], wr_id[i], wr_addr[i], ...)
// rather than one array of a packed struct (wr_table[i].id). Functionally
// these are identical; the flattened form is used because at least one
// widely-used open-source simulator (Icarus Verilog, used for the included
// self-check testbench) has an elaboration bug with a variable index into
// an unpacked array of packed structs. Flat parallel arrays are also simply
// the more universally tool-portable style for synthesizable RTL.
// =============================================================================
import axi4_RTL_pkg::*;

// NOTE ON PORT STYLE: this module uses a flat AXI4 port list rather than a
// SystemVerilog interface port. That's deliberate, not a workaround forced
// by any one tool: most synthesis flows (and plenty of simulators) have
// incomplete support for interface-typed ports on synthesizable RTL, so
// real AXI IP is almost always written this way. axi4_if.sv still exists
// and is the recommended way to wire this DUT up from a testbench or a
// UVM environment -- see axi4_slave_tb.sv for exactly that pattern.
module axi4_slave #(
  parameter int ID_WIDTH     = 4,
  parameter int ADDR_WIDTH   = 32,
  parameter int DATA_WIDTH   = 32,
  parameter int OUTSTANDING  = 4,   // max outstanding transactions, per channel (power of 2)
  parameter int SLOW_LATENCY = 6    // extra cycles added for SLOW-region completions
) (
  input  logic                  ACLK,
  input  logic                  ARESETN,

  input  logic [ID_WIDTH-1:0]   AWID,
  input  logic [ADDR_WIDTH-1:0] AWADDR,
  input  logic [7:0]            AWLEN,
  input  logic [2:0]            AWSIZE,
  input  logic [1:0]            AWBURST,
  input  logic                  AWLOCK,
  input  logic [3:0]            AWCACHE,
  input  logic [2:0]            AWPROT,
  input  logic [3:0]            AWQOS,
  input  logic                  AWVALID,
  output logic                  AWREADY,

  input  logic [DATA_WIDTH-1:0]   WDATA,
  input  logic [DATA_WIDTH/8-1:0] WSTRB,
  input  logic                    WLAST,
  input  logic                    WVALID,
  output logic                    WREADY,

  output logic [ID_WIDTH-1:0]   BID,
  output logic [1:0]            BRESP,
  output logic                  BVALID,
  input  logic                  BREADY,

  input  logic [ID_WIDTH-1:0]   ARID,
  input  logic [ADDR_WIDTH-1:0] ARADDR,
  input  logic [7:0]            ARLEN,
  input  logic [2:0]            ARSIZE,
  input  logic [1:0]            ARBURST,
  input  logic                  ARLOCK,
  input  logic [3:0]            ARCACHE,
  input  logic [2:0]            ARPROT,
  input  logic [3:0]            ARQOS,
  input  logic                  ARVALID,
  output logic                  ARREADY,

  output logic [ID_WIDTH-1:0]   RID,
  output logic [DATA_WIDTH-1:0] RDATA,
  output logic [1:0]            RRESP,
  output logic                  RLAST,
  output logic                  RVALID,
  input  logic                  RREADY
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;
  localparam int WORD_SHIFT = $clog2(STRB_WIDTH);
  localparam int OSIDX_W    = (OUTSTANDING > 1) ? $clog2(OUTSTANDING) : 1;

  // Address map and get_region() live in axi4_RTL_pkg (imported above) so the
  // DUT and the testbench share exactly one definition.

  // ---------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] fast_mem [0:(FAST_SIZE>>WORD_SHIFT)-1];
  logic [DATA_WIDTH-1:0] slow_mem [0:(SLOW_SIZE>>WORD_SHIFT)-1];

  initial begin
    //for (int i = 0; i < (FAST_SIZE>>WORD_SHIFT); i++) fast_mem[i] = '0;
    //for (int i = 0; i < (SLOW_SIZE>>WORD_SHIFT); i++) slow_mem[i] = '0;
  end

  // Write-side outstanding-transaction table (see IMPLEMENTATION NOTE above
  // for why this is flattened into parallel arrays instead of one struct array)
  logic                  wr_valid     [OUTSTANDING];
  logic [ID_WIDTH-1:0]   wr_id        [OUTSTANDING];
  logic [ADDR_WIDTH-1:0] wr_addr      [OUTSTANDING];
  logic [7:0]            wr_len       [OUTSTANDING];
  logic [2:0]            wr_size      [OUTSTANDING];
  logic [1:0]            wr_burst     [OUTSTANDING];
  logic                  wr_lock      [OUTSTANDING];
  logic [3:0]            wr_qos       [OUTSTANDING];
  logic                  wr_prot_unpriv[OUTSTANDING];
  logic [7:0]            wr_beat_cnt  [OUTSTANDING];
  logic                  wr_data_done [OUTSTANDING];
  logic                  wr_resp_err  [OUTSTANDING];
  logic                  wr_excl_fail [OUTSTANDING];
  logic [15:0]           wr_seq       [OUTSTANDING];
  logic [3:0]            wr_latency   [OUTSTANDING];
  logic [15:0]           wr_seq_ctr;

  // Read-side outstanding-transaction table
  logic                  rd_valid      [OUTSTANDING];
  logic [ID_WIDTH-1:0]   rd_id         [OUTSTANDING];
  logic [ADDR_WIDTH-1:0] rd_addr       [OUTSTANDING];
  logic [7:0]            rd_len        [OUTSTANDING];
  logic [2:0]            rd_size       [OUTSTANDING];
  logic [1:0]            rd_burst      [OUTSTANDING];
  logic                  rd_lock       [OUTSTANDING];
  logic [3:0]            rd_qos        [OUTSTANDING];
  logic                  rd_prot_unpriv[OUTSTANDING];
  logic [3:0]            rd_latency    [OUTSTANDING];

  // Single-entry exclusive access monitor (single-beat exclusive accesses only)
  logic                  mon_valid;
  logic [ID_WIDTH-1:0]   mon_id;
  logic [ADDR_WIDTH-1:0] mon_addr;

  // Read-burst streaming state (only one ID streams on the shared R channel at a time)
  logic                  rd_streaming;
  logic [OSIDX_W-1:0]    rd_stream_idx;
  logic [7:0]            rd_stream_beat;

  // ---------------------------------------------------------------------
  // Combinational selection / arbitration logic
  // ---------------------------------------------------------------------
  logic               aw_slot_free, ar_slot_free, aw_id_dup, ar_id_dup;
  logic [OSIDX_W-1:0] aw_free_idx, ar_free_idx;

  logic               w_target_valid;
  logic [OSIDX_W-1:0] w_target_idx;
  logic [15:0]        w_best_seq;

  logic               b_grant_valid;
  logic [OSIDX_W-1:0] b_grant_idx;

  logic               r_start_valid;
  logic [OSIDX_W-1:0] r_start_idx;

  logic               eff_streaming_valid;
  logic [OSIDX_W-1:0] eff_idx;
  logic [7:0]         eff_beat;

  logic [ADDR_WIDTH-1:0] addr_beat_r, addr_beat_w;
  axi_region_e            region_r, region_w;
  logic                   err_r, err_w;
  logic                   excl_ok_w;
  integer                 word_idx_r, word_idx_w;

  always_comb begin
    // --- free-slot / duplicate-ID search for AW and AR -------------------
    aw_slot_free = 1'b0; aw_free_idx = '0;
    for (int i = 0; i < OUTSTANDING; i++)
      if (!wr_valid[i] && !aw_slot_free) begin
        aw_slot_free = 1'b1; aw_free_idx = i;
      end
    aw_id_dup = 1'b0;
    for (int i = 0; i < OUTSTANDING; i++)
      if (wr_valid[i] && wr_id[i] == AWID) aw_id_dup = 1'b1;

    ar_slot_free = 1'b0; ar_free_idx = '0;
    for (int i = 0; i < OUTSTANDING; i++)
      if (!rd_valid[i] && !ar_slot_free) begin
        ar_slot_free = 1'b1; ar_free_idx = i;
      end
    ar_id_dup = 1'b0;
    for (int i = 0; i < OUTSTANDING; i++)
      if (rd_valid[i] && rd_id[i] == ARID) ar_id_dup = 1'b1;

    // --- pick which outstanding write consumes the next W beat ----------
    // (write data is matched to addresses strictly in AW issue order, per spec)
    w_target_valid = 1'b0; w_target_idx = '0; w_best_seq = 16'hFFFF;
    for (int i = 0; i < OUTSTANDING; i++)
      if (wr_valid[i] && !wr_data_done[i])
        if (!w_target_valid || wr_seq[i] < w_best_seq) begin
          w_target_valid = 1'b1; w_target_idx = i; w_best_seq = wr_seq[i];
        end

    // --- pick which completed write gets to drive B this cycle ----------
    // (highest AWQOS first; lowest table slot breaks ties)
    b_grant_valid = 1'b0; b_grant_idx = '0;
    for (int i = 0; i < OUTSTANDING; i++)
      if (wr_valid[i] && wr_data_done[i] && wr_latency[i] == 4'd0)
        if (!b_grant_valid || wr_qos[i] > wr_qos[b_grant_idx])
          begin b_grant_valid = 1'b1; b_grant_idx = i; end

    // --- pick which read burst starts streaming next (if none active) ---
    r_start_valid = 1'b0; r_start_idx = '0;
    for (int i = 0; i < OUTSTANDING; i++)
      if (rd_valid[i] && rd_latency[i] == 4'd0)
        if (!r_start_valid || rd_qos[i] > rd_qos[r_start_idx])
          begin r_start_valid = 1'b1; r_start_idx = i; end

    eff_streaming_valid = rd_streaming ? 1'b1          : r_start_valid;
    eff_idx              = rd_streaming ? rd_stream_idx : r_start_idx;
    eff_beat             = rd_streaming ? rd_stream_beat : 8'd0;

    // --- read beat address / decode --------------------------------------
    addr_beat_r = axi4_RTL_pkg::axi_beat_addr(rd_addr[eff_idx], rd_size[eff_idx],
                                 rd_burst[eff_idx], rd_len[eff_idx], eff_beat);
    region_r    = axi4_RTL_pkg::get_region(addr_beat_r);
    err_r       = (region_r == REGION_ERR) ||
                  (region_r == REGION_FAST_PROT && rd_prot_unpriv[eff_idx]);
    word_idx_r  = (region_r == REGION_SLOW) ? ((addr_beat_r - SLOW_BASE) >> WORD_SHIFT)
                                             : ((addr_beat_r - FAST_BASE) >> WORD_SHIFT);

    // --- write beat address / decode --------------------------------------
    addr_beat_w = axi4_RTL_pkg::axi_beat_addr(wr_addr[w_target_idx], wr_size[w_target_idx],
                                 wr_burst[w_target_idx], wr_len[w_target_idx],
                                 wr_beat_cnt[w_target_idx]);
    region_w    = axi4_RTL_pkg::get_region(addr_beat_w);
    err_w       = (region_w == REGION_ERR) ||
                  (region_w == REGION_FAST_PROT && wr_prot_unpriv[w_target_idx]);
    word_idx_w  = (region_w == REGION_SLOW) ? ((addr_beat_w - SLOW_BASE) >> WORD_SHIFT)
                                             : ((addr_beat_w - FAST_BASE) >> WORD_SHIFT);
    excl_ok_w   = !wr_lock[w_target_idx] ||
                  (mon_valid && mon_id == wr_id[w_target_idx] && mon_addr == addr_beat_w);

    // --- output port values ------------------------------------------------
    // (assigned procedurally here, rather than via continuous `assign`,
    // for consistency with the rest of this combinational block)
    AWREADY = ARESETN && aw_slot_free && !aw_id_dup;
    ARREADY = ARESETN && ar_slot_free && !ar_id_dup;
    WREADY  = ARESETN && w_target_valid;

    BVALID  = ARESETN && b_grant_valid;
    BID     = wr_id[b_grant_idx];
    BRESP   = wr_resp_err[b_grant_idx]                                ? RESP_SLVERR :
              (wr_lock[b_grant_idx] && wr_excl_fail[b_grant_idx])     ? RESP_OKAY   :
              (wr_lock[b_grant_idx])                                  ? RESP_EXOKAY :
                                                                          RESP_OKAY;

    RVALID = ARESETN && eff_streaming_valid;
    RID    = rd_id[eff_idx];
    RDATA  = err_r ? '0 : (region_r == REGION_SLOW ? slow_mem[word_idx_r] : fast_mem[word_idx_r]);
    RRESP  = err_r ? RESP_SLVERR : (rd_lock[eff_idx] ? RESP_EXOKAY : RESP_OKAY);
    RLAST  = (eff_beat == rd_len[eff_idx]);
  end

  // Any successful write whose beat address matches the current exclusive
  // reservation invalidates it -- this covers both "the matching exclusive
  // write succeeded" and "some other write clobbered the reserved location".
  logic mon_should_clear;
  assign mon_should_clear = WVALID && WREADY && !err_w &&
                             mon_valid && (mon_addr == addr_beat_w);

  // ---------------------------------------------------------------------
  // Exclusive-access monitor (single always_ff so it has exactly one driver)
  // ---------------------------------------------------------------------
  always_ff @(posedge ACLK) begin
    if (!ARESETN) begin
      mon_valid <= 1'b0; mon_id <= '0; mon_addr <= '0;
    end else if (ARVALID && ARREADY && ARLOCK) begin
      mon_valid <= 1'b1; mon_id <= ARID; mon_addr <= ARADDR;
    end else if (mon_should_clear) begin
      mon_valid <= 1'b0;
    end
  end

  // ---------------------------------------------------------------------
  // Write table: AW accept, W-beat consume, B retire, latency countdown
  // ---------------------------------------------------------------------
  always_ff @(posedge ACLK) begin
    if (!ARESETN) begin
      for (int i = 0; i < OUTSTANDING; i++) begin
        wr_valid[i] <= 1'b0; wr_id[i] <= '0; wr_addr[i] <= '0; wr_len[i] <= '0;
        wr_size[i] <= '0; wr_burst[i] <= '0; wr_lock[i] <= '0; wr_qos[i] <= '0;
        wr_prot_unpriv[i] <= '0; wr_beat_cnt[i] <= '0; wr_data_done[i] <= '0;
        wr_resp_err[i] <= '0; wr_excl_fail[i] <= '0; wr_seq[i] <= '0; wr_latency[i] <= '0;
      end
      wr_seq_ctr <= 16'd0;
      for (int i = 0; i < (FAST_SIZE>>WORD_SHIFT); i++) fast_mem[i] = '0;
      for (int i = 0; i < (SLOW_SIZE>>WORD_SHIFT); i++) slow_mem[i] = '0;

    end else begin
      for (int i = 0; i < OUTSTANDING; i++)
        if (wr_valid[i] && wr_data_done[i] && wr_latency[i] != 4'd0)
          wr_latency[i] <= wr_latency[i] - 4'd1;

      if (AWVALID && AWREADY) begin
        wr_valid[aw_free_idx]        <= 1'b1;
        wr_id[aw_free_idx]           <= AWID;
        wr_addr[aw_free_idx]         <= AWADDR;
        wr_len[aw_free_idx]          <= AWLEN;
        wr_size[aw_free_idx]         <= AWSIZE;
        wr_burst[aw_free_idx]        <= AWBURST;
        wr_lock[aw_free_idx]         <= AWLOCK;
        wr_qos[aw_free_idx]          <= AWQOS;
        wr_prot_unpriv[aw_free_idx]  <= AWPROT[0];
        wr_beat_cnt[aw_free_idx]     <= 8'd0;
        wr_data_done[aw_free_idx]    <= 1'b0;
        wr_resp_err[aw_free_idx]     <= 1'b0;
        wr_excl_fail[aw_free_idx]    <= 1'b0;
        wr_seq[aw_free_idx]          <= wr_seq_ctr;
        wr_latency[aw_free_idx]      <= 4'd0;
        wr_seq_ctr <= wr_seq_ctr + 16'd1;
      end

      if (WVALID && WREADY) begin
        if (err_w) begin
          wr_resp_err[w_target_idx] <= 1'b1;
        end else if (excl_ok_w) begin
          if (region_w == REGION_SLOW) begin
            for (int b = 0; b < STRB_WIDTH; b++)
              if (WSTRB[b]) slow_mem[word_idx_w][8*b +: 8] <= WDATA[8*b +: 8];
          end else begin
            for (int b = 0; b < STRB_WIDTH; b++)
              if (WSTRB[b]) fast_mem[word_idx_w][8*b +: 8] <= WDATA[8*b +: 8];
          end
        end else begin
          wr_excl_fail[w_target_idx] <= 1'b1;
        end

        wr_beat_cnt[w_target_idx] <= wr_beat_cnt[w_target_idx] + 8'd1;
        if (WLAST) begin
          wr_data_done[w_target_idx] <= 1'b1;
          wr_latency[w_target_idx]   <=
            (axi4_RTL_pkg::get_region(wr_addr[w_target_idx]) == REGION_SLOW) ? SLOW_LATENCY[3:0] : 4'd0;
        end
      end

      if (BVALID && BREADY) begin
        wr_valid[b_grant_idx] <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------
  // Read table: AR accept, latency countdown, R streaming state machine
  // ---------------------------------------------------------------------
  always_ff @(posedge ACLK) begin
    if (!ARESETN) begin
      for (int i = 0; i < OUTSTANDING; i++) begin
        rd_valid[i] <= 1'b0; rd_id[i] <= '0; rd_addr[i] <= '0; rd_len[i] <= '0;
        rd_size[i] <= '0; rd_burst[i] <= '0; rd_lock[i] <= '0; rd_qos[i] <= '0;
        rd_prot_unpriv[i] <= '0; rd_latency[i] <= '0;
      end
      rd_streaming   <= 1'b0;
      rd_stream_idx  <= '0;
      rd_stream_beat <= 8'd0;
    end else begin
      for (int i = 0; i < OUTSTANDING; i++)
        if (rd_valid[i] && rd_latency[i] != 4'd0)
          rd_latency[i] <= rd_latency[i] - 4'd1;

      if (ARVALID && ARREADY) begin
        rd_valid[ar_free_idx]        <= 1'b1;
        rd_id[ar_free_idx]           <= ARID;
        rd_addr[ar_free_idx]         <= ARADDR;
        rd_len[ar_free_idx]          <= ARLEN;
        rd_size[ar_free_idx]         <= ARSIZE;
        rd_burst[ar_free_idx]        <= ARBURST;
        rd_lock[ar_free_idx]         <= ARLOCK;
        rd_qos[ar_free_idx]          <= ARQOS;
        rd_prot_unpriv[ar_free_idx]  <= ARPROT[0];
        rd_latency[ar_free_idx]      <=
          (axi4_RTL_pkg::get_region(ARADDR) == REGION_SLOW) ? SLOW_LATENCY[3:0] : 4'd0;
      end

      if (RVALID && RREADY) begin
        if (!rd_streaming) begin
          if (RLAST) begin
            rd_valid[eff_idx] <= 1'b0; // single-beat burst finishes immediately
          end else begin
            rd_streaming   <= 1'b1;
            rd_stream_idx  <= eff_idx;
            rd_stream_beat <= 8'd1;
          end
        end else begin
          if (RLAST) begin
            rd_streaming <= 1'b0;
            rd_valid[rd_stream_idx] <= 1'b0;
          end else begin
            rd_stream_beat <= rd_stream_beat + 8'd1;
          end
        end
      end
    end
  end

endmodule
