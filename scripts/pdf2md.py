#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# =========================
# HTML / anchors / bullets
# =========================

_BR_TOKEN = "\ue000BR\ue000"  # internal marker for <br> placeholders


# =========================
# Markdown fence helpers
# =========================

_FENCE_LINE_RE = re.compile(r"^(?P<indent>\s*)(?P<fence>`{3,}|~{3,})(?P<info>.*)$")


def _split_fenced_blocks(text: str) -> list[tuple[bool, str]]:
    """Split text into (is_fenced_block, chunk) tuples preserving newlines."""
    lines = text.splitlines(keepends=True)
    blocks: list[tuple[bool, str]] = []
    buf: list[str] = []
    in_fence = False
    fence_char = ""
    fence_len = 0

    def flush(current_in_fence: bool) -> None:
        if buf:
            blocks.append((current_in_fence, "".join(buf)))
            buf.clear()

    for line in lines:
        candidate = _FENCE_LINE_RE.match(line.rstrip("\n"))
        if not in_fence and candidate:
            flush(in_fence)
            fence_char = candidate.group("fence")[0]
            fence_len = len(candidate.group("fence"))
            in_fence = True
            buf.append(line)
            continue

        if in_fence and candidate:
            seq = candidate.group("fence")
            if seq[0] == fence_char and len(seq) >= fence_len:
                buf.append(line)
                flush(True)
                in_fence = False
                fence_char = ""
                fence_len = 0
                continue

        buf.append(line)

    flush(in_fence)
    return blocks


def strip_html_preserve_code(text: str) -> str:
    """
    Strip HTML tags while preserving inline code spans.
    Convert <br> to a token resolved later with table-aware heuristics.
    """
    out_chunks: list[str] = []
    for is_fenced, chunk in _split_fenced_blocks(text):
        if is_fenced:
            out_chunks.append(chunk)
            continue

        parts = re.split(r"(`[^`]*`)", chunk)
        for i in range(0, len(parts), 2):
            seg = parts[i]
            seg = re.sub(r"<br\s*/?>", _BR_TOKEN, seg, flags=re.IGNORECASE)
            seg = re.sub(r"</p\s*>", "\n\n", seg, flags=re.IGNORECASE)
            seg = re.sub(r"<p(\s[^<>]*?)?>", "", seg, flags=re.IGNORECASE)
            seg = re.sub(r"<!--.*?-->", "", seg, flags=re.DOTALL)
            # drop remaining tags (e.g., <span id="...">)
            seg = re.sub(
                r"</?[A-Za-z][A-Za-z0-9-]*(\s[^<>]*?)?>",
                "",
                seg,
                flags=re.DOTALL,
            )
            parts[i] = seg
        out_chunks.append("".join(parts))
    return "".join(out_chunks)


def drop_internal_page_links(text: str) -> str:
    # turn "[2.1,](#page-3-1)" → "2.1," (preserve visible text, drop anchor)
    return re.sub(r"\[([^\]]+?)\]\(#page-\d+-\d+\)", r"\1", text)


def normalize_bullets(text: str) -> str:
    # PDF extractor sometimes emits Unicode bullets; make them lists.
    return re.sub(r"(?m)^([ \t]*)•[ \t]+", r"\1- ", text)


# ======================
# Contents removal
# ======================


def remove_contents_section(md: str) -> str:
    """
    Remove '# Contents' / '# Table of Contents' block (until the next markdown header).
    This eliminates the huge table-of-contents table produced by marker.
    """
    lines = md.splitlines()
    out, i, n = [], 0, len(lines)

    def is_contents_header(s: str) -> bool:
        return bool(
            re.match(r"^\s*#+\s*(contents|table of contents)\s*$", s, re.IGNORECASE)
        )

    while i < n:
        if is_contents_header(lines[i]):
            i += 1
            # skip everything until next heading
            while i < n and not re.match(r"^\s*#+\s+\S", lines[i]):
                i += 1
            while i < n and lines[i].strip() == "":
                i += 1
            continue
        out.append(lines[i])
        i += 1
    return "\n".join(out).rstrip() + "\n"


# ======================
# Headings normalization
# ======================

_NUMERIC_HEAD = re.compile(r"^\s*(\d+(?:\.\d+)*)\b")


def normalize_headings(md: str) -> str:
    """
    Keep the very first H1 as-is (document title).
    For all other ATX headings:
      - strip any residual html,
      - compute level from numeric prefix (2 → H2, 2.1 → H3, 2.1.3 → H4),
      - otherwise make them H2.
    This fixes MD025 (single H1) and MD001 (increment by one).
    """
    seen_h1 = False
    chunks: list[str] = []

    for is_fenced, block in _split_fenced_blocks(md):
        if is_fenced:
            chunks.append(block)
            continue

        lines = block.splitlines()
        processed: list[str] = []

        for ln in lines:
            m = re.match(r"^\s{0,3}(#{1,6})\s+(.*)$", ln)
            if not m:
                processed.append(ln)
                continue

            hashes, text = m.group(1), m.group(2).strip()

            if len(hashes) == 1 and not seen_h1:
                # first H1 stays H1
                seen_h1 = True
                processed.append(f"# {text}")
                continue

            # derive level from numeric prefix
            mnum = _NUMERIC_HEAD.match(text)
            if mnum:
                depth = mnum.group(1).count(".") + 1  # 2 → depth 1 → H2; 2.1 → depth 2 → H3
                level = min(1 + depth, 6)
            else:
                level = 2  # default demotion

            processed.append(f"{'#' * level} {text}")

        chunk_text = "\n".join(processed)
        if block.endswith("\n") and not chunk_text.endswith("\n"):
            chunk_text += "\n"
        chunks.append(chunk_text)

    result = "".join(chunks)
    if not result.endswith("\n"):
        result += "\n"
    return result


# ======================
# Table helpers
# ======================

_TABLE_ROW_START = re.compile(r"^\s*\|")
# Allow header separator with pipes and dashes/colons/spaces
_HYPHEN_LINE = re.compile(r"^\s*\|?\s*[:\- ]+\|?[:\- |]*$")


def _is_table_line(s: str) -> bool:
    stripped = s.strip()
    if not stripped:
        return False
    if _TABLE_ROW_START.match(s):
        return True
    return "|" in stripped and bool(_HYPHEN_LINE.match(s))


def _split_cells(row: str) -> list[str]:
    core = row.strip()
    if not core:
        return []
    if core.startswith("|"):
        core = core[1:]
    if core.endswith("|") and not (len(core) >= 2 and core[-2] == "\\"):
        core = core[:-1]

    cells: list[str] = []
    buf: list[str] = []
    escaped = False
    in_code = False
    code_tick_len = 0
    i = 0
    length = len(core)

    while i < length:
        ch = core[i]
        if escaped:
            buf.append(ch)
            escaped = False
            i += 1
            continue
        if ch == "\\":
            escaped = True
            i += 1
            continue
        if ch == "`":
            tick_len = 1
            while i + tick_len < length and core[i + tick_len] == "`":
                tick_len += 1
            if not in_code:
                in_code = True
                code_tick_len = tick_len
            elif tick_len == code_tick_len:
                in_code = False
                code_tick_len = 0
            buf.append("`" * tick_len)
            i += tick_len
            continue
        if ch == "|" and not in_code:
            cells.append("".join(buf).strip())
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1

    if escaped:
        buf.append("\\")
    cells.append("".join(buf).strip())
    return cells


def _canonicalize_row(row: str, cols: int, trim_tail: int = 0) -> str:
    cells = _split_cells(row)
    if trim_tail:
        keep = max(0, len(cells) - trim_tail)
        cells = cells[:keep]
    if len(cells) < cols:
        cells += [""] * (cols - len(cells))
    elif len(cells) > cols:
        tail = " | ".join(cells[cols - 1 :])
        cells = cells[: cols - 1] + [tail]
    return "| " + " | ".join(cells) + " |"


def _make_separator(cols: int) -> str:
    return "| " + " | ".join(["---"] * cols) + " |"


def _row_is_dashy(row: str) -> bool:
    cells = _split_cells(row)
    if not cells:
        return False
    return all(re.fullmatch(r"[:\-\s]*", c) for c in cells)


def _rebuild_single_table(block_lines: list[str]) -> str:
    """
    Given only table lines (already filtered), produce a single valid GFM table:
      header
      separator
      body...
    Consume at most one header-separator from the input; ignore any stray ones later.
    """
    # strip empty and non-table lines defensively (should not be here)
    rows = [ln.rstrip() for ln in block_lines if _is_table_line(ln) and ln.strip()]

    # find header: first non-dashy row
    i = 0
    while i < len(rows) and _row_is_dashy(rows[i]):
        i += 1
    if i >= len(rows):
        return "\n".join(block_lines).rstrip()

    header = rows[i]
    sep_idx = i + 1
    if sep_idx >= len(rows) or not _row_is_dashy(rows[sep_idx]):
        return "\n".join(block_lines).rstrip()

    parsed_rows = [_split_cells(header)]
    for r in rows[sep_idx + 1 :]:
        if _TABLE_ROW_START.match(r) and not _row_is_dashy(r):
            parsed_rows.append(_split_cells(r))

    cols = max(1, len(parsed_rows[0]))

    def column_empty(idx: int) -> bool:
        for cells in parsed_rows:
            if idx < len(cells) and cells[idx].strip():
                return False
        return True

    trim_tail = 0
    while cols - trim_tail > 1 and column_empty(cols - trim_tail - 1):
        trim_tail += 1

    cols = max(1, cols - trim_tail)
    out = []
    out.append(_canonicalize_row(header, cols, trim_tail=trim_tail))

    # consume one header separator if present
    i = sep_idx + 1
    out.append(_make_separator(cols))

    # body rows: only those starting with '|', skip dashy lines
    while i < len(rows):
        r = rows[i]
        if _row_is_dashy(r):
            i += 1
            continue
        if _TABLE_ROW_START.match(r):
            out.append(_canonicalize_row(r, cols, trim_tail=trim_tail))
        i += 1

    return "\n".join(out)


def reflow_pipe_tables(text: str) -> str:
    """
    Walk the document, and for each contiguous table block (strictly lines that are table lines),
    normalize it via _rebuild_single_table. Never pull captions or prose into the table.
    """
    lines = text.splitlines()
    out = []
    i, n = 0, len(lines)

    while i < n:
        if _is_table_line(lines[i]):
            block = [lines[i]]
            i += 1
            while i < n and _is_table_line(lines[i]):
                block.append(lines[i])
                i += 1
            table_md = _rebuild_single_table(block)
            if out and out[-1].strip():
                out.append("")
            out.extend(table_md.splitlines())
            if i < n and lines[i].strip():
                out.append("")
        else:
            out.append(lines[i])
            i += 1

    return "\n".join(out).rstrip() + "\n"


def ensure_blank_lines_around_tables(text: str) -> str:
    """Ensure a blank line before and after each table block, outside fences."""
    chunks: list[str] = []

    for is_fenced, block in _split_fenced_blocks(text):
        if is_fenced:
            chunks.append(block)
            continue

        lines = block.splitlines()
        out: list[str] = []
        i, n = 0, len(lines)

        while i < n:
            if _is_table_line(lines[i]):
                if out and out[-1].strip():
                    out.append("")
                while i < n and _is_table_line(lines[i]):
                    out.append(lines[i])
                    i += 1
                if i < n and lines[i].strip():
                    out.append("")
            else:
                out.append(lines[i])
                i += 1

        chunk_text = "\n".join(out)
        if block.endswith("\n") and not chunk_text.endswith("\n"):
            chunk_text += "\n"
        chunks.append(chunk_text)

    result = "".join(chunks)
    if not result.endswith("\n"):
        result += "\n"
    return result


def fix_common_table_cell_typos(text: str) -> str:
    """Normalize frequent cell typos inside table rows."""
    out = []
    for ln in text.splitlines():
        if _TABLE_ROW_START.match(ln):
            ln = re.sub(
                r"(\|\s*)input\s*/?\s*output(\s*\|)",
                r"\1input/output\2",
                ln,
                flags=re.IGNORECASE,
            )
        out.append(ln)
    return "\n".join(out) + "\n"


# ===========================
# Smart <br> handling
# ===========================


def smart_convert_br(md: str) -> str:
    """
    Replace _BR_TOKEN with:
      - ' ' inside table blocks,
      - '\n' elsewhere.
    """
    lines = md.splitlines()
    out = []
    i, n = 0, len(lines)

    while i < n:
        if _is_table_line(lines[i]):
            # in tables: replace with single space
            while i < n and _is_table_line(lines[i]):
                out.append(lines[i].replace(_BR_TOKEN, " "))
                i += 1
        else:
            # outside tables: turn into newlines
            seg = lines[i].replace(_BR_TOKEN, "\n")
            out.extend(seg.splitlines())
            i += 1
    return "\n".join(out) + "\n"


# ===========================
# Images: ensure alt text
# ===========================


def ensure_image_alts(md: str) -> str:
    # ![](path) -> ![Image](path)
    return re.sub(r"!\[\]\(", "![Image](", md)


# ===========================
# Media spacing
# ===========================

_IMAGE_BLOCK = re.compile(r"^!\[[^\]]*\]\([^\)]+\)$")
_CAPTION_LINE = re.compile(r"^\s*(?:Fig(?:\.|ure)?\.?|Figure|Table)\b", re.IGNORECASE)


def ensure_blank_lines_around_media(text: str) -> str:
    """Add blank lines before images and after captions, outside fences."""
    chunks: list[str] = []

    for is_fenced, block in _split_fenced_blocks(text):
        if is_fenced:
            chunks.append(block)
            continue

        lines = block.splitlines()
        out: list[str] = []
        last_line_was_image = False
        pending_gap_after_caption = False

        for line in lines:
            stripped = line.strip()

            if pending_gap_after_caption:
                if not stripped:
                    continue
                if not out or out[-1].strip():
                    out.append("")
                pending_gap_after_caption = False

            is_image = bool(_IMAGE_BLOCK.match(stripped))

            if is_image:
                indent = line[: len(line) - len(line.lstrip())]
                if (not out) or out[-1].strip():
                    out.append(indent if indent.strip() == "" else "")
                out.append(line)
                last_line_was_image = True
                continue

            if _CAPTION_LINE.match(stripped):
                if last_line_was_image:
                    last_line_was_image = False
                out.append(line)
                pending_gap_after_caption = True
                continue

            out.append(line)
            if stripped:
                last_line_was_image = False

        chunk_text = "\n".join(out)
        if block.endswith("\n") and not chunk_text.endswith("\n"):
            chunk_text += "\n"
        chunks.append(chunk_text)

    result = "".join(chunks)
    if not result.endswith("\n"):
        result += "\n"
    return result


# ===========================
# Ordered lists normalization
# ===========================


def normalize_ordered_lists(md: str) -> str:
    """
    Convert ordered list markers to '1.' style to satisfy MD029 "1/1/1".
    Keeps indentation and the rest of the text intact.
    """
    out = []
    for ln in md.splitlines():
        out.append(re.sub(r"^(\s*)\d+\.(\s+)", r"\g<1>1.\g<2>", ln))
    return "\n".join(out) + "\n"


# ===========================
# mdformat (optional)
# ===========================


def canonize_with_mdformat(md_text: str, compact_tables: bool = True) -> str:
    exe = shutil.which("mdformat")
    if not exe:
        return md_text
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "in.md"
        p.write_text(md_text, encoding="utf-8")
        cmd = [exe, str(p)]
        if compact_tables:
            cmd.insert(1, "--compact-tables")
        try:
            subprocess.run(
                cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
        except subprocess.CalledProcessError:
            return md_text
        return p.read_text(encoding="utf-8")


# ===========================
# Whitespace normalization
# ===========================


def normalize_whitespace(text: str) -> str:
    out = []
    in_code = False
    for ln in text.splitlines():
        if ln.strip().startswith("```"):
            in_code = not in_code
            out.append(ln.rstrip("\n"))
            continue
        out.append(ln if in_code else ln.rstrip())
    return "\n".join(out) + "\n"


# ===========================
# Pipeline
# ===========================


def post_process_markdown(md_text: str) -> str:
    # 1) strip html and page anchors, keep <br> as token
    txt = strip_html_preserve_code(md_text)
    txt = drop_internal_page_links(txt)
    txt = remove_contents_section(txt)
    txt = normalize_bullets(txt)

    # 2) heading normalization (single H1, numeric outline → levels)
    txt = normalize_headings(txt)

    # 3) resolve <br> token with table-aware heuristic
    txt = smart_convert_br(txt)

    # 4) tables: rebuild single logical tables only, never absorb captions
    txt = reflow_pipe_tables(txt)
    txt = ensure_blank_lines_around_tables(txt)
    txt = fix_common_table_cell_typos(txt)

    # 5) lists and images
    txt = normalize_ordered_lists(txt)
    txt = ensure_image_alts(txt)
    txt = ensure_blank_lines_around_media(txt)

    # 6) optional canonicalization (pretty-print) if mdformat is available
    txt = canonize_with_mdformat(txt, compact_tables=True)

    # 6b) enforce spacing again in case the formatter collapsed blank lines
    txt = ensure_blank_lines_around_tables(txt)
    txt = ensure_blank_lines_around_media(txt)

    # 7) final tidy
    txt = normalize_whitespace(txt)
    return txt


# ===========================
# marker-pdf runner
# ===========================


def run_marker_single(pdf_path: Path, outdir: Path) -> Path:
    exe = shutil.which("marker_single")
    if not exe:
        raise RuntimeError(
            "marker_single was not found in PATH. Install with:\n"
            "  pip install 'marker-pdf[all]'"
        )

    cfg = {
        "output_format": "markdown",
        "pdftext_workers": 6,
        "MarkdownRenderer": {"add_block_ids": False, "paginate_output": False},
        "layout_batch_size": 2,
        "detection_batch_size": 2,
        "recognition_batch_size": 2,
        "extract_images": True,
        "force_ocr": False,
    }

    outdir.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
        json.dump(cfg, tf)
        tf.flush()
        cfg_path = Path(tf.name)

    try:
        cmd = [
            exe,
            str(pdf_path),
            "--output_dir",
            str(outdir),
            "--config_json",
            str(cfg_path),
            "--output_format",
            "markdown",
        ]
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"marker_single failed with exit code {e.returncode}") from e
    finally:
        try:
            Path(cfg_path).unlink(missing_ok=True)
        except Exception:
            pass

    return outdir / pdf_path.stem


def find_markdown_file(product_dir: Path) -> Path:
    md_files = sorted(product_dir.glob("*.md")) or sorted(product_dir.rglob("*.md"))
    if not md_files:
        raise FileNotFoundError(f"No markdown file found in {product_dir}")
    preferred = product_dir / (product_dir.name + ".md")
    return preferred if preferred.exists() else md_files[0]


# ===========================
# Main
# ===========================


def overwrite_file(path: Path, content: str, backup: bool) -> None:
    if backup:
        bak = path.with_suffix(path.suffix + ".bak")
        bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    path.write_text(content, encoding="utf-8")


def main() -> int:
    p = argparse.ArgumentParser(
        description=(
            "Normalize Marker-PDF Markdown: drop Contents, fix headings (single H1, numeric outline), "
            "smart <br>, stable GFM tables (no caption absorption), ordered-list 1./1./1., and image alts. "
            "Accepts .md (in-place) or .pdf (via marker_single → then in-place on generated .md)."
        )
    )
    p.add_argument("input", type=Path, help="Path to input .md or .pdf")
    p.add_argument(
        "--outdir",
        type=Path,
        default=Path("md_out"),
        help="Output dir for marker when input is a PDF (default: md_out)",
    )
    p.add_argument(
        "--backup",
        action="store_true",
        help="Write a .bak next to the Markdown before overwriting",
    )
    args = p.parse_args()

    in_path = args.input.resolve()
    if not in_path.exists():
        print(f"Error: {in_path} does not exist.", file=sys.stderr)
        return 2

    if in_path.suffix.lower() == ".md":
        raw = in_path.read_text(encoding="utf-8")
        processed = post_process_markdown(raw)
        overwrite_file(in_path, processed, backup=args.backup)
        print(f"Updated in place: {in_path}")
        return 0

    if in_path.suffix.lower() == ".pdf":
        product_dir = run_marker_single(in_path, args.outdir.resolve())
        md_path = find_markdown_file(product_dir)
        raw = md_path.read_text(encoding="utf-8")
        processed = post_process_markdown(raw)
        overwrite_file(md_path, processed, backup=args.backup)
        print(f"Generated with marker and updated in place: {md_path}")
        return 0

    print("Error: input must be .md or .pdf", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
