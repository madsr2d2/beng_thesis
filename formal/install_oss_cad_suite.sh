#!/usr/bin/env bash
# Install oss-cad-suite — provides GHDL (LLVM backend) + Yosys + SymbiYosys + solvers.
# This is required to run formal verification with: sby formal/bit_stuffer_fd.sby
#
# After installation, activate with:
#   source /opt/oss-cad-suite/environment
#
# Run formal proof:
#   sby formal/bit_stuffer_fd.sby bmc      # bounded check (~seconds)
#   sby formal/bit_stuffer_fd.sby prove    # exhaustive k-induction (~minutes)

set -e

INSTALL_DIR="/opt/oss-cad-suite"
RELEASE_DATE=$(curl -sI https://github.com/YosysHQ/oss-cad-suite-build/releases/latest |
  grep -i location | grep -oP '\d{4}-\d{2}-\d{2}')

if [ -z "$RELEASE_DATE" ]; then
  echo "ERROR: Could not fetch latest oss-cad-suite release date."
  exit 1
fi

TARBALL="oss-cad-suite-linux-x64-${RELEASE_DATE//-/}.tgz"
URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${RELEASE_DATE}/${TARBALL}"

echo "Latest release: ${RELEASE_DATE}"
echo "Downloading: ${URL}"
echo "Install target: ${INSTALL_DIR}"
echo ""

mkdir -p /tmp/oss-cad-suite-dl
wget -q --show-progress -O "/tmp/oss-cad-suite-dl/${TARBALL}" "${URL}"

echo "Extracting to ${INSTALL_DIR} ..."
sudo mkdir -p "${INSTALL_DIR}"
sudo tar xzf "/tmp/oss-cad-suite-dl/${TARBALL}" -C /opt

rm "/tmp/oss-cad-suite-dl/${TARBALL}"

echo ""
echo "Installation complete."
echo "Activate with:  source ${INSTALL_DIR}/environment"
echo "Verify GHDL:    ghdl --version   (should show LLVM build)"
echo "Verify sby:     sby --help"
echo ""
echo "Run formal proof from project root:"
echo "  source ${INSTALL_DIR}/environment"
echo "  sby formal/bit_stuffer_fd.sby bmc"
