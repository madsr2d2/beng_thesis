#!/usr/bin/env bash

# This script is intended to be run with Bash.
if [ -z "$BASH_VERSION" ]; then
  echo "Error: This script must be run with bash. If you are using zsh, do not 'source' it; run it as an executable instead." >&2
  return 1 2>/dev/null || exit 1
fi

set -euo pipefail

# Robustly get the root directory of the project
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  # Bash or sourced in bash
  SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  # Zsh (sourced or executed)
  SCRIPT_PATH="${(%):-%x}"
else
  # Fallback
  SCRIPT_PATH="$0"
fi

ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: md_to_pdf.sh [--section NAME[,NAME...]] [INPUT_MD] [OUTPUT_PDF]

Options:
  --md-file PATH         Markdown input file (alias: --md_file).
  --output-pdf PATH      PDF output file.
  --table-style STYLE    Table style preset: clean or enhanced.
  --toc-depth N          TOC depth (default: 4).
  --section NAME         Select a section subtree by ID/alias; repeatable.
                         Accepts comma-separated values.
                         Examples:
                           --section verification_plan
                           --section sec:verification-results,discussion
  -h, --help             Show this help.

Environment:
  PANDOC_TABLE_STYLE     Table style preset for PDF output.
                         Values: clean (default), enhanced
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "required command not found: $cmd"
  fi
}

is_enabled() {
  local val
  val="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  case "$val" in
  1 | true | yes | on) return 0 ;;
  *) return 1 ;;
  esac
}

append_section_selector() {
  local value="$1"
  if [[ -z "$value" ]]; then
    die "--section requires a non-empty value."
  fi
  if [[ -n "$SECTION_SELECTOR" ]]; then
    SECTION_SELECTOR+=","
  fi
  SECTION_SELECTOR+="$value"
}

parse_args() {
  SECTION_SELECTOR=""
  INPUT_MD_OVERRIDE=""
  OUTPUT_PDF_OVERRIDE=""
  TABLE_STYLE_OVERRIDE=""
  TOC_DEPTH_OVERRIDE=""
  POSITIONAL_ARGS=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --md-file | --md_file | --input-md)
      [[ $# -ge 2 ]] || die "$1 requires a value."
      INPUT_MD_OVERRIDE="$2"
      shift 2
      ;;
    --md-file=* | --md_file=* | --input-md=*)
      INPUT_MD_OVERRIDE="${1#*=}"
      [[ -n "$INPUT_MD_OVERRIDE" ]] || die "${1%%=*} requires a non-empty value."
      shift
      ;;
    --output-pdf | --pdf-file | --output)
      [[ $# -ge 2 ]] || die "$1 requires a value."
      OUTPUT_PDF_OVERRIDE="$2"
      shift 2
      ;;
    --output-pdf=* | --pdf-file=* | --output=*)
      OUTPUT_PDF_OVERRIDE="${1#*=}"
      [[ -n "$OUTPUT_PDF_OVERRIDE" ]] || die "${1%%=*} requires a non-empty value."
      shift
      ;;
    --table-style)
      [[ $# -ge 2 ]] || die "$1 requires a value."
      TABLE_STYLE_OVERRIDE="$2"
      shift 2
      ;;
    --table-style=*)
      TABLE_STYLE_OVERRIDE="${1#*=}"
      [[ -n "$TABLE_STYLE_OVERRIDE" ]] || die "${1%%=*} requires a non-empty value."
      shift
      ;;
    --toc-depth)
      [[ $# -ge 2 ]] || die "$1 requires a value."
      TOC_DEPTH_OVERRIDE="$2"
      shift 2
      ;;
    --toc-depth=*)
      TOC_DEPTH_OVERRIDE="${1#*=}"
      [[ -n "$TOC_DEPTH_OVERRIDE" ]] || die "${1%%=*} requires a non-empty value."
      shift
      ;;
    --section)
      [[ $# -ge 2 ]] || die "--section requires a value."
      append_section_selector "$2"
      shift 2
      ;;
    --section=*)
      append_section_selector "${1#*=}"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONAL_ARGS+=("$1")
        shift
      done
      ;;
    -*)
      usage >&2
      die "unknown option: $1"
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
    esac
  done

  # Resolve positional args while allowing explicit input/output flags.
  if [[ -n "$INPUT_MD_OVERRIDE" && -n "$OUTPUT_PDF_OVERRIDE" ]]; then
    [[ ${#POSITIONAL_ARGS[@]} -eq 0 ]] || die "positional args are not allowed when both --md-file and --output-pdf are provided."
  elif [[ -n "$INPUT_MD_OVERRIDE" ]]; then
    [[ ${#POSITIONAL_ARGS[@]} -le 1 ]] || die "too many positional arguments when --md-file is provided (expected only OUTPUT_PDF)."
  elif [[ -n "$OUTPUT_PDF_OVERRIDE" ]]; then
    [[ ${#POSITIONAL_ARGS[@]} -le 1 ]] || die "too many positional arguments when --output-pdf is provided (expected only INPUT_MD)."
  else
    [[ ${#POSITIONAL_ARGS[@]} -le 2 ]] || die "too many positional arguments."
  fi
}

find_mermaid_filter_cmd() {
  local candidate
  for candidate in mermaid-filter pandoc-mermaid-filter pandoc-mermaid; do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

cleanup() {
  [[ -n "${TEMP_RENDERED_MD:-}" && -f "${TEMP_RENDERED_MD:-}" ]] && rm -f "$TEMP_RENDERED_MD"
  [[ -n "${TEMP_MD:-}" && -f "${TEMP_MD:-}" ]] && rm -f "$TEMP_MD"
  [[ -n "${TEMP_REQ_MD:-}" && -f "${TEMP_REQ_MD:-}" ]] && rm -f "$TEMP_REQ_MD"
  [[ -n "${TEMP_VPLAN_MD:-}" && -f "${TEMP_VPLAN_MD:-}" ]] && rm -f "$TEMP_VPLAN_MD"
  [[ -n "${TEMP_MERMAID_DIR:-}" && -d "${TEMP_MERMAID_DIR:-}" ]] && rm -rf "$TEMP_MERMAID_DIR"
}

main() {
  local -a POSITIONAL_ARGS TOC_ARGS CROSSREF_ARGS LUA_FILTER_ARGS

  parse_args "$@"

  if [[ -n "$INPUT_MD_OVERRIDE" ]]; then
    INPUT_MD="$INPUT_MD_OVERRIDE"
    OUTPUT_PDF="${OUTPUT_PDF_OVERRIDE:-${POSITIONAL_ARGS[0]:-$ROOT_DIR/docs/report.pdf}}"
  elif [[ -n "$OUTPUT_PDF_OVERRIDE" ]]; then
    INPUT_MD="${POSITIONAL_ARGS[0]:-$ROOT_DIR/docs/report.md}"
    OUTPUT_PDF="$OUTPUT_PDF_OVERRIDE"
  else
    INPUT_MD="${POSITIONAL_ARGS[0]:-$ROOT_DIR/docs/report.md}"
    OUTPUT_PDF="${POSITIONAL_ARGS[1]:-$ROOT_DIR/docs/report.pdf}"
  fi

  if [[ -z "$INPUT_MD" || -z "$OUTPUT_PDF" ]]; then
    usage >&2
    die "failed to resolve input/output paths."
  fi

  [[ -f "$INPUT_MD" ]] || die "input markdown not found: $INPUT_MD"

  require_cmd pandoc
  require_cmd mmdc

  MERMAID_FILTER_CMD="$(find_mermaid_filter_cmd)" || die "could not find Mermaid Pandoc filter (tried: mermaid-filter, pandoc-mermaid-filter, pandoc-mermaid)."

  PDF_ENGINE="${PDF_ENGINE:-xelatex}"
  PDF_MAINFONT="${PDF_MAINFONT:-Libertinus Serif}"
  PDF_FIG_WIDTH="${PDF_FIG_WIDTH:-\linewidth}"
  PDF_FIG_MAX_HEIGHT="${PDF_FIG_MAX_HEIGHT:-0.9\textheight}"
  PANDOC_TABLE_STYLE="$(echo "${TABLE_STYLE_OVERRIDE:-${PANDOC_TABLE_STYLE:-clean}}" | tr '[:upper:]' '[:lower:]')"
  PANDOC_TOC="${PANDOC_TOC:-0}"
  PANDOC_TOC_DEPTH="${TOC_DEPTH_OVERRIDE:-${PANDOC_TOC_DEPTH:-4}}"
  PANDOC_CROSSREF="${PANDOC_CROSSREF:-1}"
  PANDOC_FIG_PREFIX="${PANDOC_FIG_PREFIX:-Figure}"
  PANDOC_TBL_PREFIX="${PANDOC_TBL_PREFIX:-Table}"
  PANDOC_SEC_PREFIX="${PANDOC_SEC_PREFIX:-Section}"
  SANITIZE_GLYPHS="${SANITIZE_GLYPHS:-0}"
  PANDOC_TABLE_LAYOUT_FILTER="${PANDOC_TABLE_LAYOUT_FILTER:-$ROOT_DIR/scripts/filters/table_landscape.lua}"
  PANDOC_SECTION_SELECT_FILTER="${PANDOC_SECTION_SELECT_FILTER:-$ROOT_DIR/scripts/filters/select_sections.lua}"
  PANDOC_MERMAID_WIDTH_FILTER="${PANDOC_MERMAID_WIDTH_FILTER:-$ROOT_DIR/scripts/filters/mermaid_width.lua}"
  PANDOC_CELL_BREAK_FILTER="${PANDOC_CELL_BREAK_FILTER:-$ROOT_DIR/scripts/filters/cell_break.lua}"
  PANDOC_REQ_LINKS_FILTER="${PANDOC_REQ_LINKS_FILTER:-$ROOT_DIR/scripts/filters/req_links.lua}"

  case "$PANDOC_TABLE_STYLE" in
  clean | enhanced) ;;
  *)
    die "invalid table style '$PANDOC_TABLE_STYLE' (expected: clean or enhanced)."
    ;;
  esac

  TEMP_MERMAID_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mermaid-pandoc.XXXXXX")"
  TEMP_MD=""
  TEMP_RENDERED_MD=""
  trap cleanup EXIT

  OUTPUT_PDF_ABS="$(mkdir -p "$(dirname "$OUTPUT_PDF")" && cd "$(dirname "$OUTPUT_PDF")" && pwd)/$(basename "$OUTPUT_PDF")"
  INPUT_MD_ABS="$(cd "$(dirname "$INPUT_MD")" && pwd)/$(basename "$INPUT_MD")"
  INPUT_DIR="$(dirname "$INPUT_MD_ABS")"

  if [[ -f "$ROOT_DIR/mermaid-config.json" ]]; then
    export MERMAID_FILTER_MERMAID_CONFIG="$ROOT_DIR/mermaid-config.json"
  fi

  local mmdc_path
  mmdc_path="$(command -v mmdc)"
  export MERMAID_FILTER_CMD_MMDC="$mmdc_path"
  export MERMAID_FILTER_LOC="$TEMP_MERMAID_DIR"
  export MERMAID_FILTER_FORMAT="${MERMAID_FILTER_FORMAT:-png}"
  export MERMAID_FILTER_BACKGROUND="${MERMAID_FILTER_BACKGROUND:-transparent}"
  export MERMAID_FILTER_THEME="${MERMAID_FILTER_THEME:-default}"
  export MERMAID_FILTER_WIDTH="${MERMAID_FILTER_WIDTH:-1800}"
  export MERMAID_FILTER_SCALE="${MERMAID_FILTER_SCALE:-2}"

  if is_enabled "$PANDOC_TOC"; then
    TOC_ARGS=(--toc "--toc-depth=$PANDOC_TOC_DEPTH")
  else
    TOC_ARGS=()
  fi

  CROSSREF_ARGS=()
  if is_enabled "$PANDOC_CROSSREF"; then
    if command -v pandoc-crossref >/dev/null 2>&1; then
      CROSSREF_ARGS=(
        --filter pandoc-crossref
        -M "figPrefix=$PANDOC_FIG_PREFIX"
        -M "tblPrefix=$PANDOC_TBL_PREFIX"
        -M "secPrefix=$PANDOC_SEC_PREFIX"
      )
    else
      echo "Warning: pandoc-crossref not found; @fig/@tbl/@sec references may not resolve." >&2
    fi
  fi

  LUA_FILTER_ARGS=()
  if [[ -f "$PANDOC_TABLE_LAYOUT_FILTER" ]]; then
    LUA_FILTER_ARGS+=(--lua-filter "$PANDOC_TABLE_LAYOUT_FILTER")
  fi
  if [[ -f "$PANDOC_CELL_BREAK_FILTER" ]]; then
    LUA_FILTER_ARGS+=(--lua-filter "$PANDOC_CELL_BREAK_FILTER")
  fi
  if [[ -f "$PANDOC_REQ_LINKS_FILTER" ]]; then
    LUA_FILTER_ARGS+=(--lua-filter "$PANDOC_REQ_LINKS_FILTER")
  fi
  if [[ -f "$PANDOC_MERMAID_WIDTH_FILTER" ]]; then
    LUA_FILTER_ARGS+=(--lua-filter "$PANDOC_MERMAID_WIDTH_FILTER")
    export PANDOC_SOURCE_MD="$INPUT_MD_ABS"
  fi
  if [[ -n "$SECTION_SELECTOR" ]]; then
    [[ -f "$PANDOC_SECTION_SELECT_FILTER" ]] || die "section-selection filter not found: $PANDOC_SECTION_SELECT_FILTER"
    LUA_FILTER_ARGS+=(--lua-filter "$PANDOC_SECTION_SELECT_FILTER")
    export PANDOC_SECTION_IDS="$SECTION_SELECTOR"
  fi

  # Generate appendix tables from the verification plan TOML if sentinels are present
  TEMP_REQ_MD=""
  TEMP_VPLAN_MD=""
  if grep -qE '<!-- generated:(requirements|verification-plan)-table -->' "$INPUT_MD_ABS"; then
    VPLAN_TOML="$ROOT_DIR/verification_plan/verification_plan.toml"
    VPLAN_SCRIPT="$ROOT_DIR/verification_plan/verification_plan_table.py"
    if [[ -f "$VPLAN_SCRIPT" && -f "$VPLAN_TOML" ]]; then
      TEMP_REQ_MD="$(mktemp "$INPUT_DIR/.pandoc-req.XXXXXX.md")"
      TEMP_VPLAN_MD="$(mktemp "$INPUT_DIR/.pandoc-vplan.XXXXXX.md")"
      python3 "$VPLAN_SCRIPT" \
        --toml "$VPLAN_TOML" \
        --req-md "$TEMP_REQ_MD" \
        --vplan-md "$TEMP_VPLAN_MD" \
        >/dev/null
    else
      echo "Warning: verification plan script or TOML not found; sentinels left as-is." >&2
    fi
  fi

  TEMP_MD="$(mktemp "$INPUT_DIR/.pandoc-export.XXXXXX.md")"
  awk -v req="${TEMP_REQ_MD:-}" -v vplan="${TEMP_VPLAN_MD:-}" '
    BEGIN { in_mtoc = 0 }
    /^[[:space:]]*<!--[[:space:]]*mtoc-start[[:space:]]*-->[[:space:]]*$/ { in_mtoc = 1; next }
    /^[[:space:]]*<!--[[:space:]]*mtoc-end[[:space:]]*-->[[:space:]]*$/ { in_mtoc = 0; next }
    in_mtoc == 1 { next }
    /^[[:space:]]*##[[:space:]]+Table of Contents[[:space:]]*$/ { next }
    /^[[:space:]]*<!--[[:space:]]*generated:requirements-table[[:space:]]*-->[[:space:]]*$/ {
      if (req != "") { while ((getline line < req) > 0) print line; close(req) } else { print }
      next
    }
    /^[[:space:]]*<!--[[:space:]]*generated:verification-plan-table[[:space:]]*-->[[:space:]]*$/ {
      if (vplan != "") { while ((getline line < vplan) > 0) print line; close(vplan) } else { print }
      next
    }
    { print }
  ' "$INPUT_MD_ABS" >"$TEMP_MD"

  if is_enabled "$SANITIZE_GLYPHS"; then
    require_cmd perl
    perl -CSDA -i -pe 's/\x{2705}/[x]/g' "$TEMP_MD"
  fi

  pushd "$INPUT_DIR" >/dev/null

  TEMP_RENDERED_MD="$(mktemp "$INPUT_DIR/.pandoc-mermaid.XXXXXX.md")"
  pandoc "$TEMP_MD" \
    --standalone \
    --filter "$MERMAID_FILTER_CMD" \
    -t markdown \
    -o "$TEMP_RENDERED_MD"

  export PANDOC_DEFAULT_FIG_WIDTH="$PDF_FIG_WIDTH"
  export PANDOC_DEFAULT_FIG_MAX_HEIGHT="$PDF_FIG_MAX_HEIGHT"
  export PANDOC_TABLE_STYLE

  pandoc "$TEMP_RENDERED_MD" \
    --standalone \
    "${LUA_FILTER_ARGS[@]}" \
    "${CROSSREF_ARGS[@]}" \
    --citeproc \
    --table-caption-position=above \
    --pdf-engine="$PDF_ENGINE" \
    --number-sections \
    "${TOC_ARGS[@]}" \
    -V papersize:a4 \
    -V geometry:margin=2.2cm \
    -V fontsize=11pt \
    -V linestretch=1.15 \
    -V mainfont="$PDF_MAINFONT" \
    -V colorlinks=true \
    -V linkcolor=blue \
    -V urlcolor=blue \
    -o "$OUTPUT_PDF_ABS"

  popd >/dev/null

  # Clean up any stale pandoc temp files in the input directory
  find "$INPUT_DIR" -maxdepth 1 \( -name '.pandoc-*' -o -name 'mermaid-filter.err' \) -type f -delete

  echo "PDF generated: $OUTPUT_PDF_ABS"
}

main "$@"
