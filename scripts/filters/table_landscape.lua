-- Rotate table-heavy sections when wrapped in a fenced Div:
-- ::: {.landscape-tables}
-- ... tables ...
-- :::

local function has_class(el, class_name)
  for _, c in ipairs(el.classes or {}) do
    if c == class_name then
      return true
    end
  end
  return false
end

function Meta(meta)
  if not FORMAT:match("latex") then
    return meta
  end

  local fig_width = os.getenv("PANDOC_DEFAULT_FIG_WIDTH") or "\\linewidth"
  local fig_height = os.getenv("PANDOC_DEFAULT_FIG_MAX_HEIGHT") or "0.82\\textheight"
  local table_style = (os.getenv("PANDOC_TABLE_STYLE") or "clean"):lower()
  local fig_setkeys = string.format(
    "\\AtBeginDocument{\\setkeys{Gin}{width=%s,height=%s,keepaspectratio}}",
    fig_width,
    fig_height
  )

  local header = meta["header-includes"] or {}
  if header.t == "MetaInlines" or header.t == "MetaBlocks" then
    header = { header }
  end

  local blocks = {
    pandoc.RawBlock("latex", "\\usepackage{graphicx}"),
    pandoc.RawBlock("latex", "\\usepackage{pdflscape}"),
    pandoc.RawBlock("latex", "\\raggedbottom"),
    pandoc.RawBlock("latex", "\\usepackage{float}"),
    pandoc.RawBlock("latex", "\\floatplacement{figure}{htbp}"),
    pandoc.RawBlock("latex", "\\floatplacement{table}{htbp}"),
    pandoc.RawBlock("latex", "\\setcounter{topnumber}{3}"),
    pandoc.RawBlock("latex", "\\setcounter{bottomnumber}{0}"),
    pandoc.RawBlock("latex", fig_setkeys)
  }

  if table_style == "enhanced" then
    table.insert(blocks, pandoc.RawBlock("latex", "\\usepackage[table]{xcolor}"))
    table.insert(blocks, pandoc.RawBlock("latex", "\\usepackage{cellspace}"))
    table.insert(blocks, pandoc.RawBlock("latex", "\\usepackage{makecell}"))
    table.insert(blocks, pandoc.RawBlock("latex", "\\usepackage{caption}"))
    table.insert(blocks, pandoc.RawBlock("latex", "\\setlength\\cellspacetoplimit{3pt}"))
    table.insert(blocks, pandoc.RawBlock("latex", "\\setlength\\cellspacebottomlimit{3pt}"))
    table.insert(blocks, pandoc.RawBlock("latex", "\\definecolor{TableStripe}{gray}{0.94}"))
    table.insert(blocks, pandoc.RawBlock("latex", "\\captionsetup[table]{labelfont=bf,font=small,skip=6pt}"))
    table.insert(blocks, pandoc.RawBlock("latex", "\\AtBeginEnvironment{longtable}{\\small\\setlength{\\tabcolsep}{5pt}\\renewcommand{\\arraystretch}{1.18}}"))
    table.insert(blocks, pandoc.RawBlock("latex", "\\AtBeginEnvironment{tabular}{\\small\\setlength{\\tabcolsep}{5pt}\\renewcommand{\\arraystretch}{1.15}}"))
  end

  table.insert(header, pandoc.MetaBlocks(blocks))
  meta["header-includes"] = header
  return meta
end

function Table(el)
  if not FORMAT:match("latex") then
    return el
  end

  -- Pin column widths for the 2-column abbreviations table so it spans \linewidth.
  -- Pandoc emits ColWidthDefault (natural l/r columns) when the separator is short;
  -- explicit fractions force p{...} columns that together fill the line.
  if #el.colspecs == 2 then
    local first_row = el.head and el.head.rows and el.head.rows[1]
    if first_row and first_row.cells[1] then
      if pandoc.utils.stringify(first_row.cells[1]) == "Abbreviation" then
        local fractions = { 0.18, 0.82 }
        local new_specs = {}
        for i, spec in ipairs(el.colspecs) do
          new_specs[i] = { spec[1], fractions[i] }
        end
        el.colspecs = new_specs
      end
    end
  end

  -- Pin column widths for the 5-column requirements appendix table.
  -- Separator-based proportions lose to unbreakable \href{} content; setting
  -- colspecs here overrides them. Fractions must sum to 1.0.
  -- ID(0.08): fits "REQ-001" on one line. Priority(0.08): fits "Priority" header.
  if #el.colspecs == 5 then
    local first_row = el.head and el.head.rows and el.head.rows[1]
    if first_row and first_row.cells[1] then
      if pandoc.utils.stringify(first_row.cells[1]) == "ID" then
        local fractions = { 0.13, 0.11, 0.08, 0.43, 0.25 }
        local new_specs = {}
        for i, spec in ipairs(el.colspecs) do
          new_specs[i] = { spec[1], fractions[i] }
        end
        el.colspecs = new_specs
      end
    end
  end

  local table_style = (os.getenv("PANDOC_TABLE_STYLE") or "clean"):lower()
  if table_style ~= "enhanced" then
    return el
  end

  -- Inject \cellcolor{TableStripe} into every header cell.
  -- \cellcolor works inside cells (no \noalign needed) and is independent of
  -- the row counter, so header color is guaranteed regardless of longtable
  -- counter reset behaviour at \endhead.
  if el.head and el.head.rows then
    for _, row in ipairs(el.head.rows) do
      for _, cell in ipairs(row.cells) do
        if #cell.contents == 0 then
          cell.contents = { pandoc.Plain({ pandoc.RawInline("latex", "\\cellcolor{TableStripe}") }) }
        elseif cell.contents[1].t == "Plain" or cell.contents[1].t == "Para" then
          table.insert(cell.contents[1].content, 1, pandoc.RawInline("latex", "\\cellcolor{TableStripe}"))
        end
      end
    end
  end

  -- Counter does not reset at \endhead, so row 2 is the first data row.
  -- \rowcolors{2}{white}{TableStripe} makes row 2=white, row 3=gray, row 4=white, ...
  -- The header (row 1) is forced gray independently via \cellcolor above.
  return {
    pandoc.RawBlock("latex", "{\\rowcolors{2}{white}{TableStripe}"),
    el,
    pandoc.RawBlock("latex", "}")
  }
end

function Div(el)
  if not FORMAT:match("latex") then
    return nil
  end

  if has_class(el, "landscape-tables") then
    local out = {
      pandoc.RawBlock("latex", "\\begin{landscape}"),
      pandoc.RawBlock("latex", "\\begingroup"),
      pandoc.RawBlock("latex", "\\footnotesize"),
      pandoc.RawBlock("latex", "\\setlength{\\tabcolsep}{3pt}"),
      pandoc.RawBlock("latex", "\\renewcommand{\\arraystretch}{1.1}")
    }
    for _, block in ipairs(el.content) do
      table.insert(out, block)
    end
    table.insert(out, pandoc.RawBlock("latex", "\\endgroup"))
    table.insert(out, pandoc.RawBlock("latex", "\\end{landscape}"))
    return out
  end

  return nil
end
