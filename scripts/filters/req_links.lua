-- req_links.lua
-- Converts REQ-NNN tokens to hyperlinks targeting the requirements appendix anchor.
-- Skips spans with class req-id (the anchor cells in the generated table).

local function req_link(id)
  return pandoc.Link({pandoc.Str(id)}, "#" .. id:lower())
end

local function split_req_refs(inlines)
  local result = {}
  local changed = false
  for _, inline in ipairs(inlines) do
    if inline.t == "Str" and inline.text:find("REQ%-%d%d%d") then
      changed = true
      local text = inline.text
      local last = 1
      for s, id, e in text:gmatch("()(REQ%-%d%d%d)()") do
        if s > last then
          result[#result + 1] = pandoc.Str(text:sub(last, s - 1))
        end
        result[#result + 1] = req_link(id)
        last = e
      end
      if last <= #text then
        result[#result + 1] = pandoc.Str(text:sub(last))
      end
    else
      result[#result + 1] = inline
    end
  end
  return changed and result or nil
end

return {
  traverse = "topdown",
  Span = function(el)
    if el.classes:includes("req-id") then
      return el, false
    end
  end,
  Link = function(el)
    if el.target:match("^#req%-%d") then
      return el, false
    end
  end,
  Inlines = split_req_refs,
}
