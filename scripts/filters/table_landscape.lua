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
  local fig_setkeys = string.format(
    "\\AtBeginDocument{\\setkeys{Gin}{width=%s,height=%s,keepaspectratio}}",
    fig_width,
    fig_height
  )

  local header = meta["header-includes"] or {}
  if header.t == "MetaInlines" or header.t == "MetaBlocks" then
    header = { header }
  end

  table.insert(header, pandoc.MetaBlocks({
    pandoc.RawBlock("latex", "\\usepackage{graphicx}"),
    pandoc.RawBlock("latex", "\\usepackage{pdflscape}"),
    pandoc.RawBlock("latex", fig_setkeys)
  }))
  meta["header-includes"] = header
  return meta
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
