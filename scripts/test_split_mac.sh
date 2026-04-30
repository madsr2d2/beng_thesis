#!/usr/bin/env bash
# test_split_mac.sh -- Compile and run can_mac_pcs_fce_tb against the split-path
# MAC architecture (can_mac_split.vhd / architecture split_rtl) to verify that
# the bugs fixed in can_mac_fsm_tx.vhd and can_mac_fsm_rx.vhd are sufficient to
# make the split path pass the same 15707-affirmation test suite as the combined
# FSM (architecture rtl).
#
# Strategy: compile can_mac.vhd (rtl) first to register the entity, then compile
# can_mac_split.vhd (split_rtl) last. GHDL binds unqualified "entity work.can_mac"
# to the most-recently-analysed architecture, which will be split_rtl. This makes
# the testbench exercise the split path without modifying any source files.

set -euo pipefail

SIMDIR=sim/split_test
OSVVM_LIB=OsvvmLibraries/lib
GHDL=ghdl
FLAGS="--std=08 -fpsl -frelaxed --warn-no-vital-generic --warn-no-hide \
  -P${OSVVM_LIB}/osvvm/v08 \
  -P${OSVVM_LIB}/osvvm_common/v08 \
  -P${OSVVM_LIB} \
  -P."
STOP_TIME=${1:-500ms}

mkdir -p "$SIMDIR"

compile() {
  echo "  Analyzing $1"
  $GHDL -a $FLAGS --workdir="$SIMDIR" --work=work "$1"
}

echo "=== Split-path MAC test (architecture split_rtl) ==="
echo "Stop time: $STOP_TIME"
echo

echo "--- Packages ---"
compile src/can_types_p/hdl_src/can_types_p.vhd
compile src/can_tb_p/hdl_src/can_tb_p.vhd

echo "--- Shared submodules ---"
compile src/can_mac_bs/hdl_src/can_mac_bs.vhd
compile src/can_mac_crc/hdl_src/can_mac_crc.vhd
compile src/can_mac_ser_tx/hdl_src/can_mac_ser_tx.vhd

echo "--- Split TX/RX FSMs ---"
compile src/can_mac_tx/hdl_src/can_mac_fsm_tx.vhd
compile src/can_mac_rx/hdl_src/can_mac_fsm_rx.vhd

echo "--- Split TX/RX wrappers ---"
compile src/can_mac_tx/hdl_src/can_mac_tx.vhd
compile src/can_mac_rx/hdl_src/can_mac_rx.vhd

echo "--- FCE ---"
compile src/can_fce/hdl_src/can_fce.vhd

echo "--- Combined MAC FSM (needed to compile can_mac rtl architecture) ---"
compile src/can_mac/hdl_src/can_mac_fsm.vhd

echo "--- can_mac entity + rtl architecture ---"
compile src/can_mac/hdl_src/can_mac.vhd

echo "--- can_mac split_rtl architecture (will be default binding) ---"
compile src/can_mac/hdl_src/can_mac_split.vhd

echo "--- PCS and system-level layers ---"
compile src/can_pcs/hdl_src/can_pcs.vhd
compile src/can_mac_pcs_fce/hdl_src/can_mac_pcs_fce.vhd
compile src/can_llc_tx/hdl_src/can_llc_tx.vhd

echo "--- Testbench ---"
compile src/can_mac_pcs_fce/hdl_tb/can_mac_pcs_fce_tb.vhd

echo
echo "--- Elaborating can_mac_pcs_fce_tb ---"
$GHDL -m $FLAGS --workdir="$SIMDIR" --work=work \
  -o "$SIMDIR/can_mac_pcs_fce_tb" can_mac_pcs_fce_tb

echo
echo "--- Running simulation (stop-time=$STOP_TIME) ---"
"$SIMDIR/can_mac_pcs_fce_tb" \
  --wave="$SIMDIR/can_mac_pcs_fce_tb.ghw" \
  --stop-time="$STOP_TIME"

echo
echo "=== Done. Waveform: $SIMDIR/can_mac_pcs_fce_tb.ghw ==="
