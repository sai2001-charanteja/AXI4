typedef enum logic [1:0]{WRITE,READ,RESET} pkt_kind;
typedef enum logic [2:0] {AW,W,B,AR,R,RST} channel_kind;
class axi4_transaction extends uvm_sequence_item;
   // `uvm_object_utils(axi4_transaction)

    function new(string name = "axi4_transaction");
        super.new(name);
    endfunction
    
    rand pkt_kind kind;
    channel_kind channel;
    // AX channel
    rand bit [ID_WIDTH-1:0]   AXID; // we will chnage it when everything looks good
    rand bit [ADDR_WIDTH-1:0] AXADDR;
    rand bit [7:0]            AXLEN;
    rand bit [2:0]            AXSIZE;
    rand bit [1:0]            AXBURST;
    rand bit                  AXLOCK;
    rand bit [3:0]            AXCACHE;
    rand bit [2:0]            AXPROT;
    rand bit [3:0]            AXQOS;

        bit                  AXVALID;
        bit                  AXREADY;

    // Write data channel
    rand bit [DATA_WIDTH-1:0] WDATA [];
    rand bit [STRB_WIDTH-1:0] WSTRB [];
    bit                  WLAST;
    bit                  WVALID;
    bit                  WREADY;

    // Write response channel
    bit [ID_WIDTH-1:0]   BID;
    bit [1:0]            BRESP;
    bit                  BVALID;
    bit                  BREADY;

    

    // Read data channel
    bit [ID_WIDTH-1:0]   RID[$];
    bit [DATA_WIDTH-1:0] RDATA[$];
    bit [1:0]            RRESP[$];
    bit                  RLAST;
    bit                  RVALID;
    bit                  RREADY;
    

    `uvm_object_utils_begin(axi4_transaction)

        `uvm_field_enum(pkt_kind, kind, UVM_ALL_ON);
        `uvm_field_enum(channel_kind, channel, UVM_ALL_ON);
        `uvm_field_int(AXID, UVM_ALL_ON); 
        `uvm_field_int(AXADDR, UVM_ALL_ON);
        `uvm_field_int(AXLEN, UVM_ALL_ON);
        `uvm_field_int(AXSIZE, UVM_ALL_ON);
        `uvm_field_int(AXBURST, UVM_ALL_ON);
        `uvm_field_int(AXLOCK, UVM_ALL_ON);
        `uvm_field_int(AXCACHE, UVM_ALL_ON);
        `uvm_field_int(AXPROT, UVM_ALL_ON);
        `uvm_field_int(AXQOS, UVM_ALL_ON);
        `uvm_field_int(AXVALID, UVM_ALL_ON);
        `uvm_field_int(AXREADY, UVM_ALL_ON);
        `uvm_field_array_int(WDATA, UVM_ALL_ON);
        `uvm_field_array_int(WSTRB, UVM_ALL_ON);
        `uvm_field_int(WLAST, UVM_ALL_ON);
        `uvm_field_int(WVALID, UVM_ALL_ON);
        `uvm_field_int(WREADY, UVM_ALL_ON);
        `uvm_field_int(BID, UVM_ALL_ON);
        `uvm_field_int(BRESP, UVM_ALL_ON);
        `uvm_field_int(BVALID, UVM_ALL_ON);
        `uvm_field_int(BREADY, UVM_ALL_ON);
        `uvm_field_queue_int(RID, UVM_ALL_ON);
        `uvm_field_queue_int(RDATA, UVM_ALL_ON);
        `uvm_field_queue_int(RRESP, UVM_ALL_ON);
        `uvm_field_int(RLAST, UVM_ALL_ON);
        `uvm_field_int(RVALID, UVM_ALL_ON);
        `uvm_field_int(RREADY, UVM_ALL_ON);

    `uvm_object_utils_end
    constraint c_read_write_valid{
        kind inside {[WRITE:RESET]};
        // we can add the distribution here. 


    }

    constraint c_axchannel_valid{
        /*=====================      AXID     ===========================*/ 
        AXID inside {[0:$]};

        /*=====================      AXADDR     ===========================*/ 
        AXADDR inside {[32'h0000_0000 : 32'h0000_3EFF],[32'h0000_3F00:32'h0000_3FFF],[32'h0000_4000:32'h0000_7FFF],[32'h0000_8000:32'h0000_BFFF]};
        if(AXBURST == BURST_WRAP)
            AXADDR%(1<<AXSIZE) == 0;
        
        (AXADDR & 12'hFF) + (1<<AXSIZE)*(AXLEN+1) <= 4096;  //4kB boundary

        /*=====================      AXLEN      ===========================*/ 
        if(AXBURST == BURST_FIXED) AXLEN < 16;
        else if(AXBURST == BURST_WRAP) AXLEN inside {1,3,7,15};
        else AXLEN inside {[0:255]};

        if(AXLOCK == 1) AXLEN == 0;  // For exclusive access only single beat is allowed.

        /*=====================      AXSIZE      ===========================*/
        AXSIZE inside {[0:$clog2(STRB_WIDTH)]}; // means 1 to 4 bytes in each beat cause the bus width is only 4 bytes(32-bits)

        /*=====================      AXBURST      ===========================*/
        AXBURST inside {BURST_FIXED,BURST_INCR,BURST_WRAP};
        if(AXLOCK == 1) AXBURST == BURST_FIXED;

        /*=====================      AXLOCK      ===========================*/
        AXLOCK inside {0,1}; // Normal _ exclusive

        /*=====================      AXCACHE      ===========================*/
        AXCACHE inside {[0:15]};

        /*=====================      AXPROT      ===========================*/
        AXPROT inside {[0:7]};
        
        /*=====================      AXQOS      ===========================*/
        AXQOS inside {[0:15]};   
    }

    constraint c_wchannel_valid{
        /*=====================    WDATA        ===========================*/
        if(kind == WRITE)
            WDATA.size() == AXLEN + 1;
        else 
            WDATA.size() == 0;

        foreach(WDATA[i])
            WDATA[i] inside {[0:(1<<((1<<AXSIZE)<<3)) -1]};


        /*=====================      WSTRB      ===========================*/
        if(kind == WRITE) WSTRB.size() == AXLEN + 1;
        else WSTRB.size() == 0;

        foreach(WSTRB[i])
            WSTRB[i] inside {[0:(1<<STRB_WIDTH)-1]};
    }

    function void post_randomize();
        //AXID = AXID + 1; // It warps and resets 
        //pass
    endfunction 
    

endclass