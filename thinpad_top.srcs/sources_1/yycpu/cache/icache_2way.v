//两路组相联，最近最少替换策略

module icache_2way (
    input wire                                  clk,
    input wire                                  rst,
    // CPU 接口
    (* DONT_TOUCH = "1" *) input    wire[31:0]  pc_i,              // CPU 请求的指令地址
    (* DONT_TOUCH = "1" *) input    wire        rom_ce_n_i,        // 指令存储器片选信号，低电平有效
    output   reg [31:0]                         inst_o,            // 输出的指令
    output   reg                                stall_from_icache, // 缓存暂停信号
    
    // SRAM 接口
    input wire                                  stall_from_bus,    // 总线暂停信号
    input wire [31:0]                           inst_i             // 从 SRAM 读取的指令
);

parameter SET_NUM = 16;     //
parameter WAY_NUM = 2;      //两路组相联
parameter TAG = 16;
parameter SET_INDEX = 4;

reg [31:0] cache_mem[0:SET_NUM-1][0:WAY_NUM-1];
reg [TAG-1:0] cache_tag[0:SET_NUM-1][0:WAY_NUM-1];
reg [WAY_NUM-1:0] cache_valid [0:SET_NUM-1];
reg [SET_NUM-1:0] lru;

parameter IDLE = 0;
parameter READ_SRAM = 1;
reg [1:0] state, next_state;

always @(posedge clk or posedge rst) begin
    if (rst) state <= IDLE;
    else state <= next_state;
end

wire [TAG-1:0] ram_tag_i = rom_addr_i[21:6];
wire [SET_INDEX-1:0] ram_set_i = rom_addr_i[5:2];

wire [WAY_NUM-1:0] hit;
assign hit[0] = (state == IDLE) ? cache_valid[ram_set_i][0] && (cache_tag[ram_set_i][0] == ram_tag_i) : 1'b0;
assign hit[1] = (state == IDLE) ? cache_valid[ram_set_i][1] && (cache_tag[ram_set_i][1] == ram_tag_i) : 1'b0;

wire cache_hit = hit[0] | hit[1];

reg finish_read;
integer i, j;

always @(*) begin
    if (rst) begin
        finish_read = 1'b0;
        inst_o = 32'd0;
    end else begin
        case (state)
            IDLE: begin
                finish_read = 1'b0;       
                if (cache_hit && ~stall_from_bus) begin
                    inst_o = hit[0] ? cache_mem[ram_set_i][0] : cache_mem[ram_set_i][1];
                end else begin
                    inst_o = 32'd0;
                end
            end
            READ_SRAM: begin       
                inst_o = inst_i;
                finish_read = 1'b1;   
            end
            default: begin 
                finish_read = 1'b0;
                inst_o = 32'hzzzzzzzz;
            end
        endcase
    end
end


wire rst_n = ~rst;
always @(posedge clk or posedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < SET_NUM; i = i + 1) begin
            for (j = 0; j < WAY_NUM; j = j + 1) begin
                cache_mem[i][j] <= 32'b0;
                cache_tag[i][j] <= 16'b0;
            end
            cache_valid[i] <= 2'b00;
        end
        lru <= 16'b0;
    end else begin
        case (state)
            IDLE: begin
                if (cache_hit) begin
                    lru[ram_set_i] <= hit[0]; // Update LRU
                end
            end
            READ_SRAM: begin
                if (finish_read) begin
                    if (~cache_valid[ram_set_i][0] || lru[ram_set_i]) begin
                        cache_mem[ram_set_i][0] <= inst_i;
                        cache_valid[ram_set_i][0] <= 1'b1;
                        cache_tag[ram_set_i][0] <= ram_tag_i;
                        lru[ram_set_i] <= 1'b1; // Set LRU to way 1
                    end else begin
                        cache_mem[ram_set_i][1] <= inst_i;
                        cache_valid[ram_set_i][1] <= 1'b1;
                        cache_tag[ram_set_i][1] <= ram_tag_i;
                        lru[ram_set_i] <= 1'b0; // Set LRU to way 0
                    end
                end
            end
        endcase
    end
end

always @(*) begin
    if (rst) begin
        stall_from_icache = 1'b0;     
        next_state = READ_SRAM;
    end else begin
        case (state)
            IDLE: begin
                if ( ~rom_ce_n_i && ~cache_hit && ~stall_from_bus) begin
                    next_state = READ_SRAM;
                    stall_from_icache = 1'b1;
                end else begin
                    next_state = IDLE;
                    stall_from_icache = 1'b0;
                end
            end
            READ_SRAM: begin
                if (finish_read) begin
                    next_state = IDLE;
                    stall_from_icache = 1'b0;
                end else begin
                    next_state = READ_SRAM;
                    stall_from_icache = 1'b1;  
                end 
            end
            default: begin 
                next_state = IDLE;
                stall_from_icache = 1'b0;
            end
        endcase
    end
end

endmodule