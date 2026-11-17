class axi4_directed_seq extends uvm_sequence#(axi4_transaction);
    `uvm_object_utils(axi4_directed_seq)
    axi4_reset_seq rst_seq;
    function new(string name = "axi4_directed_seq");
        super.new(name);
        set_automatic_phase_objection(1);
    endfunction
    

    task body();
        axi4_transaction trnx;
        rst_seq = axi4_reset_seq::type_id::create("rst_seq");
        rst_seq.start(m_sequencer);
        
        for(int idx=0;idx<5;idx++) begin
            `uvm_info("WR_SEQ",$sformatf("Write transaction packet %0d Sequence started",idx),UVM_MEDIUM)
            trnx = axi4_transaction::type_id::create($sformatf("rd_seq_%0d",idx));
            start_item(trnx);
            trnx.randomize() with {kind == WRITE;  AXBURST == BURST_INCR; AXLEN == 3; AXSIZE == 2; AXADDR == 32'h0000_0000+idx*4*(32'h0000_0004); };
            foreach(trnx.WDATA[i]) begin
                trnx.WDATA[i] = idx;
                trnx.WSTRB[i] = 'b1;
            end
            finish_item(trnx);
            `uvm_info("WR_SEQ",$sformatf("Write transaction packet %0d is Seqeunce Completed",idx),UVM_MEDIUM)
        end

        for(int idx=0;idx<5;idx++) begin
            `uvm_info("RD_SEQ",$sformatf("Read transaction packet %0d Sequence started",idx),UVM_MEDIUM)
            trnx = axi4_transaction::type_id::create($sformatf("rd_seq_%0d",idx));
            start_item(trnx);
            trnx.randomize() with {kind == READ;  AXBURST == BURST_INCR; AXLEN == 3;AXSIZE == 2; AXADDR == 32'h0000_0000+idx*4*(32'h0000_0004); };
            
            finish_item(trnx);
            `uvm_info("RD_SEQ",$sformatf("Read transaction packet %0d is Seqeunce Completed",idx),UVM_MEDIUM)
        end

       
    endtask

endclass