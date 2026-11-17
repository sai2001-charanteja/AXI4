class axi4_env extends uvm_env;
    `uvm_component_utils(axi4_env)

    axi4_agent agnt;
    axi4_scb scb; 
    function new(string name, uvm_component parent = null);
        super.new(name,parent);
    endfunction


    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        agnt = axi4_agent::type_id::create("agnt",this);
        
        scb = axi4_scb::type_id::create("scb",this);

    endfunction
    
    function void connect_phase(uvm_phase phase);
        
        agnt.pass_through_port.connect(scb.imp);

    endfunction
    
    task run_phase(uvm_phase phase);

        phase.raise_objection(this);

        // Start the AXI sequence

        // Wait until scoreboard confirms all expected responses
        wait(scb.total_reads == 5);

        // Now it is safe to end the test
        phase.drop_objection(this);

    endtask
endclass