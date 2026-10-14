// UART 8N1, LSB first; RX synchronizer and independent 16-byte RX/TX FIFOs.
module uart #(parameter int CLKS_PER_BIT = 16)(
  input logic clk, rst_n, rx,
  output logic tx,
  input logic tx_push,
  input logic [7:0] tx_data,
  output logic tx_space, tx_idle,
  input logic rx_pop,
  output logic [7:0] rx_data,
  output logic rx_available,
  output logic [31:0] rx_dropped, framing_errors
);
  localparam int CW = $clog2(CLKS_PER_BIT+1);
  logic [CW-1:0] tx_count, rx_count;
  logic [3:0] tx_bit;
  logic [2:0] rx_bit;
  logic tx_busy, tx_empty, tx_full, tx_pop;
  logic [7:0] tx_front, rx_shift;
  logic [9:0] tx_shift;
  logic rx_meta, rx_sync, rx_push, rx_empty;
  typedef enum logic [1:0] {RX_IDLE, RX_START, RX_BITS, RX_STOP} rx_state_t;
  rx_state_t rx_state;
  assign tx_pop = !tx_busy && !tx_empty;
  assign tx_space = !tx_full || tx_pop;
  assign tx_idle = !tx_busy && tx_empty;
  assign rx_available = !rx_empty;
  sync_fifo tx_fifo(.clk(clk), .rst_n(rst_n), .push(tx_push), .pop(tx_pop),
    .data_in(tx_data), .data_out(tx_front), .empty(tx_empty), .full(tx_full),
    .accepted(), .count(), .high_water(), .dropped());
  sync_fifo rx_fifo(.clk(clk), .rst_n(rst_n), .push(rx_push), .pop(rx_pop),
    .data_in(rx_shift), .data_out(rx_data), .empty(rx_empty), .full(),
    .accepted(), .count(), .high_water(), .dropped(rx_dropped));
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx <= 1; tx_busy <= 0; tx_count <= 0; tx_bit <= 0; tx_shift <= '1;
      rx_meta <= 1; rx_sync <= 1; rx_state <= RX_IDLE; rx_count <= 0;
      rx_bit <= 0; rx_shift <= 0; rx_push <= 0; framing_errors <= 0;
    end else begin
      rx_meta <= rx; rx_sync <= rx_meta;
      rx_push <= 0;
      if (tx_pop) begin
        tx_shift <= {1'b1,tx_front,1'b0}; tx <= 0;
        tx_busy <= 1; tx_bit <= 0; tx_count <= CW'(CLKS_PER_BIT-1);
      end else if (tx_busy) begin
        if (tx_count != 0) tx_count <= tx_count - 1'b1;
        else if (tx_bit == 9) begin tx_busy <= 0; tx <= 1; end
        else begin
          tx_bit <= tx_bit + 1'b1; tx <= tx_shift[tx_bit+1'b1];
          tx_count <= CW'(CLKS_PER_BIT-1);
        end
      end
      case (rx_state)
        RX_IDLE: if (!rx_sync) begin
          rx_state <= RX_START; rx_count <= CW'(CLKS_PER_BIT/2-1);
        end
        RX_START: if (rx_count != 0) rx_count <= rx_count - 1'b1;
          else if (rx_sync) rx_state <= RX_IDLE;
          else begin rx_state <= RX_BITS; rx_bit <= 0; rx_count <= CW'(CLKS_PER_BIT-1); end
        RX_BITS: if (rx_count != 0) rx_count <= rx_count - 1'b1;
          else begin
            rx_shift[rx_bit] <= rx_sync; rx_count <= CW'(CLKS_PER_BIT-1);
            if (rx_bit == 7) rx_state <= RX_STOP;
            else rx_bit <= rx_bit + 1'b1;
          end
        RX_STOP: if (rx_count != 0) rx_count <= rx_count - 1'b1;
          else begin
            rx_state <= RX_IDLE;
            if (rx_sync) rx_push <= 1;
            else framing_errors <= framing_errors + 32'd1;
          end
        default: rx_state <= RX_IDLE;
      endcase
    end
  end
endmodule
