-- mermaid_width.lua
-- Reads `fig-width=<fraction>` attributes from mermaid code blocks in the original
-- source file and applies them as percentage widths to the corresponding figures
-- in the final pandoc pass (matched by figure ID).
--
-- Usage: set PANDOC_SOURCE_MD to the path of the original markdown file before
-- invoking pandoc, then include this filter with --lua-filter.
--
-- NOTE: use `fig-width=` (not `width=`) to avoid mermaid-filter intercepting
-- the attribute and passing it to mmdc as a pixel width (which breaks on fractions).
--
-- Example block attribute:
--   ```{.mermaid #fig:my-diagram fig-width=0.7 caption="..."}
-- Result: image rendered at 70% of text width in the PDF.
--
-- After mermaid-filter runs, the ID lives on the Figure element (not the inner
-- Image), so this filter uses pandoc.walk_block to patch the nested Image.

local widths = {}

local function load_widths()
  local source_file = os.getenv("PANDOC_SOURCE_MD")
  if not source_file then return end

  local f = io.open(source_file, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()

  for pre, post in content:gmatch("```{([^}]*)mermaid([^}]*)}") do
    local full = pre .. post
    local id    = full:match("#([%w:%-_]+)")
    local width = full:match("fig%-width=([%d%.]+)")
    if id and width then
      widths[id] = tonumber(width)
    end
  end
end

load_widths()

function Figure(el)
  local id = el.identifier
  if id == "" or not widths[id] then return end

  local pct = string.format("%.0f%%", widths[id] * 100)

  return pandoc.walk_block(el, {
    Image = function(img)
      img.attributes["width"] = pct
      return img
    end
  })
end
