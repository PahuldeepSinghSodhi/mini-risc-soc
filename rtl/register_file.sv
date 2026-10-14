// =============================================================================
// MiniRISC CPU — Register File
// =============================================================================
// 16 × 32-bit register file.
//   • 2 asynchronous (combinational) read ports  — rs1, rs2
//   • 1 synchronous write port                   — rd  (posedge clk)
//   • R0 is hardwired to zero: writes to R0 are silently discarded.
//   • Full register state exposed via regs_out for debug / monitoring.
// =============================================================================

module register_file
  import mini_risc_pkg::*;
(
  input  logic                   clk,
  input  logic                   rst_n,

  // Read port 1 (combinational)
  input  logic [REG_ADDR_W-1:0]  rs1_addr,
  output logic [DATA_WIDTH-1:0]  rs1_data,

  // Read port 2 (combinational)
  input  logic [REG_ADDR_W-1:0]  rs2_addr,
  output logic [DATA_WIDTH-1:0]  rs2_data,

  // Write port (synchronous, rising edge)
  input  logic                   wen,
  input  logic [REG_ADDR_W-1:0]  rd_addr,
  input  logic [DATA_WIDTH-1:0]  rd_data,

  // Debug: expose entire register bank
  output logic [DATA_WIDTH-1:0]  regs_out [REG_COUNT]
);

  // Storage
  logic [DATA_WIDTH-1:0] regs [REG_COUNT];

  // --- Combinational reads --------------------------------------------------
  assign rs1_data = (rs1_addr == 0) ? '0 : regs[rs1_addr];
  assign rs2_data = (rs2_addr == 0) ? '0 : regs[rs2_addr];

  // --- Synchronous write with R0 protection ---------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < REG_COUNT; i++)
        regs[i] <= '0;
    end else if (wen && (rd_addr != {REG_ADDR_W{1'b0}})) begin
      regs[rd_addr] <= rd_data;
    end
  end

  // Debug output
  assign regs_out = regs;

endmodule
