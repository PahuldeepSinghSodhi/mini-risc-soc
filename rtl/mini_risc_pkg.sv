// =============================================================================
// MiniRISC CPU — Package Definitions
// =============================================================================
// Shared type definitions, parameters, and constants used across all RTL
// modules and the verification testbench.
//
// Architecture: 32-bit, 16 registers, word-addressed, multicycle.
// =============================================================================

package mini_risc_pkg;

  // --------------------------------------------------------------------------
  // Datapath Parameters
  // --------------------------------------------------------------------------
  parameter int DATA_WIDTH  = 32;
  parameter int REG_COUNT   = 16;
  parameter int REG_ADDR_W  = 4;
  parameter int IMEM_DEPTH  = 256;   // 256 words (1 KB)
  parameter int DMEM_DEPTH  = 256;   // 256 words (1 KB)
  parameter int IMEM_ADDR_W = 8;
  parameter int DMEM_ADDR_W = 8;

  // --------------------------------------------------------------------------
  // Opcode Enumeration  (instruction bits [31:28])
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    OP_RTYPE = 4'h0,   // R-type ALU operations (funct selects)
    OP_ADDI  = 4'h1,   // Add immediate
    OP_ANDI  = 4'h2,   // AND immediate
    OP_ORI   = 4'h3,   // OR  immediate
    OP_LW    = 4'h4,   // Load word
    OP_SW    = 4'h5,   // Store word
    OP_BEQ   = 4'h6,   // Branch if equal
    OP_BNE   = 4'h7,   // Branch if not equal
    OP_JAL   = 4'h8,   // Jump and link
    OP_LUI   = 4'h9,   // Load upper immediate
    OP_SLTI  = 4'hA,   // Set less-than immediate (signed)
    OP_HALT  = 4'hF    // Halt execution
  } opcode_t;

  // --------------------------------------------------------------------------
  // R-type Function Code Enumeration  (instruction bits [3:0])
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    F_ADD = 4'h0,
    F_SUB = 4'h1,
    F_AND = 4'h2,
    F_OR  = 4'h3,
    F_XOR = 4'h4,
    F_SLT = 4'h5,
    F_SLL = 4'h6,
    F_SRL = 4'h7
  } funct_t;

  // --------------------------------------------------------------------------
  // ALU Operation Enumeration
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD    = 4'h0,
    ALU_SUB    = 4'h1,
    ALU_AND    = 4'h2,
    ALU_OR     = 4'h3,
    ALU_XOR    = 4'h4,
    ALU_SLT    = 4'h5,
    ALU_SLL    = 4'h6,
    ALU_SRL    = 4'h7,
    ALU_PASS_B = 4'h8   // Pass operand_b through (used for LUI)
  } alu_op_t;

  // --------------------------------------------------------------------------
  // Write-Back Source Enumeration
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    WB_ALU = 2'b00,    // ALU result
    WB_MEM = 2'b01,    // Data-memory read data
    WB_PC_NEXT = 2'b10, // PC + 1 (word-addressed JAL return address)
    WB_IMM = 2'b11     // Immediate  (reserved / future use)
  } wb_src_t;

  // --------------------------------------------------------------------------
  // Instruction Format Enumeration
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    FMT_RTYPE = 3'b000,
    FMT_ITYPE = 3'b001,
    FMT_STYPE = 3'b010,
    FMT_BTYPE = 3'b011,
    FMT_JTYPE = 3'b100,
    FMT_ILLEGAL = 3'b110,
    FMT_HALT  = 3'b111
  } fmt_t;

  typedef enum logic [1:0] {
    FAULT_NONE = 2'd0, FAULT_ILLEGAL = 2'd1,
    FAULT_INSTRUCTION = 2'd2, FAULT_DATA = 2'd3
  } fault_t;

  localparam logic [31:0] SENSOR_STATUS = 32'h100, SENSOR_DATA = 32'h101,
    SENSOR_DROPPED = 32'h102, SENSOR_HIGH_WATER = 32'h103,
    UART_STATUS = 32'h110, UART_RX_DATA = 32'h111, UART_TX_DATA = 32'h112,
    UART_RX_DROPPED = 32'h113, UART_FRAME_ERRORS = 32'h114,
    TIMER_CYCLES = 32'h120, INSTRUCTIONS_RETIRED = 32'h121, GPIO = 32'h130;

endpackage
