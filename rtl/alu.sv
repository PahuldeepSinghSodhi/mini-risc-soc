// =============================================================================
// MiniRISC CPU — Arithmetic Logic Unit (ALU)
// =============================================================================
// Combinational ALU supporting 9 operations.  SLT uses signed comparison.
// Flags: zero, negative, overflow (signed ADD/SUB only).
// =============================================================================

module alu
  import mini_risc_pkg::*;
(
  input  logic [DATA_WIDTH-1:0] operand_a,
  input  logic [DATA_WIDTH-1:0] operand_b,
  input  alu_op_t               alu_op,

  output logic [DATA_WIDTH-1:0] result,
  output logic                  zero,
  output logic                  negative,
  output logic                  overflow
);

  // Internal intermediate results
  logic [DATA_WIDTH-1:0] add_result;
  logic [DATA_WIDTH-1:0] sub_result;
  logic                  add_overflow;
  logic                  sub_overflow;

  // Addition / subtraction with signed-overflow detection
  assign add_result   = operand_a + operand_b;
  assign sub_result   = operand_a - operand_b;

  // Signed overflow: operand signs agree but result sign differs
  assign add_overflow = (operand_a[DATA_WIDTH-1] == operand_b[DATA_WIDTH-1]) &&
                        (add_result[DATA_WIDTH-1] != operand_a[DATA_WIDTH-1]);
  assign sub_overflow = (operand_a[DATA_WIDTH-1] != operand_b[DATA_WIDTH-1]) &&
                        (sub_result[DATA_WIDTH-1] != operand_a[DATA_WIDTH-1]);

  always_comb begin
    result   = '0;
    overflow = 1'b0;

    case (alu_op)
      ALU_ADD: begin
        result   = add_result;
        overflow = add_overflow;
      end

      ALU_SUB: begin
        result   = sub_result;
        overflow = sub_overflow;
      end

      ALU_AND:    result = operand_a & operand_b;
      ALU_OR:     result = operand_a | operand_b;
      ALU_XOR:    result = operand_a ^ operand_b;

      ALU_SLT:    // Signed less-than comparison
        result = {{(DATA_WIDTH-1){1'b0}}, ($signed(operand_a) < $signed(operand_b))};

      ALU_SLL:    result = operand_a << operand_b[4:0];
      ALU_SRL:    result = operand_a >> operand_b[4:0];
      ALU_PASS_B: result = operand_b;

      default:    result = '0;
    endcase
  end

  // Status flags (always valid)
  assign zero     = (result == '0);
  assign negative = result[DATA_WIDTH-1];

endmodule
