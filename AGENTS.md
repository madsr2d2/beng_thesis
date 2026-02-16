# Repository Guidelines

## Project Structure & Module Organization
Primary HDL sources and testbenches live in `src/`.
- Design modules: `src/*.vhd` (for example `tx_mac.vhd`, `tx_pcs.vhd`, `can_pkg.vhd`)
- Testbenches: `src/*_tb.vhd` (for example `can_pkg_tb.vhd`, `tx_can_tb.vhd`)

Simulation outputs are written to `sim/` (`.ghw`, logs, GHDL work library).  
Waveform view presets are in `gtk_wave/` (`<tb_name>.gtkw`).  
Reference documentation is in `docs/`, and utility scripts are in `scripts/`.  
`OsvvmLibraries/` is a vendored dependency used by the testbenches.

## Build, Test, and Development Commands
Run from repository root:
- `cd OsvvmLibraries/osvvm && tclsh build.tcl`  
  Builds OSVVM libraries (required once per toolchain/version).
- `make TB=src/can_pkg_tb all`  
  Clean + compile + simulate + open GTKWave for a testbench.
- `make TB=src/tx_can_tb compile run`  
  Compile and run without opening the viewer.
- `make TB=src/tx_mac_ser_tb compile`  
  Syntax/elaboration check only.
- `make clean`  
  Removes generated `sim/` and temporary OSVVM build artifacts.

## Coding Style & Naming Conventions
Use VHDL-2008 (`ghdl --std=08`). Follow VSG (`vsg_config.yaml`) for style checks:
- `vsg -c vsg_config.yaml -f src/can_pkg.vhd`

Naming patterns:
- Files/modules: snake_case (`tx_mac_fsm_v2.vhd`)
- Testbenches: suffix `_tb.vhd`
- Constants: lower snake case with `_c` suffix (`format_start_c`)

## Testing Guidelines
Framework: GHDL + OSVVM assertions/alerts in `_tb.vhd` testbenches.  
Add or update tests whenever behavior changes in `src/*.vhd`. Prefer targeted benches per module and keep regression benches passing before opening a PR.  
No fixed coverage threshold is enforced; practical requirement is passing relevant testbenches and clear validation for changed logic.

## Commit & Pull Request Guidelines
Recent history favors concise, imperative commit subjects:
- `Add TX PCS/LLC/CAN modules...`
- `Fix SBC bit identification...`
- `Refactor get_next_mac_frame_bit...`

Use: `<Verb> <scope> <what changed>`; avoid vague messages like `update`.  
PRs should include:
- Problem statement and design intent
- Files/modules impacted (for example `src/tx_pcs.vhd`, `src/tx_pcs_tb.vhd`)
- Repro/verification commands run
- Waveform screenshot or notes when timing/serialization behavior changes
