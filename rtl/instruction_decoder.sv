// =============================================================================
// MiniRISC CPU — Instruction Decoder
// =============================================================================
// Extracts all fields from the 32-bit instruction word and determines the
// instruction format based on the opcode.
//
// Encoding formats:
//   R-type: [31:28 opcode=0] [27:24 rd ] [23:20 rs1] [19:16 rs2] [15:4 rsvd] [3:0 funct]
//   I-type: [31:28 opcode  ] [27:24 rd ] [23:20 rs1] [19:0 imm20                       ]
//   S-type: [31:28 opcode=5] [27:24 rs2] [23:20 rs1] [19:0 imm20                       ]
//   B-type: [31:28 opcode  ] [27:24 rs2] [23:20 rs1] [19:0 offset                      ]
//   J-type: [31:28 opcode=8] [27:24 rd ] [23:0  imm24                                  ]
// =============================================================================

module instruction_decoder
  import mini_risc_pkg::*;
(
  input  logic [DATA_WIDTH-1:0]  instr,

  output opcode_t                opcode,
  output logic [REG_ADDR_W-1:0]  rd,
  output logic [REG_ADDR_W-1:0]  rs1,
  output logic [REG_ADDR_W-1:0]  rs2,
  output funct_t                 funct,
  output logic [19:0]            imm20,
  output logic [23:0]            imm24,
  output fmt_t                   fmt
);

  // --- Field extraction (raw fields except normalized second source) --------
  assign opcode = opcode_t'(instr[31:28]);
  assign rd     = instr[27:24];
  assign rs1    = instr[23:20];
  // Normalize the source address; rd remains the raw upper field.
  assign rs2    = (opcode == OP_SW || opcode == OP_BEQ || opcode == OP_BNE)
                  ? instr[27:24] : instr[19:16];
  assign funct  = funct_t'(instr[3:0]);
  assign imm20  = instr[19:0];
  assign imm24  = instr[23:0];

  // --- Format determination from opcode --------------------------------------
  always_comb begin
    case (opcode)
      OP_RTYPE:                         fmt = FMT_RTYPE;
      OP_ADDI, OP_ANDI, OP_ORI,
      OP_LW,   OP_SLTI, OP_LUI:        fmt = FMT_ITYPE;
      OP_SW:                            fmt = FMT_STYPE;
      OP_BEQ,  OP_BNE:                 fmt = FMT_BTYPE;
      OP_JAL:                           fmt = FMT_JTYPE;
      OP_HALT:                          fmt = FMT_HALT;
      default:                          fmt = FMT_ILLEGAL;
    endcase
  end

endmodule
