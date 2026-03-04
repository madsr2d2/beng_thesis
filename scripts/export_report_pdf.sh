#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Warning: scripts/export_report_pdf.sh is deprecated. Use scripts/md_to_pdf.sh instead." >&2
exec "$SCRIPT_DIR/md_to_pdf.sh" "$@"
