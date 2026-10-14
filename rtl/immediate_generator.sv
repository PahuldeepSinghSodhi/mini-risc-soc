// =============================================================================
// MiniRISC CPU — Immediate Generator
// =============================================================================
// Produces the 32-bit sign-extended (or shifted) immediate value from the raw
// instruction fields, based on the opcode.
//
// Word-addressed architecture — branch/jump offsets are in words (no <<2).
//
//   LUI:            {imm20, 12'b0}           upper-immediate load
//   JAL:            sign_extend(imm24)        PC-relative word offset
//   Everything else: sign_extend(imm20)       signed 20-bit immediate
// =============================================================================

module immediate_generator
  import mini_risc_pkg::*;
(
  input  opcode_t               opcode,
  input  logic [19:0]           imm20,
  input  logic [23:0]           imm24,

  output logic [DATA_WIDTH-1:0] imm_out
);

  always_comb begin
    case (opcode)
      OP_LUI:  imm_out = {imm20, 12'b0};                  // Upper immediate
      OP_JAL:  imm_out = {{8{imm24[23]}},  imm24};         // Sign-extend 24→32
      default: imm_out = {{12{imm20[19]}}, imm20};          // Sign-extend 20→32
    endcase
  end

endmodule
