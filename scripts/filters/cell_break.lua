-- cell_break.lua: replace []{.break} spans with \newline in LaTeX output.
-- Used to insert line breaks within pipe table cells for PDF generation.
function Span(el)
  if el.classes:includes("break") then
    return pandoc.RawInline("latex", "\\newline ")
  end
end
