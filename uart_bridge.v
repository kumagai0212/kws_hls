module uart_bridge #(
    parameter SYSTEM_CLOCK = 120000000,
    parameter UART_CLOCK = 1000000
)(
    input wire clk_i,
    output wire tx_o,
    input wire rx_i,
    input wire [7:0]  wdata_i,
    input wire we_i,
    output wire [7:0] data_frame_o,
    output wire data_valid_o,
    output wire ready_o
);

    localparam [2:0] IDLE = 3'd0,
                     WAIT = 3'd1,
                     READ = 3'd2,
                     WRITE = 3'd3,
                     STOP = 3'd4;

    reg [7:0] data_frame;
    reg [3:0] bit_count = 4'b0; 
    reg [2:0] state = 3'b0;
    reg one_count = 1'b0;
    reg data_valid = 0;
    wire [9:0] send_frame;
    reg ready = 1;
    reg tx = 1'b1;
    reg is_tx = 1'b0;

    assign data_frame_o = data_frame;
    assign data_valid_o = data_valid;
    assign send_frame = {1'b1, wdata_i, 1'b0}; //stop_bit, data frame, start_bit
    assign ready_o = ready;
    assign tx_o = tx;

    //uart clock generation(9600 bps)
    localparam DIV_CLOCK = SYSTEM_CLOCK / (UART_CLOCK*2);
    localparam DIV_CLOCK_HALF = DIV_CLOCK / 2;
    reg clk_uart = 0;
    reg [19:0] clk_count = DIV_CLOCK, clk_count_half = 0;
    reg clk_reset = 0;
    always @(posedge clk_i) begin
        if (!clk_reset) begin
            clk_count <= DIV_CLOCK;
            clk_uart <= we_i ? 1'b1 : 1'b0;
        end else begin
            if(clk_count >= DIV_CLOCK) begin
                clk_uart <= ~clk_uart;
                clk_count <= 20'b0;
            end else begin
                clk_count <= clk_count + 1;
            end
        end
    end

    wire clk_uart_posdge, clk_uart_negedge;
    reg clk_uart_sync = 0;
    always @(posedge clk_i) begin
        clk_uart_sync <= clk_uart;
    end
    assign clk_uart_posdge = !clk_uart_sync & clk_uart;
    assign clk_uart_negedge = clk_uart_sync & !clk_uart;

    always @(posedge clk_i) begin
        case (state)
            IDLE : begin
                clk_count_half <= 20'b0;
                clk_reset <= 1'b0;
                data_valid <= 1'b0;
                bit_count <= 4'b0;
                one_count <= 1'b0;
                ready <= 1'b1;
                
                if (!rx_i) begin //detect star_bit is low(data read)
                    state <= WAIT;
                    ready <= 1'b0;
                    is_tx <= 1'b0;
                end
                if (we_i) begin
                    state <= WAIT;
                    tx <= 1'b1;
                    is_tx <= we_i;
                    ready <= 1'b0; //Enable we_i low 
                end
            end 
            WAIT : begin //wait for 1/4 freq
                if (clk_count_half >= DIV_CLOCK_HALF) begin
                    clk_reset <= 1'b1;
                    // state <= FINISH;
                    state <= is_tx ? WRITE : READ;
                end else begin
                    clk_count_half <= clk_count_half + 1;
                end   
            end
            READ : begin
                if(clk_uart_posdge) begin //posedge clk_uart
                    bit_count <= bit_count + 1;
                    one_count <= rx_i ? ~one_count : one_count; //count of 1 bit
                    data_frame[bit_count] <= rx_i; 
                    if(bit_count == 4'd7) state <= STOP;
                end
            end
            WRITE: begin //start bit = 1bit, stop bit = 1bit, Parity Bit = 0bit
                if(clk_uart_negedge) begin
                    bit_count <= bit_count + 1;
                    if (bit_count >= 10) begin
                        state <= IDLE;
                    end else begin
                        tx <= send_frame[bit_count];    
                    end
                end
            end
            STOP : begin
                if (clk_uart_posdge) begin
                    bit_count <= bit_count + 1;
                    if(rx_i) begin //detect stop bit is high
                        state <= IDLE;
                        // {data_frame, data_valid} <= !one_count ? 9'b0 : {data_frame, 1'b1}; //error check
                        {data_frame, data_valid} <= {data_frame, 1'b1};
                        bit_count <= 4'b0;
                        one_count <= 1'b0;
                        clk_reset <= 1'b0;
                    end else if(bit_count >= 10) begin //stop bit keeps low
                        state <= IDLE;
                        data_valid <= 1'b0;
                        bit_count <= 4'b0;
                        one_count <= 1'b0;
                        clk_reset <= 1'b0;
                    end
                end
            end
            default: state <= 3'b0; 
        endcase
    end

endmodule