class axi4_driver extends uvm_driver#(axi4_transaction);
    `uvm_component_utils(axi4_driver)
 
    virtual axi4_if vif;
    int pkt_count;
    semaphore slots;
    mailbox#(axi4_transaction) mbx_aw,mbx_w,mbx_ar;
    process axi_threads_proc;
    function new(string name = "axi4_driver",uvm_component parent = null);
        super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if(!uvm_config_db#(virtual axi4_if)::get(this,"","vif",vif))
            `uvm_fatal("CONFIG_ERROR","Unable to set virtual interface")
        
        pkt_count = 1;

        slots = new(OUTSTANDING);  // I will use this semaphore to simulate the outstanding transaction
        mbx_aw = new();
        mbx_w = new();
        mbx_ar = new();
        
    endfunction

    virtual task run_phase(uvm_phase phase);
        //phase.raise_objection(this);
        axi4_transaction trx;

        fork
            begin
                axi_threads_proc = process::self(); // It store the handle of the outerblock
                fork
                    drive_aw();
                    drive_w();
                    drive_b();
                    drive_ar();
                    drive_r();
                join
            end
        join_none


        forever begin
            `uvm_info("DRVR",$sformatf("[%0t] Waiting for transaction - %0d",$time, pkt_count),UVM_DEBUG)
            seq_item_port.get_next_item(trx);
            `uvm_info("DRVR",$sformatf("[%0t] Drving of transaction - %0d Started",$time, pkt_count),UVM_DEBUG)
            
            slots.get(1);

            if(trx.kind == WRITE) begin
                mbx_aw.put(trx);
                mbx_w.put(trx);
            end else if(trx.kind == READ) begin
                mbx_ar.put(trx);
            end else begin
                drive_reset();
            end

            //`uvm_info("DRVR",$sformatf("[%0t] Drving of transaction - %0d Finished",$time, pkt_count),UVM_DEBUG)
            seq_item_port.item_done();
           // `uvm_info("DRVR",$sformatf("[%0t] Released Transaction - %0d",$time, pkt_count),UVM_DEBUG)
            pkt_count++;
        end 
    endtask

    task automatic drive_reset();
        
        vif.ARESETN <= 1'b0;
        vif.AWID<= 0;
        vif.AWADDR<= 0;
        vif.AWLEN<= 0;
        vif.AWSIZE<= 0;
        vif.AWBURST<= 0;
        vif.AWLOCK<= 0;
        vif.AWCACHE<= 0;
        vif.AWPROT<= 0;
        vif.AWQOS<= 0;
        vif.AWVALID<= 0;
        vif.WDATA<= 0;
        vif.WSTRB<= 0;
        vif.WLAST<= 0;
        vif.WVALID<= 0;
        vif.BREADY<= 0;
        vif.ARID<= 0;
        vif.ARADDR<= 0;
        vif.ARLEN<= 0;
        vif.ARSIZE<= 0;
        vif.ARBURST<= 0;
        vif.ARLOCK<= 0;
        vif.ARCACHE<= 0;
        vif.ARPROT<= 0;
        vif.ARQOS<= 0;
        vif.ARVALID<= 0;

        repeat(4) @(posedge vif.ACLK);
        vif.ARESETN <= 1'b1;
        slots = new(OUTSTANDING);
        begin
            axi4_transaction trx;
            while (mbx_aw.num() > 0) mbx_aw.get(trx);
            while (mbx_w.num() > 0) mbx_w.get(trx);
            while (mbx_ar.num() > 0) mbx_ar.get(trx);
        end
        if(axi_threads_proc!=null) 
            axi_threads_proc.kill();
       fork
            begin
                axi_threads_proc = process::self(); // It store the handle of the outerblock
                fork
                    drive_aw();
                    drive_w();
                    drive_b();
                    drive_ar();
                    drive_r();
                join
            end
        join_none
        
    endtask

    task automatic drive_aw(); 
        axi4_transaction trx;
        forever begin
            
            mbx_aw.get(trx);
        
            vif.AWVALID <= 1'b1;
            vif.AWADDR <= trx.AXADDR;
            vif.AWBURST <= trx.AXBURST;
            vif.AWID <= trx.AXID;
            vif.AWLEN <= trx.AXLEN;
            vif.AWSIZE <= trx.AXSIZE;
            vif.AWLOCK <= trx.AXLOCK;
            vif.AWCACHE <= trx.AXCACHE;
            vif.AWPROT <= trx.AXPROT;
            vif.AWQOS <= trx.AXQOS;

            do begin  @(posedge vif.ACLK);  end while(vif.AWREADY !== 1'b1 && vif.ARESETN !== 1'b0);

            vif.AWVALID <= 1'b0;

        end
    endtask

    task automatic drive_w(); 
        axi4_transaction trx;
        forever begin
            mbx_w.get(trx);
            vif.WVALID <= 1'b1;
            foreach(trx.WDATA[i]) begin
                if(vif.ARESETN === 1'b0) break;

                vif.WDATA <= trx.WDATA[i];
                vif.WSTRB <= trx.WSTRB[i];
                vif.WLAST <= (i == trx.WDATA.size() -1);

                do begin @(posedge vif.ACLK); end while(vif.WREADY !== 1'b1 && vif.ARESETN !== 1'b0);

            end

            vif.WLAST <= 1'b0;
            vif.WVALID <= 1'b0;

           
            
        end
    endtask

    task automatic drive_ar(); 

        axi4_transaction trx;
        forever begin
            mbx_ar.get(trx);
            @(posedge vif.ACLK);
            vif.ARVALID <= 1'b1;
            vif.ARADDR <= trx.AXADDR;
            vif.ARBURST <= trx.AXBURST;
            vif.ARID <= trx.AXID;
            vif.ARLEN <= trx.AXLEN;
            vif.ARSIZE <= trx.AXSIZE;
            vif.ARLOCK <= trx.AXLOCK;
            vif.ARCACHE <= trx.AXCACHE;
            vif.ARPROT <= trx.AXPROT;
            vif.ARQOS <= trx.AXQOS;

            do begin
                @(posedge vif.ACLK);
            end while(vif.ARREADY !== 1'b1);
            

            vif.ARVALID <= 1'b0;

        end

    endtask

    task automatic drive_b();
        vif.BREADY <= 1'b1;
        forever begin
            vif.BREADY <= 1'b1;
            @(posedge vif.ACLK iff (vif.BVALID === 1'b1));
            slots.put(1);                       // write fully complete
        end
    endtask

    task automatic drive_r();
        vif.RREADY <= 1'b1;
        forever begin
            vif.RREADY <= 1'b1;
            @(posedge vif.ACLK iff (vif.RVALID === 1'b1 && vif.RLAST === 1'b1));
            slots.put(1);                       // read fully complete
        end
    endtask

endclass