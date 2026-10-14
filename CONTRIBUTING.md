# Contributing

Start with the [architecture walkthrough](PROJECT_WALKTHROUGH.md) and the [verification guide](docs/VERIFICATION.md). The supported, tested development environment is Windows x64 with Python 3.14 and Visual Studio C++ tools.

```powershell
python tools/run.py setup
python tools/run.py all
```

For focused iteration, use `test`, `demo`, `benchmark`, or `synth` instead of `all`. Run `all` before opening a pull request so the committed evidence comes from one source fingerprint.

Keep changes focused. For instruction or device behavior changes, update the ISA/memory-map documentation and add a directed scenario covering the behavior. For firmware changes, verify warm-up, exact thresholds, hysteresis, and overload. Explain the problem, chosen behavior, and validation in the pull request.

Commit source, documentation, and refreshed reports. Do not commit the virtual environment, SDK archives, native binaries, or generated C++ models. The firmware image and instruction listing are generated in `build/`; CI attaches them to its evidence artifact.

Use measured language: a finite interval sweep is not a universal throughput proof, passing assertions are not formal verification, and generic synthesis cells are not board-specific FPGA resources.

Source fingerprints normalize CRLF to LF; firmware image bytes use LF on every platform. Do not hand-edit hashes or generated result numbers.
