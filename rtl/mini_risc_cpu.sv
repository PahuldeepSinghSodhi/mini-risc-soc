// One outstanding transaction per port. Word addresses; target = current PC+offset.
module mini_risc_cpu
  import mini_risc_pkg::*;
(
  input logic clk, rst_n,
  output logic imem_req,
  output logic [31:0] imem_addr,
  input logic imem_ready, imem_error,
  input logic [31:0] imem_rdata,
  output logic dmem_req, dmem_write,
  output logic [31:0] dmem_addr, dmem_wdata,
  input logic dmem_ready, dmem_error,
  input logic [31:0] dmem_rdata,
  output logic halted,
  output fault_t fault_cause,
  output logic [31:0] fault_pc, pc,
  output logic retire_valid
`ifndef SYNTHESIS
  ,output logic [31:0] debug_regs [16],
  output logic [31:0] retire_pc, retire_instr
`endif
);
  typedef enum logic [1:0] {FETCH, EXECUTE, MEMORY, STOPPED} state_t;
  state_t state;
  logic [31:0] instr, next_pc, immediate, a, b, alu_b, result, write_data;
  logic [31:0] saved_addr, saved_data;
  logic saved_write;
  logic [3:0] rd, rs1, rs2;
  logic [19:0] imm20;
  logic [23:0] imm24;
  opcode_t opcode;
  funct_t funct;
  fmt_t fmt;
  alu_op_t alu_op;
  wb_src_t wb_src;
  logic reg_write, mem_read, mem_write, alu_src, pc_src, halt, illegal;
  logic zero, negative, overflow, encoding_illegal, register_enable;
  logic [31:0] registers [16];
  instruction_decoder dec(.*);
  immediate_generator imm(.opcode(opcode), .imm20(imm20), .imm24(imm24), .imm_out(immediate));
  control_unit control(.opcode(opcode), .funct(funct), .alu_zero(zero),
    .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
    .alu_src(alu_src), .alu_op(alu_op), .wb_src(wb_src), .pc_src(pc_src),
    .halt(halt), .illegal(illegal));
  assign alu_b = alu_src ? immediate : b;
  alu arithmetic(.operand_a(a), .operand_b(alu_b), .alu_op(alu_op),
    .result(result), .zero(zero), .negative(negative), .overflow(overflow));
  assign encoding_illegal = illegal || (opcode == OP_RTYPE && instr[15:4] != 0);
  assign next_pc = pc_src ? pc + immediate : pc + 32'd1;
  assign write_data = (state == MEMORY) ? dmem_rdata :
                       (wb_src == WB_PC_NEXT ? pc + 32'd1 : result);
  assign register_enable = rst_n &&
    ((state == EXECUTE && !encoding_illegal && !halt && !mem_read && !mem_write && reg_write) ||
     (state == MEMORY && dmem_ready && !dmem_error && !saved_write));
  register_file rf(.clk(clk), .rst_n(rst_n), .rs1_addr(rs1), .rs2_addr(rs2),
    .rs1_data(a), .rs2_data(b), .wen(register_enable), .rd_addr(rd),
    .rd_data(write_data), .regs_out(registers));
  assign halted = (state == STOPPED);
  assign imem_req = rst_n && (state == FETCH);
  assign imem_addr = pc;
  assign dmem_req = rst_n && (state == MEMORY);
  assign dmem_write = saved_write;
  assign dmem_addr = saved_addr;
  assign dmem_wdata = saved_data;
`ifndef SYNTHESIS
  assign debug_regs = registers;
`endif

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= FETCH; pc <= 0; instr <= 0;
      saved_addr <= 0; saved_data <= 0; saved_write <= 0;
      fault_cause <= FAULT_NONE; fault_pc <= 0; retire_valid <= 0;
`ifndef SYNTHESIS
      retire_pc <= 0; retire_instr <= 0;
`endif
    end else begin
      retire_valid <= 0;
      case (state)
        FETCH: if (imem_ready) begin
          if (imem_error) begin
            state <= STOPPED; fault_cause <= FAULT_INSTRUCTION; fault_pc <= pc;
          end else begin instr <= imem_rdata; state <= EXECUTE; end
        end
        EXECUTE: begin
          if (encoding_illegal) begin
            state <= STOPPED; fault_cause <= FAULT_ILLEGAL; fault_pc <= pc;
          end else if (mem_read || mem_write) begin
            saved_addr <= result; saved_data <= b; saved_write <= mem_write;
            state <= MEMORY;
          end else begin
            retire_valid <= 1;
`ifndef SYNTHESIS
            retire_pc <= pc; retire_instr <= instr;
`endif
            if (halt) state <= STOPPED;
            else begin pc <= next_pc; state <= FETCH; end
          end
        end
        MEMORY: if (dmem_ready) begin
          if (dmem_error) begin
            state <= STOPPED; fault_cause <= FAULT_DATA; fault_pc <= pc;
          end else begin
            retire_valid <= 1; pc <= pc + 32'd1; state <= FETCH;
`ifndef SYNTHESIS
            retire_pc <= pc; retire_instr <= instr;
`endif
          end
        end
        STOPPED: state <= STOPPED;
        default: state <= STOPPED;
      endcase
    end
  end
`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    assert (registers[0] == 0) else $fatal(1, "R0 changed");
    if (halted) assert (!register_enable && !imem_req && !dmem_req)
      else $fatal(1, "Stopped CPU caused a side effect");
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    imem_req && !imem_ready |=> imem_req && $stable(imem_addr));
  assert property (@(posedge clk) disable iff (!rst_n)
    dmem_req && !dmem_ready |=> dmem_req && $stable({dmem_addr,dmem_write,dmem_wdata}));
  assert property (@(posedge clk) disable iff (!rst_n)
    halted |=> halted && $stable(pc));
`endif
endmodule
