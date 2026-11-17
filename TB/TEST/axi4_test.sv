class axi4_test extends uvm_test;
    `uvm_component_utils(axi4_test)

    axi4_env env;

    function new(string name, uvm_component parent = null);
        super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env = axi4_env::type_id::create("env",this);

        //uvm_config_db#(uvm_object_wrapper)::set(this,"env.agnt.seqr.main_phase","default_sequence",axi4_wr_seq::get_type());
       // uvm_config_db#(uvm_object_wrapper)::set(this,"env.agnt.seqr.main_phase","default_sequence",axi4_main_seq::get_type());
        uvm_config_db#(uvm_object_wrapper)::set(this,"env.agnt.seqr.main_phase","default_sequence",axi4_directed_seq::get_type());
    endfunction



endclass