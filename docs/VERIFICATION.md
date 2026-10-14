# Verification and reproducibility

## What the regression checks

| Layer | Cases/suites | Evidence |
|---|---:|---|
| CPU | 20 | All supported instructions; delayed responses with four seeds; branch outcomes; JAL; sign/shift boundaries; illegal encodings; access faults; R0; retained stop; reset during a pending store |
| Components | 9 | ALU results/flags, register timing/reset, 5,000 seeded FIFO cycles, UART TX/RX/framing/overflow/backpressure/reset |
| MMIO integration | 8 | CPU-driven sensor waits, serial loopback, counters/GPIO, invalid access faults, TX-full waiting without duplicate bytes |
| Temperature application | 9 | Normal readings, warm-up, exact threshold, isolated spike, hysteresis, recovery, threshold noise, mixed workload, overload |

The total of **46** counts cases and suites of different sizes. It is not a coverage percentage. A Python application oracle independently sums the complete window for every accepted sample; it does not implement a full instruction-set interpreter.

Assertions check protected R0, frozen stopped state, stable outstanding requests, and FIFO bounds. Tests have simulation watchdogs. No formal proof or coverage closure is claimed.

## Commands and CI

Run `python tools/run.py setup` once, then `python tools/run.py all`. GitHub Actions runs the same commands on a fresh Windows runner and uploads reports, raw traces, diagnostics, and generated firmware as an artifact. The status badge links to the actual workflow state.

The local virtual environment, native build, and optional SDK installation live under ignored directories. Compiler/SDK versions may differ between a laptop and a hosted runner; each run records its actual toolchain. Dependency versions are pinned; the packaged Verilator binary reports a build identifier that is preserved separately from its Python distribution version.

## How to interpret the measurements

- **Processing cycles:** accepted sample's hardware FIFO pop to the firmware's processed-count RAM write; includes firmware work and any UART queue wait during that work.
- **Queue cycles:** FIFO acceptance to pop.
- **Alarm response:** accepted qualifying sample's arrival to the GPIO transition.
- **Filtering delay:** arrival of the sustained overheat step to arrival of the sample whose filtered value crosses the threshold. It is separate from CPU/queue delay.
- **Zero-drop interval:** smallest tested interval without loss for the fixed 512-sample, seed-14 workload. The seven tested intervals are 16, 32, 64, 128, 256, 512 and 1,024 cycles; this does not establish an unlimited-duration maximum rate.
- **Synthesis counts:** technology-independent primitive/bit-cell counts after memory expansion, without ABC, a target library, placement, routing, or timing/power analysis. Coarse memory shapes are retained separately.

`reports/raw/*.csv` records offers, acceptance decisions, hardware pops, processing completions, GPIO changes, and decoded serial bytes. Input files and per-run JSON make each experiment inspectable.

## Fingerprints and committed snapshots

Each report contains the implementation and firmware fingerprints. Source text is canonicalized to LF before hashing; firmware hex files are written with LF. The combined results are withheld when stage fingerprints differ.

The reports committed to the repository are a measured reference snapshot. A CI artifact describes that CI run; it does not automatically replace committed reports. Rerun the complete workflow and commit updated evidence after changing implementation or firmware.

## Scope of the result

The workload uses simulated unsigned temperature readings. There is no physical sensor or FPGA deployment in this release, and no claim of board-level timing, power, certified control behavior, or RISC-V compatibility. These boundaries keep the demonstration's claims aligned with the available evidence.
