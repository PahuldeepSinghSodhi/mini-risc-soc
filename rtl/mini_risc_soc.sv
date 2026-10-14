module mini_risc_soc
  import mini_risc_pkg::*;
#(parameter string IMEM_FILE = "build/firmware.hex", parameter int UART_CLKS_PER_BIT = 16)(
  input logic clk, rst_n,
  input logic [11:0] sample_data,
  input logic sample_valid, uart_rx,
  output logic uart_tx,
  output logic [31:0] gpio,
  output logic halted,
  output fault_t fault_cause,
  output logic [31:0] fault_pc
`ifndef SYNTHESIS
  ,input logic [7:0] debug_mem_addr,
  output logic [31:0] debug_mem_data, debug_cycles, debug_retired,
  output logic debug_sample_accepted, debug_sample_pop,
  output logic [11:0] debug_sample_value,
  output logic [4:0] debug_fifo_count, debug_high_water,
  output logic [31:0] debug_dropped, debug_pc,
  output logic debug_uart_idle
`endif
);
  logic [31:0] imem [IMEM_DEPTH], dmem [DMEM_DEPTH];
  initial begin
`ifndef SYNTHESIS
    string image;
    if ($value$plusargs("imem=%s", image)) $readmemh(image, imem);
    else $readmemh(IMEM_FILE, imem);
`else
    $readmemh(IMEM_FILE, imem);
`endif
  end
  logic ireq, iready, ierror, dreq, dready, derror, dwrite, retire;
  logic [31:0] iaddr, irdata, daddr, dwdata, drdata, pc, cycles, retired;
  logic [11:0] sensor_front;
  logic sensor_empty, sensor_full, sensor_pop, sensor_accepted;
  logic [4:0] sensor_count, sensor_high;
  logic [31:0] sensor_dropped;
  logic tx_push, tx_space, tx_idle, rx_pop, rx_available;
  logic [7:0] rx_data;
  logic [31:0] rx_dropped, frame_errors;
  logic can_complete, address_error;
  logic [31:0] read_value;
  mini_risc_cpu cpu(.clk(clk), .rst_n(rst_n), .imem_req(ireq), .imem_addr(iaddr),
    .imem_ready(iready), .imem_error(ierror), .imem_rdata(irdata),
    .dmem_req(dreq), .dmem_write(dwrite), .dmem_addr(daddr), .dmem_wdata(dwdata),
    .dmem_ready(dready), .dmem_error(derror), .dmem_rdata(drdata),
    .halted(halted), .fault_cause(fault_cause), .fault_pc(fault_pc), .pc(pc), .retire_valid(retire)
`ifndef SYNTHESIS
    ,.debug_regs(), .retire_pc(), .retire_instr()
`endif
  );
  sync_fifo #(.WIDTH(12)) sensor_fifo(.clk(clk), .rst_n(rst_n), .push(sample_valid),
    .pop(sensor_pop), .data_in(sample_data), .data_out(sensor_front), .empty(sensor_empty),
    .full(sensor_full), .accepted(sensor_accepted), .count(sensor_count),
    .high_water(sensor_high), .dropped(sensor_dropped));
  uart #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) serial(.clk(clk), .rst_n(rst_n),
    .rx(uart_rx), .tx(uart_tx), .tx_push(tx_push), .tx_data(dwdata[7:0]),
    .tx_space(tx_space), .tx_idle(tx_idle), .rx_pop(rx_pop), .rx_data(rx_data),
    .rx_available(rx_available), .rx_dropped(rx_dropped), .framing_errors(frame_errors));

  // Peripheral front values are sampled into drdata on the same edge as their pop.
  always_comb begin
    can_complete = 1; address_error = 0; read_value = 0;
    if (daddr < DMEM_DEPTH) read_value = dmem[daddr[7:0]];
    else case (daddr)
      SENSOR_STATUS: read_value = {16'b0,3'b0,sensor_count,6'b0,sensor_full,!sensor_empty};
      SENSOR_DATA: begin read_value = {20'b0,sensor_front}; can_complete = !sensor_empty; end
      SENSOR_DROPPED: read_value = sensor_dropped;
      SENSOR_HIGH_WATER: read_value = {27'b0,sensor_high};
      UART_STATUS: read_value = {29'b0,tx_idle,tx_space,rx_available};
      UART_RX_DATA: begin read_value = {24'b0,rx_data}; can_complete = rx_available; end
      UART_TX_DATA: begin can_complete = tx_space; if (!dwrite) address_error = 1; end
      UART_RX_DROPPED: read_value = rx_dropped;
      UART_FRAME_ERRORS: read_value = frame_errors;
      TIMER_CYCLES: read_value = cycles;
      INSTRUCTIONS_RETIRED: read_value = retired;
      GPIO: read_value = gpio;
      default: address_error = 1;
    endcase
    if (dwrite && daddr >= DMEM_DEPTH && daddr != UART_TX_DATA && daddr != GPIO)
      address_error = 1;
    if (address_error) can_complete = 1;
  end
  wire service = rst_n && dreq && !dready && can_complete && !address_error;
  assign sensor_pop = service && !dwrite && daddr == SENSOR_DATA;
  assign rx_pop = service && !dwrite && daddr == UART_RX_DATA;
  assign tx_push = service && dwrite && daddr == UART_TX_DATA;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      iready <= 0; ierror <= 0; irdata <= 0;
      dready <= 0; derror <= 0; drdata <= 0;
      gpio <= 0; cycles <= 0; retired <= 0;
    end else begin
      cycles <= cycles + 32'd1;
      if (retire) retired <= retired + 32'd1;
      iready <= 0; dready <= 0;
      if (ireq && !iready) begin
        iready <= 1; ierror <= iaddr >= IMEM_DEPTH;
        irdata <= iaddr < IMEM_DEPTH ? imem[iaddr[7:0]] : 32'b0;
      end
      if (dreq && !dready && can_complete) begin
        dready <= 1; derror <= address_error; drdata <= read_value;
        if (service && dwrite) begin
          if (daddr < DMEM_DEPTH) dmem[daddr[7:0]] <= dwdata;
          else if (daddr == GPIO) gpio <= dwdata;
        end
      end
    end
  end
`ifndef SYNTHESIS
  assign debug_mem_data = dmem[debug_mem_addr];
  assign debug_cycles = cycles;
  assign debug_retired = retired;
  assign debug_sample_accepted = sensor_accepted;
  assign debug_sample_pop = sensor_pop;
  assign debug_sample_value = sensor_front;
  assign debug_fifo_count = sensor_count;
  assign debug_high_water = sensor_high;
  assign debug_dropped = sensor_dropped;
  assign debug_pc = pc;
  assign debug_uart_idle = tx_idle;
`endif
endmodule
