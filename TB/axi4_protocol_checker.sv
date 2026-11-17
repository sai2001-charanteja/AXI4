// =============================================================================
// axi4_protocol_checker.sv
//
// A small set of protocol-level SystemVerilog assertions (SVA) covering basic
// AXI4 handshake and burst-safety rules. This is NOT a substitute for
// functional checking (that's what the scoreboard in your UVM environment
// is for) -- it catches PROTOCOL violations: a master or slave doing
// something the AXI4 spec simply does not allow, independent of whether the
// data happens to be "correct".
//
// USAGE: bind this into your own testbench or UVM environment against any
// axi4_if instance, e.g.:
//
//   bind axi4_slave_tb axi4_protocol_checker #(
//     .ID_WIDTH(4), .ADDR_WIDTH(32), .DATA_WIDTH(32)
//   ) u_chk (.axi(axi));
//
// or instantiate it directly alongside a DUT/interface in a new testbench.
// It is passive-only: every port is an input, so binding it can never change
// simulation behavior, only observe it.
//
// Icarus Verilog compatibility note: Icarus's `assert property` support is
// partial (see README.md). The properties below use a subset of SVA that
// compiles under `iverilog -g2012`; a full simulator (VCS/Questa/Xcelium)
// will additionally report a proper pass/fail count and let you enable
// `-g assertions` coverage. If your flow doesn't support `assert property`
// at all, the commented `// PLAIN-SV:` line above each property shows the
// equivalent always-block-plus-$error version.
// =============================================================================
module axi4_protocol_checker #(
  parameter int ID_WIDTH   = 4,
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
) (
  axi4_if.monitor axi
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  // -----------------------------------------------------------------------
  // 1) Reset behavior: every VALID must be low while ARESETN is low.
  // -----------------------------------------------------------------------
  // PLAIN-SV: always @(*) if (!axi.ARESETN) begin
  //             if (axi.AWVALID) $error("AWVALID high during reset");
  //             ... (repeat for WVALID/ARVALID/BVALID/RVALID)
  //           end
  property p_reset_valid_low(logic valid_sig);
    @(posedge axi.ACLK) (!axi.ARESETN) |-> !valid_sig;
  endproperty
  a_reset_awvalid: assert property (p_reset_valid_low(axi.AWVALID))
    else $error("[%0t] PROTOCOL: AWVALID asserted during reset", $time);
  a_reset_wvalid:  assert property (p_reset_valid_low(axi.WVALID))
    else $error("[%0t] PROTOCOL: WVALID asserted during reset", $time);
  a_reset_arvalid: assert property (p_reset_valid_low(axi.ARVALID))
    else $error("[%0t] PROTOCOL: ARVALID asserted during reset", $time);
  a_reset_bvalid:  assert property (p_reset_valid_low(axi.BVALID))
    else $error("[%0t] PROTOCOL: BVALID asserted during reset", $time);
  a_reset_rvalid:  assert property (p_reset_valid_low(axi.RVALID))
    else $error("[%0t] PROTOCOL: RVALID asserted during reset", $time);

  // -----------------------------------------------------------------------
  // 2) VALID must not wait for READY to be asserted (no combinational
  //    dependency of VALID on READY -- a master may not "peek" at READY
  //    before deciding to raise VALID). This is checked indirectly: once
  //    VALID is high, it must stay high until READY is seen, which the
  //    "no early deassertion" property below covers. A true "VALID doesn't
  //    wait for READY" check requires knowledge of the driving master's
  //    internal state and isn't observable from the bus alone, so it is
  //    intentionally not asserted here -- call this out in interviews as a
  //    property that needs white-box (not just bus-level) visibility.
  //
  // 3) VALID, once asserted, must remain asserted (and its payload stable)
  //    until the corresponding READY is seen -- a transfer may not be
  //    "un-offered" or have its payload change mid-offer.
  // -----------------------------------------------------------------------
  // PLAIN-SV (AWVALID example):
  //   logic aw_pending; logic [ADDR_WIDTH-1:0] aw_addr_latched;
  //   always @(posedge axi.ACLK) begin
  //     if (!axi.ARESETN) aw_pending <= 0;
  //     else if (axi.AWVALID && !axi.AWREADY) begin
  //       if (aw_pending && axi.AWADDR !== aw_addr_latched)
  //         $error("AWADDR changed while AWVALID held without AWREADY");
  //       aw_pending <= 1; aw_addr_latched <= axi.AWADDR;
  //     end else aw_pending <= 0;
  //   end
  property p_valid_stable_until_ready(logic valid_sig, logic ready_sig);
    @(posedge axi.ACLK) disable iff (!axi.ARESETN)
      (valid_sig && !ready_sig) |=> valid_sig;
  endproperty
  a_awvalid_stable: assert property (p_valid_stable_until_ready(axi.AWVALID, axi.AWREADY))
    else $error("[%0t] PROTOCOL: AWVALID deasserted before AWREADY", $time);
  a_wvalid_stable:  assert property (p_valid_stable_until_ready(axi.WVALID, axi.WREADY))
    else $error("[%0t] PROTOCOL: WVALID deasserted before WREADY", $time);
  a_arvalid_stable: assert property (p_valid_stable_until_ready(axi.ARVALID, axi.ARREADY))
    else $error("[%0t] PROTOCOL: ARVALID deasserted before ARREADY", $time);
  a_bvalid_stable:  assert property (p_valid_stable_until_ready(axi.BVALID, axi.BREADY))
    else $error("[%0t] PROTOCOL: BVALID deasserted before BREADY", $time);
  a_rvalid_stable:  assert property (p_valid_stable_until_ready(axi.RVALID, axi.RREADY))
    else $error("[%0t] PROTOCOL: RVALID deasserted before RREADY", $time);

  property p_addr_stable_until_ready(logic valid_sig, logic ready_sig, logic [ADDR_WIDTH-1:0] addr_sig);
    @(posedge axi.ACLK) disable iff (!axi.ARESETN)
      (valid_sig && !ready_sig) |=> $stable(addr_sig);
  endproperty
  a_awaddr_stable: assert property (p_addr_stable_until_ready(axi.AWVALID, axi.AWREADY, axi.AWADDR))
    else $error("[%0t] PROTOCOL: AWADDR changed while AWVALID held without AWREADY", $time);
  a_araddr_stable: assert property (p_addr_stable_until_ready(axi.ARVALID, axi.ARREADY, axi.ARADDR))
    else $error("[%0t] PROTOCOL: ARADDR changed while ARVALID held without ARREADY", $time);

  // -----------------------------------------------------------------------
  // 4) WLAST must appear exactly on the beat matching the AWLEN of the
  //    write burst it belongs to -- neither early nor late. Tracked with a
  //    simple beat counter that resets on every accepted W beat with WLAST.
  // -----------------------------------------------------------------------
  // PLAIN-SV:
  //   logic [7:0] w_beat_cnt; logic [7:0] w_awlen_latched;
  //   always @(posedge axi.ACLK) begin
  //     if (!axi.ARESETN) w_beat_cnt <= 0;
  //     else begin
  //       if (axi.AWVALID && axi.AWREADY) w_awlen_latched <= axi.AWLEN;
  //       if (axi.WVALID && axi.WREADY) begin
  //         if (axi.WLAST && w_beat_cnt != w_awlen_latched)
  //           $error("WLAST asserted at beat %0d, expected %0d", w_beat_cnt, w_awlen_latched);
  //         w_beat_cnt <= axi.WLAST ? 0 : w_beat_cnt + 1;
  //       end
  //     end
  //   end
  logic [7:0] chk_w_beat_cnt;
  logic [7:0] chk_w_awlen_q;
  always_ff @(posedge axi.ACLK) begin
    if (!axi.ARESETN) begin
      chk_w_beat_cnt <= 8'd0;
      chk_w_awlen_q  <= 8'd0;
    end else begin
      if (axi.AWVALID && axi.AWREADY) chk_w_awlen_q <= axi.AWLEN;
      if (axi.WVALID && axi.WREADY) begin
        if (axi.WLAST && (chk_w_beat_cnt != chk_w_awlen_q))
          $error("[%0t] PROTOCOL: WLAST at beat %0d but AWLEN implies beat %0d",
                  $time, chk_w_beat_cnt, chk_w_awlen_q);
        chk_w_beat_cnt <= axi.WLAST ? 8'd0 : (chk_w_beat_cnt + 8'd1);
      end
    end
  end

  // -----------------------------------------------------------------------
  // 5) RLAST must appear exactly on the beat matching the ARLEN of the read
  //    burst it belongs to. A small per-ID table (latched at AR accept
  //    time) makes this correct even with several IDs outstanding at once,
  //    relying only on the AXI4 rule that one ID's own beats are always
  //    contiguous on the R channel (read data interleaving is deprecated
  //    in AXI4) -- not on any single-burst-at-a-time assumption.
  // -----------------------------------------------------------------------
  // PLAIN-SV: this check IS plain SV (no `assert property`), shown here in
  // full since it doubles as the workaround for simulators without SVA
  // support.
  logic [7:0] chk_arlen_table [(1<<ID_WIDTH)-1:0];
  logic [7:0] chk_r_beat_cnt;
  always_ff @(posedge axi.ACLK) begin
    if (!axi.ARESETN) begin
      chk_r_beat_cnt <= 8'd0;
    end else begin
      if (axi.ARVALID && axi.ARREADY) chk_arlen_table[axi.ARID] <= axi.ARLEN;
      if (axi.RVALID && axi.RREADY) begin
        if (axi.RLAST && (chk_r_beat_cnt != chk_arlen_table[axi.RID]))
          $error("[%0t] PROTOCOL: RLAST for ID %0d at beat %0d but ARLEN implies beat %0d",
                  $time, axi.RID, chk_r_beat_cnt, chk_arlen_table[axi.RID]);
        chk_r_beat_cnt <= axi.RLAST ? 8'd0 : (chk_r_beat_cnt + 8'd1);
      end
    end
  end

  // -----------------------------------------------------------------------
  // 6) Burst-type legality: AWBURST/ARBURST must never be the Reserved
  //    encoding (2'b11) when VALID is asserted.
  // -----------------------------------------------------------------------
  property p_burst_not_reserved(logic valid_sig, logic [1:0] burst_sig);
    @(posedge axi.ACLK) disable iff (!axi.ARESETN) valid_sig |-> (burst_sig != 2'b11);
  endproperty
  a_awburst_legal: assert property (p_burst_not_reserved(axi.AWVALID, axi.AWBURST))
    else $error("[%0t] PROTOCOL: AWBURST used the Reserved encoding (2'b11)", $time);
  a_arburst_legal: assert property (p_burst_not_reserved(axi.ARVALID, axi.ARBURST))
    else $error("[%0t] PROTOCOL: ARBURST used the Reserved encoding (2'b11)", $time);

  // -----------------------------------------------------------------------
  // 7) WRAP bursts must have a length of 2, 4, 8, or 16 beats (AxLEN of
  //    1, 3, 7, or 15) -- required by the spec so the wrap window is a
  //    power-of-two number of beats.
  // -----------------------------------------------------------------------
  function automatic logic legal_wrap_len(logic [7:0] len);
    legal_wrap_len = (len == 8'd1) || (len == 8'd3) || (len == 8'd7) || (len == 8'd15);
  endfunction

  property p_wrap_len_legal(logic valid_sig, logic [1:0] burst_sig, logic [7:0] len_sig);
    @(posedge axi.ACLK) disable iff (!axi.ARESETN)
      (valid_sig && burst_sig == 2'b10) |-> legal_wrap_len(len_sig);
  endproperty
  a_awlen_wrap_legal: assert property (p_wrap_len_legal(axi.AWVALID, axi.AWBURST, axi.AWLEN))
    else $error("[%0t] PROTOCOL: WRAP write burst has illegal length (AWLEN=%0d)", $time, axi.AWLEN);
  a_arlen_wrap_legal: assert property (p_wrap_len_legal(axi.ARVALID, axi.ARBURST, axi.ARLEN))
    else $error("[%0t] PROTOCOL: WRAP read burst has illegal length (ARLEN=%0d)", $time, axi.ARLEN);

  // -----------------------------------------------------------------------
  // 8) No X/Z on VALID signals once out of reset -- an unknown VALID is
  //    always a testbench or DUT bug, never legal protocol behavior.
  // -----------------------------------------------------------------------
  property p_no_x_valid(logic valid_sig);
    @(posedge axi.ACLK) disable iff (!axi.ARESETN) !$isunknown(valid_sig);
  endproperty
  a_no_x_awvalid: assert property (p_no_x_valid(axi.AWVALID)) else $error("[%0t] PROTOCOL: AWVALID is X/Z", $time);
  a_no_x_wvalid:  assert property (p_no_x_valid(axi.WVALID))  else $error("[%0t] PROTOCOL: WVALID is X/Z", $time);
  a_no_x_arvalid: assert property (p_no_x_valid(axi.ARVALID)) else $error("[%0t] PROTOCOL: ARVALID is X/Z", $time);
  a_no_x_bvalid:  assert property (p_no_x_valid(axi.BVALID))  else $error("[%0t] PROTOCOL: BVALID is X/Z", $time);
  a_no_x_rvalid:  assert property (p_no_x_valid(axi.RVALID))  else $error("[%0t] PROTOCOL: RVALID is X/Z", $time);

endmodule
