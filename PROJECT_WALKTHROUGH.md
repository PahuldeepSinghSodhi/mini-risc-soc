# MiniRISC implementation walkthrough

This guide describes the integrated implementation. Read README.md for setup and reports/RESULTS.md for generated measurements. The original six-file audit is archived in docs/ORIGINAL_REVIEW.md.

## Read the code in this order

| Source | Responsibility |
|---|---|
| rtl/mini_risc_pkg.sv | Fixed 32-bit ISA types, operation codes, fault codes, and MMIO constants |
| rtl/instruction_decoder.sv | Fields and format; normalized second-register selection for stores/branches |
| rtl/immediate_generator.sv | Signed 20/24-bit immediates and LUI construction |
| rtl/control_unit.sv | Register/memory/ALU controls, illegal function detection, separate branch selection |
| rtl/register_file.sv | Sixteen registers, asynchronous reads, synchronous writes, active-low asynchronous reset, protected R0 |
| rtl/alu.sv | Nine operations and live zero/negative/signed-overflow flags |
| rtl/mini_risc_cpu.sv | Instruction lifecycle, transaction stability, precise data/illegal faults, HALT, retirement |
| rtl/sync_fifo.sv | Ordered buffering, simultaneous push/pop, drop accounting, high-water mark |
| rtl/uart.sv | Synchronized serial RX, 8N1 serialization, framing checks, separate RX/TX FIFOs |
| rtl/mini_risc_soc.sv | ROM/RAM responders, MMIO decoding, device integration and counters |
| firmware/program.py | Readable instruction builder, label fixups, temperature firmware and image/listing generation |
| sim/ | Native C++ RTL drivers, serial decoder, CPU/device/SoC test harnesses |
| tools/verify.py | Independent window-recomputation oracle, workload generation, MMIO fixtures and trace checks |
| tools/run.py | Local tool setup, build, regression, demo, benchmark, synthesis and report generation |
| tools/metadata.py | Implementation and firmware evidence fingerprints |

## Architecture and timing

The CPU has FETCH, EXECUTE, MEMORY and STOPPED states. FETCH holds an instruction request until its response completes, then latches the instruction. EXECUTE commits a register ALU result, branch, jump, or HALT; memory operations instead latch address/write-data and enter MEMORY. MEMORY holds that transaction until completion, then commits load writeback or finishes a store. There is no pipelining.

The instruction and data ports are independent. A transaction completes on a rising edge with both request and ready asserted. Error is meaningful with ready. Address and write controls remain stable while waiting. Reset gates requests off, clears core state, and discards the pending instruction. Only one transaction may be outstanding per port.

The SoC samples a request at an edge and presents a registered response during the following cycle. It performs a transaction's side effect once when creating that response, then avoids servicing the still-asserted request a second time while the response is being consumed. A FIFO pop and its returned front value therefore refer to the same entry. CPU-only tests also exercise longer response delays.

Rising-edge writes and active-low asynchronous resets are used throughout. RAM/FIFO payload storage is not reset globally; validity comes from FIFO counts and explicit firmware initialization. Unwritten RAM is architecturally unspecified even if a particular simulator displays zero.

## Custom ISA contract

All instruction and data addresses are **word addresses**. No byte-address scaling is applied.

- Sequential next PC and JAL link: `PC + 1`.
- Taken BEQ/BNE and JAL target: `current instruction PC + signed offset`.
- Register arithmetic and effective-address addition wrap at 32 bits. Bounds are checked on the full effective address before indexing memory; high address bits are never silently discarded by the memory decoder.
- R0 always reads zero and discards writes. Reset clears all registers.
- Signed overflow is an ALU flag, not a trap. SLT/SLTI compare signed values; SRL is logical. Shifts use the low five bits of the second operand.
- ANDI and ORI use sign-extended 20-bit immediates, as in the original custom ISA.

| Form | Instruction fields |
|---|---|
| R | opcode 31:28=0, rd 27:24, rs1 23:20, rs2 19:16, reserved 15:4=0, function 3:0 |
| I | opcode 31:28, rd 27:24, rs1 23:20, immediate 19:0 |
| Store/branch | opcode 31:28, source2 27:24, source1/base 23:20, immediate/offset 19:0 |
| JAL | opcode 31:28=8, rd 27:24, offset 23:0 |

Opcodes: 0 R-type, 1 ADDI, 2 ANDI, 3 ORI, 4 LW, 5 SW, 6 BEQ, 7 BNE, 8 JAL, 9 LUI, A SLTI, F HALT. B-E are illegal. R-type functions 0-7 are ADD, SUB, AND, OR, XOR, SLT, SLL, SRL. Function 8 is not a legal instruction even though the internal ALU uses PASS_B=8 for LUI. HALT ignores its unused lower fields.

The decoder keeps rd as the raw upper field but normalizes rs2 to bits 27:24 for SW/BEQ/BNE. Control validates opcodes/functions, and the CPU additionally rejects nonzero R-type reserved bits. Invalid encodings cannot reach memory or register writeback.

Fault codes are 0 none, 1 illegal instruction, 2 instruction access, and 3 data access. Fault cause/PC and stopped state are retained until reset. An illegal/data fault points to the instruction that failed; a failed target fetch points to the inaccessible target address. A preceding branch/JAL has already retired in that case. HALT retires once and keeps its current PC. Instruction-access errors, illegal instructions and data-access errors do not retire.

## Memory map and access rules

All addresses below are hexadecimal **word addresses**, and all accesses are 32-bit words. UART data uses only its low byte; sensor data uses its low twelve bits.

| Address | Access | Meaning |
|---|---|---|
| 000-0FF | R/W | 256-word data RAM |
| 100 | R | Sensor status: bit0 nonempty, bit1 full, bits12:8 count |
| 101 | R | Sensor front sample; waits if empty; removes one sample |
| 102 | R | Dropped sensor samples |
| 103 | R | Sensor FIFO high-water count |
| 110 | R | UART status: bit0 RX available, bit1 TX space, bit2 TX idle |
| 111 | R | UART RX byte; waits if empty; removes one byte |
| 112 | W | UART TX byte; waits if FIFO full |
| 113 | R | UART RX overflow count |
| 114 | R | UART invalid-stop-bit frame count |
| 120 | R | Free-running cycle counter |
| 121 | R | Retired-instruction counter |
| 130 | R/W | GPIO; firmware assigns alarm bit0 and readiness bit1 |

Unmapped addresses, reads of TX-only data, and writes to read-only devices fault. Reads of status/counters/GPIO do not wait for device data. Counters wrap modulo 2^32 and reset to zero. The retirement counter observes a registered retirement pulse one cycle later, including HALT; peripheral timers continue while the CPU is stopped.

Sensor, UART RX and UART TX FIFOs each hold sixteen entries. A simultaneous pop at full capacity permits a new push. Otherwise full sensor/RX FIFOs drop the newest arrival and count the loss. UART TX writes wait instead of dropping bytes. Sensor valid is a one-cycle pulse per sample; there is no producer backpressure pin.

UART is 8N1, LSB first, with a two-register RX synchronizer and a configurable integer clocks-per-bit divisor. The tested default is sixteen. It is a single-clock design; a production board implementation would also need clock, pin, timing, CDC and electrical review.

## Firmware and application state

The builder uses instruction-encoding helpers and labels; it is not an assembly-text parser. Its generated listing makes every encoded instruction reviewable. The image is padded to 256 words with HALT instructions and contains 59 active instruction words.

| Registers | Use |
|---|---|
| R1/R2/R15 | Sensor/UART/GPIO bases |
| R3/R4/R5 | Ring index, rolling sum, warm-up count |
| R6/R7 | New/outgoing sample |
| R8/R12/R13 | Scratch registers |
| R9/R10/R11 | Average, alarm state, processed count |
| R14 | Shift amount four |

RAM words 0-15 hold the ring. Words 32-35 hold processed count, average, alarm-on count and alarm-off count. Those locations are initialized by firmware; other RAM locations are not promised initialized.

For each sample, firmware subtracts the outgoing value, inserts/adds the new value, advances the index modulo sixteen, and shifts the sum right by four. The largest possible sixteen-sample sum fits easily in 32 bits. Warm-up saturates at sixteen. Alarm decisions are suppressed before then; afterward the average turns the alarm on at >=800 and off at <=750 in tenths of a degree Celsius.

On a transition, firmware writes GPIO first, then enqueues four UART bytes: A5, state, average low byte, average high byte. Finally it writes the latest average and processed-count statistic. A full TX FIFO may delay completion; buffering and benchmark measurements account for that delay. Firmware polls forever; finite testbench runs stop only after all accepted samples and queued serial bytes have drained.

## Verification and measurement boundaries

The CPU tests use delayed instruction/data response models. Device tests include 5,000 seeded FIFO cycles and actual UART pin waveforms. MMIO fixtures execute through the CPU, including empty FIFO waits, UART loopback, a full TX FIFO and invalid accesses.

The Python application oracle recomputes the complete sixteen-value window sum for each accepted sample rather than sharing the firmware's rolling-sum implementation. It checks every average, alarm state, transition record and RAM statistic. CSV traces record offered/accepted samples, hardware pops, completion statistics, GPIO transitions and decoded UART bytes.

Processing cycles run from FIFO pop to processed-count RAM write. Queueing cycles run from acceptance to pop. Alarm response runs from acceptance of the qualifying sample to GPIO change. Filter delay compares the overheating step's arrival with the qualifying sample's arrival and is separate from CPU/queueing time. The seven-point rate sweep uses the same 512-sample seeded workload, not an unlimited-duration capacity proof.

Synthesis reports preserve memory widths/depths before technology-independent expansion, then count generic primitives without ABC or a target library. The register file is represented as registers; synthesized decoder lookup ROMs are distinguished from declared RAM/ROM/FIFOs. Debug observation ports are simulation-only. Results do not establish physical FPGA resource use, timing, power, safety certification, code-coverage closure, or formal proof.

All source-dependent reports carry source/firmware fingerprints. The combined report is withheld if stage fingerprints differ. Run `python tools/run.py all` to regenerate consistent evidence after a source change.
