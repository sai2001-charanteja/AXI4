class axi4_rd_seq extends uvm_sequence#(axi4_transaction);
    `uvm_object_utils(axi4_rd_seq)

    function new(string name = "axi4_rd_seq");
        super.new(name);
        set_automatic_phase_objection(1);
    endfunction
    

    task body();
        axi4_transaction trnx;
        
        for(int idx=0;idx<100;idx++) begin
            `uvm_info("RD_SEQ",$sformatf("Read transaction packet %0d Sequence started",idx),UVM_MEDIUM)
            trnx = axi4_transaction::type_id::create($sformatf("rd_seq_%0d",idx));
            start_item(trnx);
            trnx.randomize() with {kind == READ;};
            finish_item(trnx);
            `uvm_info("RD_SEQ",$sformatf("Read transaction packet %0d is Seqeunce Completed",idx),UVM_MEDIUM)
        end
    endtask

endclass