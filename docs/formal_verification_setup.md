---
title: Formal Verification Setup Guide
subtitle: GHDL + oss-cad-suite + SymbiYosys for VHDL-2008
date: 2026-03-09
---

# Formal Verification Setup Guide {#sec:formal-verification-setup}

This guide documents how to set up and use formal verification for the CAN node VHDL project. It covers the toolchain installation, OSVVM recompilation, Makefile adjustments, PSL assertion authoring, and SymbiYosys configuration. The guide is written to be reproducible from scratch.

**Toolchain overview:**

| Tool | Role |
|------|------|
| GHDL (oss-cad-suite, LLVM backend) | VHDL-2008 compiler with PSL support |
| Yosys | RTL synthesis and netlist generation |
| SymbiYosys (`sby`) | Formal proof orchestrator |
| z3 / bitwuzla | SMT solvers (bundled in oss-cad-suite) |

---

## Table of Contents

1. [Why oss-cad-suite Is Required](#sec:why-oss-cad-suite)
2. [Installing oss-cad-suite](#sec:installing-oss-cad-suite)
3. [Recompiling OSVVM Libraries](#sec:recompiling-osvvm)
4. [Makefile Changes](#sec:makefile-changes)
5. [PSL Assertions in VHDL](#sec:psl-assertions)
6. [SymbiYosys Configuration](#sec:sby-config)
7. [Running Formal Proofs](#sec:running-proofs)
8. [Understanding Results](#sec:understanding-results)
9. [Troubleshooting](#sec:troubleshooting)

---

## 1. Why oss-cad-suite Is Required {#sec:why-oss-cad-suite}

Ubuntu ships a system GHDL package (version 4.1.0 as of Ubuntu 24.04) that is compiled with the **mcode** backend. This backend parses PSL annotations when passed `-fpsl` but does **not** evaluate them at runtime. Running a testbench under the system GHDL with `--psl` either silently ignores assertions or errors.

Formal verification requires two additional capabilities that the system package does not provide:

1. **Runtime PSL evaluation** - The LLVM backend (available only in oss-cad-suite) can evaluate PSL properties during simulation.
2. **Yosys/SymbiYosys integration** - Formal exhaustive proof requires Yosys to synthesize the VHDL netlist and SymbiYosys to drive an SMT solver over it. The `ghdl-yosys-plugin` that bridges GHDL to Yosys is bundled in oss-cad-suite.

**Version comparison:**

| | System GHDL | oss-cad-suite GHDL |
|--|--|--|
| Version | 4.1.0 | 6.0.0-dev (Dunoon edition) |
| Backend | mcode | LLVM |
| PSL runtime checking | No | Yes |
| Yosys plugin | No | Yes (`-i ghdl`) |
| OSVVM compatibility | Yes (its own `.cf` files) | Yes (separate `.cf` files) |

Because GHDL compiled library (`.cf`) files are version-specific and not cross-compatible, activating oss-cad-suite and running the project requires recompiling OSVVM under the new GHDL version. This is covered in @sec:recompiling-osvvm.

---

## 2. Installing oss-cad-suite {#sec:installing-oss-cad-suite}

### 2.1 Automated install script

A helper script is provided in the repository:

```bash
bash formal/install_oss_cad_suite.sh
```

This script fetches the latest release date from GitHub, downloads the Linux x64 tarball, and extracts it to `/opt/oss-cad-suite`. It requires `sudo` for the extraction step.

### 2.2 Manual installation

If the script is unavailable or you prefer a different install path:

1. Go to the releases page: `https://github.com/YosysHQ/oss-cad-suite-build/releases/latest`
2. Download the Linux x64 tarball, for example:
   ```
   oss-cad-suite-linux-x64-20260228.tgz
   ```
3. Extract to your chosen directory:
   ```bash
   tar xzf oss-cad-suite-linux-x64-20260228.tgz -C /opt
   # or to home directory:
   tar xzf oss-cad-suite-linux-x64-20260228.tgz -C ~
   ```

### 2.3 Activating the environment

oss-cad-suite ships an `environment` shell script that prepends its binaries to `PATH` and sets library paths. You must source it in every terminal session before using `ghdl`, `yosys`, or `sby`:

```bash
source /opt/oss-cad-suite/environment
# or if installed to home directory:
source ~/oss-cad-suite-linux-x64-20260228/environment
```

**Verify the correct GHDL is active:**

```bash
ghdl --version
```

Expected output (version number may differ):

```
GHDL 6.0.0-dev (4.1.0.r1404.gdc896b6a7.dirty) [Dunoon edition]
 Compiled with LLVM 18.1.8 backend
...
```

The key indicator is `[Dunoon edition]` and the `LLVM` backend line. If you see `mcode`, the system GHDL is still active.

**Verify SymbiYosys:**

```bash
sby --help
```

This should print the SymbiYosys usage message.

> **Note:** Sourcing the environment script does not persist across terminal sessions. Add the `source` line to your `~/.bashrc` or `~/.zshrc` if you want it active by default, but be aware this will shadow the system GHDL for all VHDL work.

---

## 3. Recompiling OSVVM Libraries {#sec:recompiling-osvvm}

This step is required every time you switch between the system GHDL and the oss-cad-suite GHDL.

### 3.1 Why recompilation is necessary

GHDL stores compiled library metadata in `.cf` files. These files record the GHDL version that produced them and are not forward- or backward-compatible. When GHDL encounters a `.cf` file compiled by a different version, it rejects it with an error like:

```
ghdl:error: library compiled with a different version of GHDL
```

OSVVM's build system organises compiled output under a directory named after the GHDL version. The naming logic lives in `OsvvmLibraries/Scripts/VendorScripts_GHDL.tcl`:

```tcl
regexp {GHDL\s+\d+\.\d+\S*} [exec $ghdl --version] VersionString
variable ToolNameVersion ${ToolName}-${ToolVersion}
```

For the oss-cad-suite GHDL, `ghdl --version` returns `GHDL 6.0.0-dev ...`, so OSVVM creates:

```
OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-6.0.0-dev/osvvm/v08/osvvm-obj08.cf
```

For the system GHDL 4.1.0, the path would be:

```
OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-4.1.0/osvvm/v08/osvvm-obj08.cf
```

Both directories can coexist. Only the Makefile `OSVVM_LIB_PATH` variable selects which one is used (see @sec:makefile-changes).

### 3.2 The source deletion hazard

> **WARNING:** Do not run `cd OsvvmLibraries && tclsh Scripts/StartGHDL.tcl` followed by `build osvvm/osvvm.pro` from within `OsvvmLibraries/`. This will delete the `osvvm/` source directory before the build runs.
>
> OSVVM's build script removes the old output directory that matches the library name before creating a new one. When the current working directory is `OsvvmLibraries/` and the library name is `osvvm`, the script interprets `osvvm/` as the output directory and deletes it. The `osvvm/` subdirectory is also the OSVVM source tree.

If sources are accidentally deleted, restore them from the git submodule:

```bash
# From project root:
git submodule update --init OsvvmLibraries/osvvm

# Or from within OsvvmLibraries:
git submodule update --init osvvm
```

### 3.3 Correct recompilation procedure

The safe approach is to run the build from the project root and point `VhdlLibraryParentDirectory` at the `osvvm/` subdirectory (not the parent). Create a temporary TCL script:

```tcl
# /tmp/build_osvvm3.tcl
source /home/madsr2d2/beng_thesis/OsvvmLibraries/Scripts/StartGHDL.tcl
set ::osvvm::VhdlLibraryParentDirectory "/home/madsr2d2/beng_thesis/OsvvmLibraries/osvvm"
build /home/madsr2d2/beng_thesis/OsvvmLibraries/osvvm/osvvm.pro
```

Then run from the project root with the oss-cad-suite environment active:

```bash
source /opt/oss-cad-suite/environment
cd /home/madsr2d2/beng_thesis
tclsh /tmp/build_osvvm3.tcl
```

**Expected result:** A new directory appears at:

```
OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-6.0.0-dev/
```

Verify the compiled library file exists:

```bash
ls OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-6.0.0-dev/osvvm/v08/osvvm-obj08.cf
```

---

## 4. Makefile Changes {#sec:makefile-changes}

After switching to oss-cad-suite GHDL, two lines in the Makefile require updating. Both changes are already applied in the current repository state.

### 4.1 OSVVM library path

The `OSVVM_LIB_PATH` variable must point to the directory compiled by the active GHDL version.

```makefile
# system GHDL 4.1.0 (old):
OSVVM_LIB_PATH = $(CURDIR)/OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-4.1.0

# oss-cad-suite GHDL 6.0.0-dev (current):
OSVVM_LIB_PATH = $(CURDIR)/OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-6.0.0-dev
```

### 4.2 OsvvmTemp_GHDL copy path

Newer versions of OSVVM moved `OsvvmTemp_GHDL/` one directory level up, from inside `osvvm/` to the `OsvvmLibraries/` root.

```makefile
# Old path (inside osvvm subdirectory):
@cp -r OsvvmLibraries/osvvm/OsvvmTemp_GHDL . 2>/dev/null || true

# New path (OsvvmLibraries root):
@cp -r OsvvmLibraries/OsvvmTemp_GHDL . 2>/dev/null || true
```

The `2>/dev/null || true` suppresses errors if the directory does not exist in a given OSVVM version.

---

## 5. PSL Assertions in VHDL {#sec:psl-assertions}

### 5.1 Overview of PSL modes

PSL (Property Specification Language) annotations are embedded in VHDL source files as specially prefixed comments. GHDL and Yosys both recognise the `-- psl` prefix.

The same source file supports three verification modes without modification:

| Mode | Command | PSL behaviour |
|------|---------|---------------|
| Standard simulation | `ghdl -r ...` | PSL lines treated as plain comments, ignored |
| PSL simulation | `ghdl -r -fpsl ...` | PSL evaluated at runtime (requires LLVM GHDL) |
| Formal proof | `sby formal/bit_stuffer_fd.sby` | PSL proved exhaustively via SMT solver |

### 5.2 Placement in the architecture body

PSL annotations must appear in the **concurrent region** of the architecture body - after `begin` and before `end architecture`. They cannot appear in port/generic declarations or inside sequential processes.

```vhdl
architecture rtl of my_entity is
  signal my_signal : integer range 0 to 15;
begin

  -- ... concurrent signal assignments and processes ...

  -- psl default clock is rising_edge(clk_i);
  -- psl P1 : assert always (my_signal <= 15) report "FAIL: P1 overflow";

end architecture rtl;
```

### 5.3 Core PSL constructs

**Default clock declaration** (required - appears once per architecture):

```vhdl
-- psl default clock is rising_edge(clk_i);
```

Without this, every property must name its own clock. All temporal operators (`always`, `next`, `eventually`) evaluate on rising edges of `clk_i`.

**Assume - constrains solver inputs:**

```vhdl
-- Holds at step 0 only:
-- psl LABEL : assume (condition);

-- Holds at every step:
-- psl LABEL : assume always (condition);
```

The solver treats `assume` statements as axioms. It will only explore states where the assumption holds. Assumptions do NOT drive design signals - they restrict the solver's search space.

**Assert - property to prove:**

```vhdl
-- psl LABEL : assert always (condition) report "failure message";
```

The solver tries to find a counterexample (an input sequence that falsifies the assertion). If it succeeds, it generates a trace. If it exhausts the search (within the proof depth), the property is proved.

### 5.4 Handling uninitialized state at step 0

In formal verification, step 0 is the state before any clock edge. Signals without VHDL initial values are unconstrained - the solver can assign them any legal value. This commonly causes false failures because a reset signal might be `'0'` at step 0, exposing uninitialized internal state.

The standard pattern is to assume the reset is asserted at step 0, then guard all assertions with a reset-deasserted precondition:

```vhdl
-- psl default clock is rising_edge(clk_i);

-- Constrain initial state: reset must be asserted before the first clock edge.
-- psl ASSUME_RESET_INIT : assume (reset_i = '1');

-- Guard assertions: only check when reset has been released.
-- psl P1 : assert always (reset_i = '0' -> (counter <= max_c)) report "FAIL P1";
```

> **Pitfall - contradictory assumptions:** Do not combine `ASSUME_RESET_INIT` (reset = 1 at step 0) with `assume always ((reset_i = '0') -> next (reset_i = '0'))` (once released, stays released). These are contradictory - reset starts asserted (step 0) but can never be asserted again (the always-next constraint applies from step 0 onward). The solver reports `PREUNSAT` (precondition unsatisfiable). If you want to prevent re-assertion, use a one-sided constraint: `assume always ((reset_i = '1') -> next (reset_i = '1'))` (once asserted, stays asserted) - but this prevents the solver from ever releasing reset, which is equally problematic. The simplest correct approach is `ASSUME_RESET_INIT` alone, with guards in the assertions.

### 5.5 Assertions in bit_stuffer_fd.vhd

The following PSL properties are defined in `src/bit_stuffer_fd.vhd` (lines 193-221), after the `begin` keyword of `architecture rtl`. They verify requirements REQ-042 (dynamic bit stuffing) and REQ-043 (SBC generation) from the verification plan.

```vhdl
-- psl default clock is rising_edge(clk_i);

-- Environment assumptions
-- psl ASSUME_NO_UNKNOWN_DATA : assume always (bs_fd_i.data = dominant or bs_fd_i.data = recessive);
-- psl ASSUME_START_MUTEX : assume always not (bs_fd_i.start and bs_fd_i.valid);
-- psl ASSUME_RESET_INIT : assume (reset_i = '1');

-- #042 [P1]: consecutive_count is always bounded by stuff_width_c.
-- psl P1_COUNT_BOUNDED : assert always (reset_i = '0' -> (consecutive_count <= stuff_width_c))
--   report "FAIL P1: #042 consecutive_count exceeded stuff_width_c";

-- #042 [P2]: At the stuffing threshold, output valid must be asserted.
-- psl P2_COUNT_IMPLIES_VALID : assert always (reset_i = '0' ->
--   ((consecutive_count = stuff_width_c) -> bs_fd_o.valid))
--   report "FAIL P2: #042 count at threshold but valid not asserted";

-- #042 [P3a/3b]: Stuff bit polarity is always inverse of the triggering run.
-- psl P3_STUFF_POL_DOMINANT : assert always (reset_i = '0' ->
--   ((bs_fd_o.valid and last_polarity = dominant) -> bs_fd_o.data = recessive))
--   report "FAIL P3a: #042 stuff bit not recessive after dominant run";
-- psl P3_STUFF_POL_RECESSIVE : assert always (reset_i = '0' ->
--   ((bs_fd_o.valid and last_polarity = recessive) -> bs_fd_o.data = dominant))
--   report "FAIL P3b: #042 stuff bit not dominant after recessive run";

-- #043 [P4]: Output polarity never unknown when valid is asserted.
-- psl P4_NO_UNKNOWN_OUTPUT : assert always (reset_i = '0' ->
--   (bs_fd_o.valid -> (bs_fd_o.data = dominant or bs_fd_o.data = recessive)))
--   report "FAIL P4: #043 stuff bit has undefined polarity when valid";

-- #042 [P5]: Synchronous reset clears consecutive_count and deasserts valid.
-- psl P5_RST_CLEARS_STATE : assert always (reset_i = '1') ->
--   next (consecutive_count = 0 and not bs_fd_o.valid)
--   report "FAIL P5: #042 synchronous reset did not clear state";

-- #042 [P6]: Frame-start pulse clears consecutive_count and deasserts valid.
-- psl P6_START_CLEARS_STATE : assert always bs_fd_i.start ->
--   next (consecutive_count = 0 and not bs_fd_o.valid)
--   report "FAIL P6: #042 start pulse did not clear state";
```

**Design notes on the assumption set:**

- `ASSUME_NO_UNKNOWN_DATA`: The `polarity_t` type includes `unknown` as a third value. Without this assumption, the solver may drive `bs_fd_i.data = unknown`, which is not a valid bus state.
- `ASSUME_START_MUTEX`: `bs_fd_i.start` (frame start) and `bs_fd_i.valid` (bit valid) are mutually exclusive by protocol. This prevents the solver from exploring a spurious simultaneous assertion that the hardware never produces.
- `ASSUME_RESET_INIT`: Ensures the solver begins from a known reset state. Without it, `consecutive_count` and `last_polarity` are unconstrained at step 0.

---

## 6. SymbiYosys Configuration {#sec:sby-config}

The formal proof job is defined in `formal/bit_stuffer_fd.sby`. The full file is annotated below.

```
# formal/bit_stuffer_fd.sby

[tasks]
bmc
prove
```

Two tasks are defined. Running `sby formal/bit_stuffer_fd.sby` runs both. Running `sby formal/bit_stuffer_fd.sby bmc` runs only the bounded model check.

```
[options]
# BMC: falsification only — finds counterexamples within N cycles.
# Depth 25 covers 5x the stuffing threshold so any plausible run is reachable.
bmc: mode bmc
bmc: depth 25

# Prove: k-induction — proves properties hold for ALL possible inputs forever.
prove: mode prove
prove: depth 25
```

**BMC (Bounded Model Check):** Explores all reachable states up to `depth` clock cycles. A failing assertion produces a counterexample trace. A passing BMC result means no bug exists within 25 cycles - it does NOT prove correctness for all time.

**Prove (k-induction):** Attempts to prove the property holds for all possible states and all possible future inputs, unbounded. It does this by proving: (1) the base case holds at step 0, and (2) if the property holds for `k` consecutive steps, it holds at step `k+1`. A passing prove result is an exhaustive guarantee.

```
[engines]
smtbmc z3
```

`smtbmc` is the SymbiYosys backend that converts the problem to SMT (Satisfiability Modulo Theories) and calls a solver. `z3` is the Microsoft Z3 solver, bundled with oss-cad-suite. `bitwuzla` is a faster alternative if installed separately.

```
[script]
plugin -i ghdl
ghdl -fpsl --std=08 \
  can_types_pkg.vhd \
  can_protocol_pkg.vhd \
  can_timing_pkg.vhd \
  bit_stuffer_fd.vhd \
  -e bit_stuffer_fd

prep -top bit_stuffer_fd
```

- `plugin -i ghdl`: Loads the ghdl-yosys-plugin, which adds the `ghdl` command to Yosys.
- `ghdl -fpsl --std=08`: Compile source files with PSL enabled and VHDL-2008 standard. The `-e bit_stuffer_fd` flag sets the top-level entity to elaborate.
- Source files are listed in dependency order: packages first, then the entity that uses them.
- `prep -top bit_stuffer_fd`: Flatten and prepare the netlist for the solver.

```
[files]
src/can_types_pkg.vhd
src/can_protocol_pkg.vhd
src/can_timing_pkg.vhd
src/bit_stuffer_fd.vhd
```

File paths in `[files]` are relative to the project root (the directory from which `sby` is invoked). SymbiYosys copies these files into its working directory before running `[script]`, which is why the `[script]` section references only filenames, not paths.

---

## 7. Running Formal Proofs {#sec:running-proofs}

All commands are run from the project root (`/home/madsr2d2/beng_thesis/`) with the oss-cad-suite environment active.

### 7.1 Activate environment

```bash
source /opt/oss-cad-suite/environment
# Verify:
ghdl --version   # should show LLVM backend
sby --help       # should print SymbiYosys usage
```

### 7.2 Run bounded model check (fast, ~seconds)

```bash
sby formal/bit_stuffer_fd.sby bmc -f
```

- `bmc` - run only the bmc task
- `-f` - force, remove previous results before running

Output directory: `formal/bit_stuffer_fd_bmc/`

### 7.3 Run exhaustive inductive proof (~minutes)

```bash
sby formal/bit_stuffer_fd.sby prove -f
```

Output directory: `formal/bit_stuffer_fd_prove/`

### 7.4 Run both tasks

```bash
sby formal/bit_stuffer_fd.sby -f
```

### 7.5 Passing result

A successful run ends with output similar to:

```
SBY [bit_stuffer_fd_bmc] engine_0: Status returned by engine: pass
SBY [bit_stuffer_fd_bmc] summary: Elapsed clock time [H:MM:SS (secs)]: 0:00:03 (3)
SBY [bit_stuffer_fd_bmc] summary: engine_0 (smtbmc z3): pass
SBY [bit_stuffer_fd_bmc] DONE (PASS, rc=0)
```

The `status` file in the output directory contains `PASS`.

### 7.6 Failing result - reading the counterexample

If an assertion fails, SymbiYosys writes a counterexample trace:

```
SBY [bit_stuffer_fd_bmc] engine_0: Status returned by engine: FAILED
SBY [bit_stuffer_fd_bmc] summary: engine_0 (smtbmc z3): FAILED
SBY [bit_stuffer_fd_bmc] DONE (FAIL, rc=2)
```

The trace is written to:

```
formal/bit_stuffer_fd_bmc/engine_0/trace.smtc   # SMT counterexample
formal/bit_stuffer_fd_bmc/engine_0/trace.yw     # Yosys witness format
formal/bit_stuffer_fd_bmc/engine_0/trace_tb.v   # Verilog testbench replay
```

The Yosys witness file (`.yw`) can be viewed with GTKWave if converted, or inspected as a text log showing signal values at each step.

---

## 8. Understanding Results {#sec:understanding-results}

### 8.1 BMC vs. prove - what each guarantees

| Result | BMC PASS | Prove PASS |
|--------|----------|------------|
| No bug within depth cycles | Yes | Yes |
| No bug for any number of cycles | No | Yes |
| Counterexample if bug found | Yes | Yes |

BMC is useful for fast feedback during development. The prove mode gives the formal guarantee but may be slower and can fail to converge if the depth is insufficient.

### 8.2 PREUNSAT

If SymbiYosys reports `PREUNSAT`, the assume constraints are contradictory - no state exists that satisfies all assumptions simultaneously. This is always a bug in the assumption set, not the design. Review your `assume` annotations for logical contradictions (see the pitfall note in @sec:psl-assertions).

### 8.3 GAVEUP

In prove mode, the solver may give up if it cannot find an inductive invariant within the depth bound. Increasing `depth` in the `.sby` file or switching to a stronger solver may help. Alternatively, adding intermediate `assume` annotations that strengthen the invariant can guide the solver.

### 8.4 Reading proof output directories

After a run, the output directory structure is:

```
formal/bit_stuffer_fd_bmc/
├── logfile.txt              # Full SymbiYosys log
├── status                   # PASS or FAIL (one word)
├── bit_stuffer_fd_bmc.xml   # Structured result summary
├── model/
│   ├── design.il            # Intermediate representation
│   ├── design.json          # Netlist JSON
│   └── design_smt2.smt2     # SMT problem (inspect for debugging)
├── src/                     # Copies of source files used
└── engine_0/
    ├── logfile.txt          # Solver log (timing, steps)
    └── trace.*              # Present only on FAIL
```

---

## 9. Troubleshooting {#sec:troubleshooting}

### Library compiled with different GHDL version

**Symptom:**
```
ghdl:error: library compiled with a different version of GHDL
```

**Cause:** The Makefile `OSVVM_LIB_PATH` points to a directory compiled by a different GHDL. This happens after switching between system GHDL and oss-cad-suite GHDL without recompiling OSVVM.

**Fix:** Recompile OSVVM (see @sec:recompiling-osvvm) and ensure `OSVVM_LIB_PATH` in the Makefile matches the active GHDL version.

### ghdl command not found after sourcing environment

**Symptom:**
```
command not found: ghdl
```

**Fix:** The environment script was not sourced in the current shell session. Run:
```bash
source /opt/oss-cad-suite/environment
```

### sby: No such file or directory

**Symptom:**
```
sby: command not found
```

**Fix:** Same as above - oss-cad-suite environment not active.

### PREUNSAT on initial run

**Symptom:** Formal run immediately reports `PREUNSAT` without checking any assertions.

**Cause:** Contradictory `assume` constraints. Common cause: `ASSUME_RESET_INIT` (step 0: reset = 1) combined with a constraint that forces reset to stay at `'0'` from step 0.

**Fix:** Review all `assume` annotations. Remove constraints that are logically inconsistent with each other. Start with only `ASSUME_RESET_INIT` and add others one at a time, re-running after each addition to identify which combination is contradictory.

### PSL assertions not checked in simulation

**Symptom:** Simulation runs without any PSL-related output even though `-fpsl` is passed.

**Cause:** The system GHDL (mcode backend) does not evaluate PSL at runtime.

**Fix:** Use the oss-cad-suite GHDL (LLVM backend). Verify with `ghdl --version` - it must show `LLVM` in the output. For exhaustive checking, use `sby` instead of simulation.

### Yosys plugin error: GHDL not found

**Symptom:**
```
ERROR: Failed to load plugin: libghdl-*.so: cannot open shared object file
```

**Cause:** The oss-cad-suite environment is not active, or the GHDL Yosys plugin shared library is not on the library path.

**Fix:** Source the oss-cad-suite environment script and run `sby` again.

### OSVVM source directory deleted

**Symptom:** Build fails because `OsvvmLibraries/osvvm/*.vhd` files are missing.

**Cause:** OSVVM was built using `build osvvm/osvvm.pro` from within `OsvvmLibraries/`, which caused the build script to delete the `osvvm/` source directory.

**Fix:** Restore from the git submodule:

```bash
# From project root:
git submodule update --init OsvvmLibraries/osvvm
```

Then recompile using the safe procedure in @sec:recompiling-osvvm.

---

## Summary of File Locations

| Item | Path |
|------|------|
| oss-cad-suite (if installed to /opt) | `/opt/oss-cad-suite/` |
| oss-cad-suite environment script | `/opt/oss-cad-suite/environment` |
| Install helper script | `formal/install_oss_cad_suite.sh` |
| OSVVM compiled libs (oss-cad-suite) | `OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-6.0.0-dev/` |
| OSVVM compiled libs (system GHDL) | `OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-4.1.0/` |
| SymbiYosys job file | `formal/bit_stuffer_fd.sby` |
| PSL assertions | `src/bit_stuffer_fd.vhd` (lines 193-221, inside `architecture rtl`) |
| BMC results | `formal/bit_stuffer_fd_bmc/` |
| Prove results | `formal/bit_stuffer_fd_prove/` |
| Makefile | `Makefile` (see `OSVVM_LIB_PATH` on line 34) |
