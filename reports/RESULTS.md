# Measured MiniRISC results

Regression: **46 passing cases/suites**. Component suites contain multiple checks; this is not a coverage percentage.

Firmware: 59 words; SHA-256 `30109dac80da5043bf03de693f3015a0df74f2e92d873b6dead307daa6e7719d`.
Implementation fingerprint: `6839d37bf0bf3f29f39a46947f3fb0888ccbb871100384502caaac2c2faa4d63`.

Demo: 512 samples processed; 0 dropped; 2 alarm transitions.
Overheat filtering delay: 10 sample intervals, measured separately from queue/CPU latency.
Qualifying-sample arrival to GPIO transition: [89, 93] cycles.

## Fixed 512-sample workload, seed 14

| Input interval (cycles) | Processed | Dropped | FIFO peak | Mean processing cycles (pop to completion) |
|---:|---:|---:|---:|---:|
| 16 | 121 | 391 | 16 | 59.23 |
| 32 | 226 | 286 | 16 | 59.12 |
| 64 | 435 | 77 | 16 | 59.06 |
| 128 | 512 | 0 | 1 | 59.05 |
| 256 | 512 | 0 | 1 | 59.05 |
| 512 | 512 | 0 | 1 | 59.05 |
| 1024 | 512 | 0 | 1 | 59.05 |

Smallest **tested** zero-drop interval: 128 cycles. This finite sweep does not prove a maximum sustainable rate for every workload.

## Generic synthesis, no ABC or target library

| Design | Primitive cells | Sequential bit cells |
|---|---:|---:|
| mini_risc_cpu | 4021 | 678 |
| mini_risc_soc | 24114 | 9653 |

Memories are reported before mapping in synthesis.json and expanded into generic logic/storage for these counts. Simulation debug ports are excluded from synthesis.
These are not FPGA LUT/BRAM utilization, physical area, maximum frequency, or power measurements.

Raw inputs, CSV execution traces, and per-run JSON are in raw/. Tool versions are in toolchain.json.
Full logs and per-type synthesis statistics are retained beside this report. All timings are simulated cycles.
