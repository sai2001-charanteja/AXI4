class axi4_scb extends uvm_scoreboard;
    
    `uvm_component_utils(axi4_scb)

    uvm_analysis_imp#(axi4_transaction,axi4_scb) imp;

    localparam int WORD_SHIFT = $clog2(STRB_WIDTH);

    int err_count;
    int total_reads;
    bit [DATA_WIDTH-1:0] fast_mem [0:(axi4_RTL_pkg::FAST_SIZE>>WORD_SHIFT)-1];
    bit [DATA_WIDTH-1:0] slow_mem [0:(axi4_RTL_pkg::SLOW_SIZE>>WORD_SHIFT)-1];

    // Exclusive-access monitor model (mirrors the DUT's single-entry monitor)
    bit                  mon_valid;
    bit [ID_WIDTH-1:0]   mon_id;
    bit [ADDR_WIDTH-1:0] mon_addr;

    axi4_transaction trx;
    axi4_transaction awq[$];
    axi4_transaction wq[$];
    axi4_transaction arq[$];

    // AXI4 has no WID: W bursts are consumed in AW issue order, so pair them by arrival order
    typedef struct {
        axi4_transaction aw;
        axi4_transaction w;
    } wr_pair_t;
    wr_pair_t pairq[$];

    function void pair_writes();
        while(awq.size() > 0 && wq.size() > 0) begin
            wr_pair_t pair;
            pair.aw = awq.pop_front();
            pair.w  = wq.pop_front();
            pairq.push_back(pair);
        end
    endfunction


    function new(string name="axi4_scb",uvm_component parent = null);
        super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        imp = new("imp",this);

    endfunction


    function void write(axi4_transaction resp);
        //trx = resp.clone();
        $cast(trx, resp.clone());

        `uvm_info("SCB",$sformatf("[%0t] Recieved a Transaction %0s-%0d %0s",$time,trx.channel.name(),resp.channel,resp.kind.name()),UVM_MEDIUM)
        case(trx.channel)
            AW: begin awq.push_back(trx); pair_writes(); end
            W:  begin wq.push_back(trx);  pair_writes(); end
            B:
                begin

                    int pair_idxq[$] = pairq.find_first_index() with (item.aw.AXID == trx.BID);
                    if(pair_idxq.size() == 0) begin
                        `uvm_error("AWID_MISSING","Unable to find a paired AW/W for the BID")
                    end
                    else begin
                        wr_pair_t pair = pairq[pair_idxq[0]];
                        pairq.delete(pair_idxq[0]);
                        write_to_mem(pair.aw,pair.w);
                    end
                end
            RST: begin
                awq.delete();
                wq.delete();
                pairq.delete();
                arq.delete();
                mon_valid = 1'b0;
            end
            AR: begin
                arq.push_back(trx);
                if(trx.AXLOCK) begin
                    mon_valid = 1'b1;
                    mon_id    = trx.AXID;
                    mon_addr  = trx.AXADDR;
                end
            end
            R:  begin

                begin 

                    int ar_idxq[$] = arq.find_first_index() with (item.AXID == trx.RID[0]);
                    if(ar_idxq.size() == 0) begin
                        `uvm_error("ARID_MISSING","Unable to find the RID in the queue")
                    end

                    else begin

                        axi4_transaction ar_trx;
                        ar_trx = arq[ar_idxq[0]];
                        arq.delete(ar_idxq[0]);

                        check_mem(ar_trx,trx);
                    end
                end
                
            end
        endcase

    endfunction


    function void write_to_mem(axi4_transaction aw_trx,axi4_transaction w_trx);
        axi4_RTL_pkg::axi_region_e region;
        bit [ADDR_WIDTH-1:0] beat_addr;
        int unsigned         word_idx;
        bit                  err, excl_ok;

        foreach(w_trx.WDATA[i]) begin
            beat_addr = axi4_RTL_pkg::axi_beat_addr(aw_trx.AXADDR, aw_trx.AXSIZE, aw_trx.AXBURST, aw_trx.AXLEN, 8'(i));
            region    = axi4_RTL_pkg::get_region(beat_addr);

            // unmapped hole, or unprivileged access to the protected top of FAST -> SLVERR, no write
            err = (region == axi4_RTL_pkg::REGION_ERR) ||
                  (region == axi4_RTL_pkg::REGION_FAST_PROT && aw_trx.AXPROT[0]);

            excl_ok = !aw_trx.AXLOCK ||
                      (mon_valid && mon_id == aw_trx.AXID && mon_addr == beat_addr);

            if(!err && excl_ok) begin
                word_idx = (region == axi4_RTL_pkg::REGION_SLOW) ?
                           ((beat_addr - axi4_RTL_pkg::SLOW_BASE) >> WORD_SHIFT) :
                           ((beat_addr - axi4_RTL_pkg::FAST_BASE) >> WORD_SHIFT);

                for(int b = 0; b < STRB_WIDTH; b++) begin
                    if(w_trx.WSTRB[i][b]) begin
                        if(region == axi4_RTL_pkg::REGION_SLOW)
                            slow_mem[word_idx][8*b +: 8] = w_trx.WDATA[i][8*b +: 8];
                        else
                            fast_mem[word_idx][8*b +: 8] = w_trx.WDATA[i][8*b +: 8];
                    end
                end
            end

            // any non-error write to the reserved address invalidates the reservation
            if(!err && mon_valid && mon_addr == beat_addr) mon_valid = 1'b0;
        end
    endfunction


    function void check_mem(axi4_transaction ar_trx,axi4_transaction r_trx);
        axi4_RTL_pkg::axi_region_e region;
        bit [ADDR_WIDTH-1:0] beat_addr;
        int unsigned         word_idx;
        bit                  err;
        bit [DATA_WIDTH-1:0] exp_data;
        bit [1:0]            exp_resp;
        total_reads++;

        if(r_trx.RDATA.size() != ar_trx.AXLEN + 1) begin
            `uvm_error("R_BEATS",$sformatf("ID %0d: got %0d beats, expected %0d",ar_trx.AXID,r_trx.RDATA.size(),ar_trx.AXLEN+1))
            return;
        end

        foreach(r_trx.RDATA[i]) begin
            beat_addr = axi4_RTL_pkg::axi_beat_addr(ar_trx.AXADDR, ar_trx.AXSIZE, ar_trx.AXBURST, ar_trx.AXLEN, 8'(i));
            region    = axi4_RTL_pkg::get_region(beat_addr);
            err = (region == axi4_RTL_pkg::REGION_ERR) ||
                  (region == axi4_RTL_pkg::REGION_FAST_PROT && ar_trx.AXPROT[0]);

            if(err) begin
                exp_data = '0;
                exp_resp = RESP_SLVERR;
            end else begin
                word_idx = (region == axi4_RTL_pkg::REGION_SLOW) ?
                           ((beat_addr - axi4_RTL_pkg::SLOW_BASE) >> WORD_SHIFT) :
                           ((beat_addr - axi4_RTL_pkg::FAST_BASE) >> WORD_SHIFT);
                exp_data = (region == axi4_RTL_pkg::REGION_SLOW) ? slow_mem[word_idx] : fast_mem[word_idx];
                exp_resp = ar_trx.AXLOCK ? RESP_EXOKAY : RESP_OKAY;
            end

            if(r_trx.RDATA[i] !== exp_data) begin
                `uvm_error("R_DATA",$sformatf("ID %0d beat %0d addr 0x%08h: got 0x%08h, expected 0x%08h",ar_trx.AXID,i,beat_addr,r_trx.RDATA[i],exp_data))
                err_count++;
                break;
            end
            if(r_trx.RRESP[i] !== exp_resp) begin
                `uvm_error("R_RESP",$sformatf("ID %0d beat %0d addr 0x%08h: got %0d, expected %0d",ar_trx.AXID,i,beat_addr,r_trx.RRESP[i],exp_resp))
                err_count++;
                break;
            end
        end
    endfunction

    function void extract_phase(uvm_phase phase);
        if(total_reads !=0) begin
            if(err_count == 0 ) `uvm_info("SCB",$sformatf("TEST PASS for %0d READs",total_reads),UVM_NONE)
            else `uvm_info("SCB",$sformatf("TEST FAILE receieved %0d erros out of %0d READs",err_count, total_reads),UVM_NONE)
        end else
            `uvm_info("SCB",$sformatf("TEST NEUTRAL , no reads operation performaed"),UVM_NONE)
    endfunction

endclass