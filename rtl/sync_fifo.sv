// Small register FIFO. A pop at full capacity frees a slot for the same-edge push.
module sync_fifo #(
  parameter int WIDTH = 8, DEPTH = 16,
  parameter int ADDR_W = $clog2(DEPTH), COUNT_W = $clog2(DEPTH+1)
)(
  input logic clk, rst_n, push, pop,
  input logic [WIDTH-1:0] data_in,
  output logic [WIDTH-1:0] data_out,
  output logic empty, full, accepted,
  output logic [COUNT_W-1:0] count, high_water,
  output logic [31:0] dropped
);
  logic [WIDTH-1:0] storage [DEPTH];
  logic [ADDR_W-1:0] head, tail;
  logic take_pop;
  assign empty = (count == 0);
  assign full = (count == COUNT_W'(DEPTH));
  assign take_pop = pop && !empty;
  assign accepted = push && (!full || take_pop);
  assign data_out = empty ? '0 : storage[head];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin head <= 0; tail <= 0; count <= 0; high_water <= 0; dropped <= 0; end
    else begin
      if (accepted) begin
        storage[tail] <= data_in;
        tail <= tail == ADDR_W'(DEPTH-1) ? '0 : tail + 1'b1;
      end
      if (take_pop) head <= head == ADDR_W'(DEPTH-1) ? '0 : head + 1'b1;
      case ({accepted,take_pop})
        2'b10: begin
          count <= count + 1'b1;
          if (count + 1'b1 > high_water) high_water <= count + 1'b1;
        end
        2'b01: count <= count - 1'b1;
        default: ;
      endcase
      if (push && !accepted) dropped <= dropped + 32'd1;
    end
  end
`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    assert (int'(count) <= DEPTH) else $fatal(1, "FIFO overflow");
    assert (high_water >= count) else $fatal(1, "Invalid FIFO high-water mark");
  end
`endif
endmodule
