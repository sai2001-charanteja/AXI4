class axi4_main_seq extends uvm_sequence#(axi4_transaction);
    `uvm_object_utils(axi4_main_seq)

    axi4_wr_seq wr_seq;
    axi4_rd_seq rd_seq;
    axi4_reset_seq rst_seq;
    axi4_rd_wr_seq rd_wr_seq;

    function new(string name = "axi4_main_seq");
        super.new(name);
        set_automatic_phase_objection(1);
        
    endfunction
    

    task body();
        wr_seq = axi4_wr_seq::type_id::create("wr_seq");
        rd_seq = axi4_rd_seq::type_id::create("rd_seq");
        rst_seq = axi4_reset_seq::type_id::create("rst_seq");
        rd_wr_seq = axi4_rd_wr_seq::type_id::create("rd_wr_seq");

        rd_wr_seq.start(m_sequencer);
        rst_seq.start(m_sequencer);
        wr_seq.start(m_sequencer);
        rd_seq.start(m_sequencer);
    endtask

endclass