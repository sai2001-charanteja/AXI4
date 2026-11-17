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

  // ---------------------------------------------------------------------
  // Clock / reset
  // ---------------------------------------------------------------------
  localparam time CLK_PERIOD = 10; // ns, matches the #5 half-period below
  logic clk = 0;
  logic rstn = 0;
  always #5 clk = ~clk; // 100MHz

  axi4_if #(.ID_WIDTH(4), .ADDR_WIDTH(32), .DATA_WIDTH(32)) axi (.ACLK(clk));

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
    .ACLK(clk), .ARESETN(rstn),
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

  // ---------------------------------------------------------------------
  // Pass/fail bookkeeping
  // ---------------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;

  task automatic check(input logic cond, input string msg);
    if (cond) begin
      pass_cnt++;
      $display("[%0t] PASS: %s", $time, msg);
    end else begin
      fail_cnt++;
      $display("[%0t] FAIL: %s", $time, msg);
    end
  endtask

  // ---------------------------------------------------------------------
  // Passive monitor: records every completed write response and every
  // completed read burst, timestamped, queryable by ID. This is what lets
  // the out-of-order tests below check completion ORDER, not just values.
  // ---------------------------------------------------------------------
  // Icarus Verilog (used for this self-check) doesn't support unpacked
  // structs holding dynamic members, so the event log is kept as parallel
  // scalar queues instead of a queue-of-structs. A full SV simulator would
  // let you tidy this into a single struct queue.
  logic [3:0] b_id_q[$];
  logic [1:0] b_resp_q[$];
  time        b_time_q[$];

  logic [3:0] r_id_q[$];
  logic [1:0] r_resp_q[$];
  time        r_time_q[$];

  // master side is always ready to accept responses/data in this testbench
  assign axi.BREADY = 1'b1;
  assign axi.RREADY = 1'b1;

  always @(posedge clk) begin
    if (rstn && axi.BVALID && axi.BREADY) begin
      b_id_q.push_back(axi.BID);
      b_resp_q.push_back(axi.BRESP);
      b_time_q.push_back($time);
    end
    if (rstn && axi.RVALID && axi.RREADY && axi.RLAST) begin
      // Only the ID/response/timestamp of the LAST beat is logged here;
      // do_read() captures per-beat data itself for the tests that check it.
      r_id_q.push_back(axi.RID);
      r_resp_q.push_back(axi.RRESP);
      r_time_q.push_back($time);
    end
  end

  task automatic pop_bresp(input logic [3:0] id, output logic [1:0] resp, output time t);
    int  idx;
    logic found;
    found = 1'b0;
    while (!found) begin
      for (idx = 0; idx < b_id_q.size(); idx++) begin
        if (!found && b_id_q[idx] == id) begin
          resp  = b_resp_q[idx];
          t     = b_time_q[idx];
          b_id_q.delete(idx);
          b_resp_q.delete(idx);
          b_time_q.delete(idx);
          found = 1'b1;
        end
      end
      if (!found) @(posedge clk);
    end
  endtask

  task automatic pop_rresp_meta(input logic [3:0] id, output logic [1:0] resp, output time t);
    int  idx;
    logic found;
    found = 1'b0;
    while (!found) begin
      for (idx = 0; idx < r_id_q.size(); idx++) begin
        if (!found && r_id_q[idx] == id) begin
          resp  = r_resp_q[idx];
          t     = r_time_q[idx];
          r_id_q.delete(idx);
          r_resp_q.delete(idx);
          r_time_q.delete(idx);
          found = 1'b1;
        end
      end
      if (!found) @(posedge clk);
    end
  endtask

  // ---------------------------------------------------------------------
  // Driver tasks. All new stimulus is driven right after a NEGEDGE (a full
  // half-cycle away from the posedge the DUT's sequential logic uses). A
  // #0 after asserting VALID lets the DUT's combinational READY settle
  // before the first check (blocking assignment doesn't itself guarantee
  // dependent combinational logic has re-evaluated in the same instant).
  // READY is checked immediately after driving, or on later negedges if
  // not yet ready. Symmetrically, once a posedge has been consumed for a
  // transfer, VALID is only cleared after stepping forward to the NEXT
  // negedge -- never in the same instant as that posedge -- since either
  // direction of same-edge read/write against the DUT's own sequential
  // update is a race (and for AW/AR specifically, losing that race makes
  // the DUT see the just-accepted entry as a *new* conflicting request
  // with an already-outstanding ID, hanging the driver forever).
  // ---------------------------------------------------------------------
  task automatic issue_write(
    input logic [3:0]  id, input logic [31:0] addr, input logic [7:0] len,
    input logic [2:0]  size, input logic [1:0] burst, input logic lock,
    input logic [3:0]  qos, input logic [2:0] prot,
    input logic [31:0] data0, input logic [3:0] wstrb
  );
    logic ready_now;
    int   b;
    @(negedge clk);
    axi.AWID    = id;     axi.AWADDR = addr;  axi.AWLEN  = len;
    axi.AWSIZE  = size;   axi.AWBURST = burst; axi.AWLOCK = lock;
    axi.AWCACHE = 4'h0;   axi.AWPROT  = prot;  axi.AWQOS  = qos;
    axi.AWVALID = 1'b1;
    #0;
    ready_now = axi.AWREADY;
    while (!ready_now) begin
      @(negedge clk);
      ready_now = axi.AWREADY;
    end
    @(posedge clk);   // AW transfer registers in the DUT here
    @(negedge clk);   // safe point, a half-cycle clear of that edge
    axi.AWVALID = 1'b0;

    for (b = 0; b <= len; b++) begin
      axi.WDATA  = data0 + b;
      axi.WSTRB  = wstrb;
      axi.WLAST  = (b == len);
      axi.WVALID = 1'b1;
      #0;
      ready_now = axi.WREADY;
      while (!ready_now) begin
        @(negedge clk);
        ready_now = axi.WREADY;
      end
      @(posedge clk);   // this W beat registers in the DUT here
      @(negedge clk);   // safe point
      axi.WVALID = 1'b0;
    end
    axi.WLAST = 1'b0;
  endtask

  task automatic issue_read(
    input logic [3:0] id, input logic [31:0] addr, input logic [7:0] len,
    input logic [2:0] size, input logic [1:0] burst, input logic lock,
    input logic [3:0] qos, input logic [2:0] prot
  );
    logic ready_now;
    @(negedge clk);
    axi.ARID    = id;    axi.ARADDR = addr;  axi.ARLEN  = len;
    axi.ARSIZE  = size;  axi.ARBURST = burst; axi.ARLOCK = lock;
    axi.ARCACHE = 4'h0;  axi.ARPROT  = prot;  axi.ARQOS  = qos;
    axi.ARVALID = 1'b1;
    #0;
    ready_now = axi.ARREADY;
    while (!ready_now) begin
      @(negedge clk);
      ready_now = axi.ARREADY;
    end
    @(posedge clk);   // AR transfer registers in the DUT here
    @(negedge clk);   // safe point
    axi.ARVALID = 1'b0;
  endtask

  // Convenience: one full write, wait for its B response, return resp+time
  task automatic do_write(
    input logic [3:0] id, input logic [31:0] addr, input logic [7:0] len,
    input logic [2:0] size, input logic [1:0] burst, input logic lock,
    input logic [3:0] qos, input logic [2:0] prot, input logic [31:0] data0,
    input logic [3:0] wstrb, output logic [1:0] resp, output time t
  );
    issue_write(id, addr, len, size, burst, lock, qos, prot, data0, wstrb);
    pop_bresp(id, resp, t);
  endtask

  // Convenience: one full read, wait for its data+response, return them.
  // Captures its own beats directly (filtered by RID) rather than going
  // through the background id/resp/time-only log, since Icarus can't hold
  // per-beat data in that log's struct-free representation -- see the note
  // above pop_rresp_meta(). This is safe because the DUT only ever streams
  // one burst at a time on the shared R channel (see axi4_slave.sv), so
  // beats for other IDs never interleave into the one we're collecting.
  task automatic do_read(
    input logic [3:0] id, input logic [31:0] addr, input logic [7:0] len,
    input logic [2:0] size, input logic [1:0] burst, input logic lock,
    input logic [3:0] qos, input logic [2:0] prot,
    output logic [31:0] data[$], output logic [1:0] resp, output time t
  );
    int beat;
    logic [1:0] drain_resp;
    time        drain_t;
    issue_read(id, addr, len, size, burst, lock, qos, prot);
    data = {};
    beat = 0;
    while (beat <= len) begin
      @(posedge clk);
      if (axi.RVALID && axi.RREADY && axi.RID == id) begin
        data.push_back(axi.RDATA);
        resp = axi.RRESP;
        beat = beat + 1;
      end
    end
    t = $time;
    // Drain this transfer's entry from the background id/resp/time log too
    // (pop_rresp_meta), since we captured the data ourselves above -- if we
    // didn't, a later test reusing this same ID would pick up this stale
    // leftover entry instead of its own.
    pop_rresp_meta(id, drain_resp, drain_t);
  endtask

  // ---------------------------------------------------------------------
  // Test sequence
  // ---------------------------------------------------------------------
  logic [31:0] rdata_q[$];
  logic [1:0]  resp;
  time         t1, t2, t3;

  initial begin
    // --- reset -----------------------------------------------------------
    axi.AWVALID = 0; axi.WVALID = 0; axi.ARVALID = 0;
    axi.AWID=0; axi.AWADDR=0; axi.AWLEN=0; axi.AWSIZE=0; axi.AWBURST=0;
    axi.AWLOCK=0; axi.AWCACHE=0; axi.AWPROT=0; axi.AWQOS=0;
    axi.WDATA=0; axi.WSTRB=0; axi.WLAST=0;
    axi.ARID=0; axi.ARADDR=0; axi.ARLEN=0; axi.ARSIZE=0; axi.ARBURST=0;
    axi.ARLOCK=0; axi.ARCACHE=0; axi.ARPROT=0; axi.ARQOS=0;
    
    repeat (4) @(posedge clk);
    rstn = 1'b1;
    repeat (2) @(posedge clk);

    // --- 1) basic single-beat write + read-back --------------------------
    do_write(4'd1, FAST_BASE + 32'h0000_0010, 8'd0, 3'd2, BURST_INCR, 1'b0,
             4'd0, 3'b000, 32'hDEAD_BEEF, 4'hF, resp, t1);
    check(resp == RESP_OKAY, "basic write returns OKAY");
    do_read(4'd1, FAST_BASE + 32'h0000_0010, 8'd0, 3'd2, BURST_INCR, 1'b0,
            4'd0, 3'b000, rdata_q, resp, t1);
    check(resp == RESP_OKAY && rdata_q[0] == 32'hDEAD_BEEF, "basic read-back matches write");

    // --- 2) INCR burst of 4 beats -----------------------------------------
    do_write(4'd2, FAST_BASE + 32'h0000_0100, 8'd3, 3'd2, BURST_INCR, 1'b0,
             4'd0, 3'b000, 32'h1000_0000, 4'hF, resp, t1);
    check(resp == RESP_OKAY, "INCR burst write returns OKAY");
    do_read(4'd2, FAST_BASE + 32'h0000_0100, 8'd3, 3'd2, BURST_INCR, 1'b0,
            4'd0, 3'b000, rdata_q, resp, t1);
    check(resp == RESP_OKAY && rdata_q[0]==32'h1000_0000 && rdata_q[1]==32'h1000_0001 &&
          rdata_q[2]==32'h1000_0002 && rdata_q[3]==32'h1000_0003,
          "INCR burst read-back has correct per-beat data and order");

    // --- 3) WRAP burst: 4 beats x 4B = 16B window, start mid-window ------
    // start = 0x208, window = [0x200,0x210); beats land at 0x208,0x20C,0x200,0x204
    do_write(4'd3, FAST_BASE + 32'h0000_0208, 8'd3, 3'd2, BURST_WRAP, 1'b0,
             4'd0, 3'b000, 32'h2000_0000, 4'hF, resp, t1);
    check(resp == RESP_OKAY, "WRAP burst write returns OKAY");
    do_read(4'd3, FAST_BASE + 32'h0000_0200, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000, rdata_q, resp, t1);
    check(rdata_q[0] == 32'h2000_0002, "WRAP burst wrapped correctly to 0x200 (3rd beat)");
    do_read(4'd3, FAST_BASE + 32'h0000_0208, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000, rdata_q, resp, t1);
    check(rdata_q[0] == 32'h2000_0000, "WRAP burst start address holds 1st beat");
    do_read(4'd3, FAST_BASE + 32'h0000_020C, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000, rdata_q, resp, t1);
    check(rdata_q[0] == 32'h2000_0001, "WRAP burst 2nd beat before the wrap point");
    do_read(4'd3, FAST_BASE + 32'h0000_0204, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000, rdata_q, resp, t1);
    check(rdata_q[0] == 32'h2000_0003, "WRAP burst 4th beat after wrapping");

    // --- 4) narrow transfer: WSTRB updates only one byte lane -------------
    // Per spec, a byte's data appears on the WDATA lane matching its address
    // mod bus-width, regardless of transfer size -- so the 0xEE byte we want
    // in memory byte-lane 2 must be driven on WDATA byte-lane 2 (bits[23:16]).
    do_write(4'd4, FAST_BASE + 32'h0000_0300, 8'd0, 3'd2, BURST_INCR, 1'b0,
             4'd0, 3'b000, 32'hAABB_CCDD, 4'hF, resp, t1); // full word init
    do_write(4'd4, FAST_BASE + 32'h0000_0300, 8'd0, 3'd0, BURST_INCR, 1'b0,
             4'd0, 3'b000, 32'h00EE_0000, 4'b0100, resp, t1); // narrow: byte lane 2 only
    do_read(4'd4, FAST_BASE + 32'h0000_0300, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000, rdata_q, resp, t1);
    check(rdata_q[0] == 32'hAAEE_CCDD, "WSTRB narrow write touched only byte lane 2");

    // --- 5) SLVERR for an address inside the unmapped hole -----------------
    do_write(4'd5, HOLE_BASE + 32'h10, 8'd0, 3'd2, BURST_INCR, 1'b0,
             4'd0, 3'b000, 32'hFFFF_FFFF, 4'hF, resp, t1);
    check(resp == RESP_SLVERR, "write to unmapped hole returns SLVERR");
    do_read(4'd5, HOLE_BASE + 32'h10, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000, rdata_q, resp, t1);
    check(resp == RESP_SLVERR, "read from unmapped hole returns SLVERR");

    // --- 6) AWPROT/ARPROT privileged-region check --------------------------
    do_write(4'd6, FAST_PROT_BASE, 8'd0, 3'd2, BURST_INCR, 1'b0,
             4'd0, 3'b001 /*unprivileged*/, 32'h1234_5678, 4'hF, resp, t1);
    check(resp == RESP_SLVERR, "unprivileged write to protected region returns SLVERR");
    do_write(4'd6, FAST_PROT_BASE, 8'd0, 3'd2, BURST_INCR, 1'b0,
             4'd0, 3'b000 /*privileged*/, 32'h1234_5678, 4'hF, resp, t1);
    check(resp == RESP_OKAY, "privileged write to protected region returns OKAY");
    do_read(4'd6, FAST_PROT_BASE, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000, rdata_q, resp, t1);
    check(resp == RESP_OKAY && rdata_q[0] == 32'h1234_5678, "protected region holds the privileged write");

    // --- 7) exclusive access: matching ID succeeds -------------------------
    do_write(4'd7, FAST_BASE + 32'h0000_0400, 8'd0, 3'd2, BURST_INCR, 1'b0,
             4'd0, 3'b000, 32'h0000_0001, 4'hF, resp, t1); // seed a known value
    do_read(4'd7, FAST_BASE + 32'h0000_0400, 8'd0, 3'd2, BURST_INCR, 1'b1 /*lock*/,
            4'd0, 3'b000, rdata_q, resp, t1);
    check(resp == RESP_EXOKAY, "exclusive read returns EXOKAY and sets the monitor");
    do_write(4'd7, FAST_BASE + 32'h0000_0400, 8'd0, 3'd2, BURST_INCR, 1'b1 /*lock*/,
             4'd0, 3'b000, 32'hCAFE_0007, 4'hF, resp, t1);
    check(resp == RESP_EXOKAY, "exclusive write with matching ID returns EXOKAY");
    do_read(4'd7, FAST_BASE + 32'h0000_0400, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000, rdata_q, resp, t1);
    check(rdata_q[0] == 32'hCAFE_0007, "successful exclusive write updated memory");

    // --- 8) exclusive access: mismatched ID fails, memory unchanged -------
    do_write(4'd8, FAST_BASE + 32'h0000_0410, 8'd0, 3'd2, BURST_INCR, 1'b0,
             4'd0, 3'b000, 32'h5555_5555, 4'hF, resp, t1); // seed
    do_read(4'd8, FAST_BASE + 32'h0000_0410, 8'd0, 3'd2, BURST_INCR, 1'b1 /*lock, id=8*/,
            4'd0, 3'b000, rdata_q, resp, t1);
    check(resp == RESP_EXOKAY, "second exclusive read also returns EXOKAY");
    do_write(4'd9, FAST_BASE + 32'h0000_0410, 8'd0, 3'd2, BURST_INCR, 1'b1 /*lock, but id=9!*/,
             4'd0, 3'b000, 32'hBAD0_0009, 4'hF, resp, t1);
    check(resp == RESP_OKAY, "exclusive write with WRONG ID returns OKAY (not EXOKAY) -- failed");
    do_read(4'd8, FAST_BASE + 32'h0000_0410, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000, rdata_q, resp, t1);
    check(rdata_q[0] == 32'h5555_5555, "failed exclusive write did NOT modify memory");

    // --- 9) multiple outstanding + genuine out-of-order READ completion ---
    // id=10 targets SLOW region (long latency), id=11 targets FAST (short),
    // issued in that order -- id=11 must still complete first.
    issue_read(4'd10, SLOW_BASE + 32'h20, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000);
    issue_read(4'd11, FAST_BASE + 32'h20, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000);
    pop_rresp_meta(4'd11, resp, t2);
    pop_rresp_meta(4'd10, resp, t3);
    check(t2 < t3, "FAST-region read (issued 2nd) completes before SLOW-region read (issued 1st)");

    // --- 10) same-ID ordering: 2nd request with an outstanding ID stalls --
    issue_read(4'd12, SLOW_BASE + 32'h30, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000);
    t1 = $time;
    issue_read(4'd12, FAST_BASE + 32'h30, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000);
    t2 = $time;
    check((t2 - t1) >= 6*CLK_PERIOD, "2nd AR with an already-outstanding ID stalls until the 1st retires");
    pop_rresp_meta(4'd12, resp, t3); // drain the first (SLOW) completion
    pop_rresp_meta(4'd12, resp, t3); // drain the second (FAST) completion

    // --- 11) QoS arbitration: a backlog forms behind a long FAST burst,
    //          then services in descending QoS order ----------------------
    issue_read(4'd13, FAST_BASE + 32'h0000_0500, 8'd7, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000); // 8-beat "busy" burst, low QoS
    issue_read(4'd14, FAST_BASE + 32'h0000_0600, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd1 /*low*/,  3'b000);
    issue_read(4'd15, FAST_BASE + 32'h0000_0604, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd5 /*mid*/,  3'b000);
    issue_read(4'd1,  FAST_BASE + 32'h0000_0608, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd9 /*high*/, 3'b000); // id reused, safe: id=1's earlier read already retired
    pop_rresp_meta(4'd13, resp, t1); // drain the busy burst first (it started first)
    pop_rresp_meta(4'd1, resp, t1); // high QoS
    pop_rresp_meta(4'd15, resp, t2); // mid QoS
    pop_rresp_meta(4'd14, resp, t3); // low QoS
    check(t1 < t2 && t2 < t3, "backlogged reads complete in descending QoS order (high, mid, low)");

    // --- 12) write-side out-of-order B response, same mechanism -----------
    issue_write(4'd2, SLOW_BASE + 32'h0000_0040, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000, 32'hA0A0_A0A0, 4'hF);
    issue_write(4'd3, FAST_BASE + 32'h0000_0700, 8'd0, 3'd2, BURST_INCR, 1'b0, 4'd0, 3'b000, 32'hB0B0_B0B0, 4'hF);
    pop_bresp(4'd3, resp, t2);
    pop_bresp(4'd2, resp, t3);
    check(t2 < t3, "FAST-region write (issued 2nd) gets its B response before the SLOW-region write");

    // --- summary -----------------------------------------------------------
    $display("\n==================================================");
    $display(" RESULT: %0d passed, %0d failed (of %0d checks)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("==================================================\n");
    if (fail_cnt != 0) $fatal(1, "one or more checks failed");
    $finish;
  end

  // safety timeout so a stuck handshake fails loudly instead of hanging CI
  initial begin
    #100000;
    $fatal(1, "TIMEOUT: testbench did not finish in time (likely a stuck AXI handshake)");
  end

endmodule
