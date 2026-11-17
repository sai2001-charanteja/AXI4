class axi4_rd_wr_seq extends uvm_sequence#(axi4_transaction);
    `uvm_object_utils(axi4_rd_wr_seq)

    function new(string name = "axi4_rd_wr_seq");
        super.new(name);
        set_automatic_phase_objection(1);
    endfunction
    

    task body();
        axi4_transaction trnx;
        
        for(int idx=0;idx<100;idx++) begin
            `uvm_info("RD_WR_SEQ",$sformatf("Transaction packet %0d Sequence started",idx),UVM_MEDIUM)
            trnx = axi4_transaction::type_id::create($sformatf("RD_WR_SEQ_%0d",idx));
            start_item(trnx);
            trnx.randomize() with {kind inside {READ,WRITE};};
            finish_item(trnx);
            `uvm_info("RD_WR_SEQ",$sformatf("Transaction packet %0d is Seqeunce Completed",idx),UVM_MEDIUM)
        end
    endtask

endclass