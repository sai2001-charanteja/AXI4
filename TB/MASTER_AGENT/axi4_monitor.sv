class axi4_monitor extends uvm_monitor;
    `uvm_component_utils(axi4_monitor)

    virtual axi4_if vif;
    uvm_analysis_port#(axi4_transaction) ap;
    process axi4_channel_proc;

    function new(string name="axi4_monitor",uvm_component parent = null);
        super.new(name,parent);
    endfunction


    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual axi4_if)::get(this,"","vif",vif)) 
            `uvm_fatal("CONFIG_ERROR","Unable to set virtual interface")

        ap = new("ap",this);

    endfunction

    task run_phase(uvm_phase phase);
        
        fork : axi4_threads
            begin
                axi4_channel_proc = process::self();
                fork
                    aw_monitor();
                    w_monitor();
                    b_monitor();
                    ar_monitor();
                    r_monitor();
                join
                
            end

        join_none
        reset_monitor();
    endtask


    task aw_monitor();
        axi4_transaction trx;
        forever begin
             
            trx = axi4_transaction::type_id::create("aw_mon_trx",this);
            trx.channel = AW;
            if(vif.AWVALID === 1'b1 && vif.AWREADY === 1'b1) begin
                trx.AXID = vif.AWID;
                trx.AXADDR = vif.AWADDR;
                trx.AXLEN = vif.AWLEN;
                trx.AXSIZE = vif.AWSIZE;
                trx.AXBURST = vif.AWBURST;
                trx.AXLOCK = vif.AWLOCK;
                trx.AXCACHE = vif.AWCACHE;
                trx.AXPROT = vif.AWPROT;
                trx.AXQOS = vif.AWQOS;
                ap.write(trx);
                `uvm_info("MONITOR",$sformatf("[%0t] Successfully captured the AW channel",$time),UVM_MEDIUM)
            end
            do @(posedge vif.ACLK); while(vif.AWVALID !== 1'b1 || vif.AWREADY !== 1'b1);
        end
    endtask

    task w_monitor();
        axi4_transaction trx;
        bit [DATA_WIDTH-1:0] data[$]; 
        bit [STRB_WIDTH-1:0] strb[$];
        forever begin
             
            trx = axi4_transaction::type_id::create("w_mon_trx",this);
            trx.channel = W;
            
            while(1) begin
                
                if(vif.WVALID === 1'b1 && vif.WREADY === 1'b1) begin
                    data.push_back(vif.WDATA);
                    strb.push_back(vif.WSTRB);
                    if(vif.WLAST == 1'b1) begin
                        trx.WDATA = data;
                        trx.WSTRB = strb;
                        data.delete();
                        strb.delete();
                        ap.write(trx);
                        `uvm_info("MONITOR",$sformatf("[%0t] Successfully captured the w channel",$time),UVM_MEDIUM)
                        @(posedge vif.ACLK);
                        break; 
                    end 
                end

                do @(posedge vif.ACLK); while(vif.WVALID !== 1'b1 || vif.WREADY !== 1'b1);
                
            end
            
        end
    endtask

    task b_monitor();
        axi4_transaction trx;
       
        forever begin
             
            trx = axi4_transaction::type_id::create("b_mon_trx",this);
            trx.channel = B;
            
                
            if(vif.BVALID === 1'b1 && vif.BREADY === 1'b1) begin
                trx.BID = vif.BID;
                trx.BRESP = vif.BRESP;
                ap.write(trx);
                `uvm_info("MONITOR",$sformatf("[%0t] Successfully captured the B channel",$time),UVM_MEDIUM)
            end

            do @(posedge vif.ACLK); while(vif.BVALID !== 1'b1 || vif.BREADY !== 1'b1);
                
        end
    endtask

    task ar_monitor();
        axi4_transaction trx;
        forever begin
             
            trx = axi4_transaction::type_id::create("ar_mon_trx",this);
            trx.channel = AR;
            if(vif.ARVALID === 1'b1 && vif.ARREADY === 1'b1) begin
                trx.AXID = vif.ARID;
                trx.AXADDR = vif.ARADDR;
                trx.AXLEN = vif.ARLEN;
                trx.AXSIZE = vif.ARSIZE;
                trx.AXBURST = vif.ARBURST;
                trx.AXLOCK = vif.ARLOCK;
                trx.AXCACHE = vif.ARCACHE;
                trx.AXPROT = vif.ARPROT;
                trx.AXQOS = vif.ARQOS;
                ap.write(trx);
                `uvm_info("MONITOR",$sformatf("[%0t] Successfully captured the AR channel",$time),UVM_MEDIUM)
            end
            do @(posedge vif.ACLK); while(vif.ARVALID !== 1'b1 || vif.ARREADY !== 1'b1);
        end
    endtask

    
    task r_monitor();
        axi4_transaction trx;
        bit [DATA_WIDTH-1:0] data[$]; 
        bit [1:0] rsp[$];
        bit [ID_WIDTH-1:0] ids[$];
        forever begin
             
            trx = axi4_transaction::type_id::create("r_mon_trx",this);
            trx.channel = R;

            while(1) begin

                if(vif.RVALID === 1'b1 && vif.RREADY === 1'b1) begin
                    data.push_back(vif.RDATA);
                    rsp.push_back(vif.RRESP);
                    ids.push_back(vif.RID);
                    if(vif.RLAST == 1'b1) begin
                        trx.RDATA = data;
                        trx.RRESP = rsp;
                        trx.RID   = ids;
                        data.delete();
                        rsp.delete();
                        ids.delete();
                        ap.write(trx);
                        @(posedge vif.ACLK);
                        `uvm_info("MONITOR",$sformatf("[%0t] Successfully captured the R channel",$time),UVM_MEDIUM)
                        break; 
                        
                        end 
                end

                do @(posedge vif.ACLK); while(vif.RVALID !== 1'b1 || vif.RREADY !== 1'b1);
                
            end
            
        end
    endtask

    task reset_monitor();
        axi4_transaction trx;
        
        forever begin
             
            trx = axi4_transaction::type_id::create("reset_mon_trx",this);
            trx.channel = RST;
            
            while(1) begin
                
                if(vif.ARESETN === 1'b0) begin
                    ap.write(trx);
                    axi4_channel_proc.kill();
                    fork : axi4_threads
                        begin
                            axi4_channel_proc = process::self();
                            fork
                                aw_monitor();
                                w_monitor();
                                b_monitor();
                                ar_monitor();
                                r_monitor();
                            join
                            
                        end

                    join_none

                end

                do @(posedge vif.ACLK); while(vif.ARESETN !== 1'b0);
                
            end
            
        end
    endtask


endclass