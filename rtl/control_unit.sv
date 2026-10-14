// =============================================================================
// MiniRISC CPU — Control Unit
// =============================================================================
// Purely combinational logic that takes the decoded opcode and funct fields
// and generates all control signals for the datapath.
// =============================================================================

module control_unit
  import mini_risc_pkg::*;
(
  input  opcode_t       opcode,
  input  funct_t        funct,
  input  logic          alu_zero,     // Equality from ALU subtraction

  output logic          reg_write,
  output logic          mem_read,
  output logic          mem_write,
  output logic          alu_src,      // 0: rs2, 1: immediate
  output alu_op_t       alu_op,
  output wb_src_t       wb_src,       // 00: ALU, 01: Mem, 10: PC+1
  output logic          pc_src,       // 0: PC+1, 1: current PC + offset
  output logic          halt,
  output logic          illegal
);

  // Keep equality-dependent PC selection separate from ALU operation decoding.
  assign pc_src = (opcode == OP_JAL) || (opcode == OP_BEQ && alu_zero) ||
                  (opcode == OP_BNE && !alu_zero);

  always_comb begin
    // Default assignments to prevent latches
    reg_write = 1'b0;
    mem_read  = 1'b0;
    mem_write = 1'b0;
    alu_src   = 1'b0;
    alu_op    = ALU_ADD;
    wb_src    = WB_ALU;
    halt      = 1'b0;
    illegal   = 1'b0;

    case (opcode)
      OP_RTYPE: begin
        reg_write = (funct <= F_SRL);
        illegal   = (funct > F_SRL);
        alu_src   = 1'b0; // Use rs2
        wb_src    = WB_ALU;
        // Map funct directly to ALU op (they match by design)
        alu_op    = alu_op_t'(funct);
      end

      OP_ADDI: begin
        reg_write = 1'b1;
        alu_src   = 1'b1; // Use immediate
        wb_src    = WB_ALU;
        alu_op    = ALU_ADD;
      end

      OP_ANDI: begin
        reg_write = 1'b1;
        alu_src   = 1'b1;
        wb_src    = WB_ALU;
        alu_op    = ALU_AND;
      end

      OP_ORI: begin
        reg_write = 1'b1;
        alu_src   = 1'b1;
        wb_src    = WB_ALU;
        alu_op    = ALU_OR;
      end

      OP_LW: begin
        reg_write = 1'b1;
        alu_src   = 1'b1;
        wb_src    = WB_MEM;
        mem_read  = 1'b1;
        alu_op    = ALU_ADD; // address = rs1 + imm
      end

      OP_SW: begin
        mem_write = 1'b1;
        alu_src   = 1'b1;
        alu_op    = ALU_ADD; // address = rs1 + imm
      end

      OP_BEQ: begin
        alu_src   = 1'b0;
        alu_op    = ALU_SUB; // Compare by subtracting
      end

      OP_BNE: begin
        alu_src   = 1'b0;
        alu_op    = ALU_SUB;
      end

      OP_JAL: begin
        reg_write = 1'b1;
        wb_src    = WB_PC_NEXT; // Save word address PC+1
      end

      OP_LUI: begin
        reg_write = 1'b1;
        alu_src   = 1'b1;
        wb_src    = WB_ALU;
        alu_op    = ALU_PASS_B; // Pass immediate through ALU
      end

      OP_SLTI: begin
        reg_write = 1'b1;
        alu_src   = 1'b1;
        wb_src    = WB_ALU;
        alu_op    = ALU_SLT;
      end

      OP_HALT: begin
        halt = 1'b1;
      end

      default: illegal = 1'b1;
    endcase
  end

endmodule
