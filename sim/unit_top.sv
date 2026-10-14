module unit_top
  import mini_risc_pkg::*;
(
  input logic clk, rst_n,
  input logic [31:0] a,b,
  input alu_op_t op,
  output logic [31:0] result,
  output logic zero,negative,overflow,
  input logic [3:0] r1,r2,rd,
  input logic wen,
  input logic [31:0] wdata,
  output logic [31:0] rdata1,rdata2,
  input logic push,pop,
  input logic [7:0] din,
  output logic [7:0] front,
  output logic empty,full,accepted,
  output logic [4:0] count,high_water,
  output logic [31:0] dropped,
  input logic rx,tx_push,rx_pop,
  input logic [7:0] tx_data,
  output logic tx,tx_space,tx_idle,rx_available,
  output logic [7:0] rx_data,
  output logic [31:0] rx_dropped,framing_errors
);
  alu arithmetic(.operand_a(a),.operand_b(b),.alu_op(op),.*);
  register_file registers(.clk(clk),.rst_n(rst_n),.rs1_addr(r1),.rs2_addr(r2),
    .rs1_data(rdata1),.rs2_data(rdata2),.wen(wen),.rd_addr(rd),.rd_data(wdata),.regs_out());
  sync_fifo fifo(.clk(clk),.rst_n(rst_n),.push(push),.pop(pop),.data_in(din),
    .data_out(front),.empty(empty),.full(full),.accepted(accepted),.count(count),
    .high_water(high_water),.dropped(dropped));
  uart serial(.*);
endmodule
