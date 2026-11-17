class axi4_wr_seq extends uvm_sequence#(axi4_transaction);
    `uvm_object_utils(axi4_wr_seq)

    function new(string name = "axi4_wr_seq");
        super.new(name);
        set_automatic_phase_objection(1);
    endfunction
    

    task body();
        axi4_transaction trnx;

        for(int idx=0;idx<100;idx++) begin
            `uvm_info("WR_SEQ",$sformatf("Write transaction packet %0d Sequence started",idx),UVM_MEDIUM)
            trnx = axi4_transaction::type_id::create($sformatf("wr_seq_%0d",idx));
            start_item(trnx);
            trnx.randomize() with {kind == WRITE;};
            finish_item(trnx);
            `uvm_info("WR_SEQ",$sformatf("Write transaction packet %0d is Seqeunce Completed",idx),UVM_MEDIUM)
        end
    endtask

endclass