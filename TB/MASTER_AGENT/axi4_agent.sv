class axi4_agent extends uvm_agent;
    `uvm_component_utils(axi4_agent)

    uvm_sequencer#(axi4_transaction) seqr;

    axi4_driver drvr;
    axi4_monitor mon;
    uvm_analysis_port#(axi4_transaction) pass_through_port;

    function new(string name = "axi4_agent",uvm_component parent = null);
        super.new(name,parent);
    endfunction


    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        seqr = uvm_sequencer#(axi4_transaction)::type_id::create("seqr",this);
        
        drvr = axi4_driver::type_id::create("drvr",this);

        mon = axi4_monitor::type_id::create("mon",this);

        pass_through_port = new("pass_through_port",this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        drvr.seq_item_port.connect(seqr.seq_item_export);

        mon.ap.connect(pass_through_port);
    endfunction
    
    
endclass