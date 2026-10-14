# Changelog

## 1.0.0

- Integrated the six original RTL building blocks into a multicycle 32-bit custom-ISA processor.
- Defined word-addressed control flow, protected R0, rejected illegal instructions, and added retained HALT/fault state.
- Added synchronous instruction/data memories and explicit request/completion interfaces.
- Added sensor and UART FIFOs, serial RX/TX, GPIO, cycle and retirement counters, and MMIO access faults.
- Added temperature-monitoring firmware with a sixteen-sample window and 80°C/75°C alarm hysteresis.
- Added 46 test cases/suites, independent application checks, a fixed 512-sample benchmark, and generic synthesis reports.
- Added native Windows setup, source/firmware fingerprints, reproducible evidence, and GitHub Actions verification.
