# Design decisions

| Decision | Reason | Consequence |
|---|---|---|
| Preserve the custom instruction set | Build on the original ALU, decoder, controller, and register file | Existing encodings remain useful; standard RISC-V toolchains are not compatible |
| Use a multicycle controller | Model synchronous memories and blocking device transactions explicitly | One instruction completes before the next; no pipeline hazards or overlap |
| Address words directly | Resolve the original PC+1/PC+4 inconsistency | Sequential/link addresses use PC+1; branches and jumps use current PC plus word offset |
| Keep CPU and SoC separate | Test instruction execution independently of devices | CPU tests can introduce delayed responses; MMIO is implemented in the SoC |
| Use bounded FIFOs and visible loss counters | Make overload observable and reproducible | Sensor/RX overflow drops newest input; TX writes wait for space |
| Use a sixteen-sample window | Implement a useful filter using the existing ISA | Division becomes a right shift; alarms wait for a complete initial window |
| Use two alarm thresholds | Avoid repeated switching near one threshold | Alarm asserts at 80°C, clears at 75°C, and retains its state between them |
| Compare against an independent application model | Check firmware behavior without sharing its rolling-sum code | Every accepted sample and serial event is checked; this is not ISA differential testing |
| Publish generic synthesis separately from simulation | Measure implementation size without implying physical hardware results | Cell counts and memory shapes are useful evidence; frequency and FPGA utilization remain unmeasured |
| Keep source-dependent evidence fingerprinted | Prevent mixed or stale stage results from looking current | A combined report requires matching source and firmware hashes |

Future work should follow evidence: a pipeline requires a measured execution bottleneck, a larger FIFO requires a defined burst budget, and FPGA deployment requires a target device, constraints, and physical validation.
