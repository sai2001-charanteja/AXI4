class axi4_reset_seq extends uvm_sequence#(axi4_transaction);
    `uvm_object_utils(axi4_reset_seq)

    function new(string name = "axi4_reset_seq");
        super.new(name);
        set_automatic_phase_objection(1);
    endfunction
    

    task body();
        axi4_transaction trnx;
        `uvm_info("RESET_SEQ",$sformatf("[%0t] Reset Seqeunce is started",$time),UVM_MEDIUM)
        trnx = axi4_transaction::type_id::create("reset_seq");
        start_item(trnx);
        trnx.randomize() with {kind == RESET;};
        finish_item(trnx);
        `uvm_info("RESET_SEQ",$sformatf("[%0t] Reset Seqeunce is Finished",$time),UVM_MEDIUM)

    endtask

endclass