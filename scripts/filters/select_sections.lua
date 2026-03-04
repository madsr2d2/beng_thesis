-- Keep only selected section subtrees.
-- Read selected IDs/aliases from:
--   PANDOC_SECTION_IDS="verification_plan,sec:verification-results"

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize(s)
  s = (s or ""):lower()
  s = s:gsub("[^%w]+", "-")
  s = s:gsub("%-+", "-")
  s = s:gsub("^%-", "")
  s = s:gsub("%-$", "")
  return s
end

local STOPWORDS = {
  ["a"] = true,
  ["an"] = true,
  ["and"] = true,
  ["for"] = true,
  ["in"] = true,
  ["of"] = true,
  ["on"] = true,
  ["the"] = true,
  ["to"] = true,
}

local function canonical(s)
  local n = normalize(s)
  local out = {}
  for part in n:gmatch("[^-]+") do
    if not STOPWORDS[part] then
      table.insert(out, part)
    end
  end
  return table.concat(out, "-")
end

local function parse_selected()
  local raw = os.getenv("PANDOC_SECTION_IDS") or ""
  if raw == "" then
    return {}, {}
  end

  local selected = {}
  local queries = {}
  for token in raw:gmatch("[^,]+") do
    local t = trim(token)
    if t ~= "" then
      local n = normalize(t)
      local c = canonical(t)
      local sec_n = "sec:" .. n
      table.insert(queries, n)
      if c ~= "" then
        table.insert(queries, c)
      end

      selected[t] = true
      selected[n] = true
      if c ~= "" then
        selected[c] = true
      end
      selected[t:gsub("_", "-")] = true

      if t:match("^sec:") then
        local tail = t:sub(5)
        selected[normalize(tail)] = true
        local tail_c = canonical(tail)
        if tail_c ~= "" then
          selected[tail_c] = true
        end
      else
        selected["sec:" .. t] = true
      end
      selected[sec_n] = true
    end
  end
  return selected, queries
end

local SELECTED, QUERIES = parse_selected()

local function is_match(identifier)
  if identifier == nil or identifier == "" then
    return false
  end
  if SELECTED[identifier] then
    return true
  end

  local n = normalize(identifier)
  local c = canonical(identifier)
  if SELECTED[n] then
    return true
  end
  if c ~= "" and SELECTED[c] then
    return true
  end

  if identifier:match("^sec:") then
    local tail = identifier:sub(5)
    if SELECTED[tail] or SELECTED[normalize(tail)] then
      return true
    end
    local tail_c = canonical(tail)
    if tail_c ~= "" and SELECTED[tail_c] then
      return true
    end
  else
    if SELECTED["sec:" .. n] then
      return true
    end
  end

  for _, q in ipairs(QUERIES) do
    if q ~= "" and (n:sub(1, #q) == q or (c ~= "" and c:sub(1, #q) == q)) then
      return true
    end
  end
  return false
end

function Pandoc(doc)
  if next(SELECTED) == nil then
    return doc
  end

  local out = {}
  local stack = {}
  local matched_headers = 0

  local function current_include()
    if #stack == 0 then
      return false
    end
    return stack[#stack].include
  end

  for _, block in ipairs(doc.blocks) do
    if block.t == "Header" then
      while #stack > 0 and stack[#stack].level >= block.level do
        table.remove(stack)
      end

      local header_text = pandoc.utils.stringify(block.content or {})
      local self_match = is_match(block.identifier) or is_match(header_text)
      if self_match then
        matched_headers = matched_headers + 1
      end
      local include = current_include() or self_match
      table.insert(stack, { level = block.level, include = include })

      if include then
        table.insert(out, block)
      end
    else
      if current_include() then
        table.insert(out, block)
      end
    end
  end

  if matched_headers == 0 then
    io.stderr:write("Error: --section did not match any headings.\n")
    io.stderr:write("Hint: use section IDs like 'sec:design-architecture' or aliases like 'design_and_architecture'.\n")
    os.exit(2)
  end

  return pandoc.Pandoc(out, doc.meta)
end
