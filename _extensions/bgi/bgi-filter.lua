--- bgi-filter.lua
--- Pandoc Lua filter for BGI Quarto RevealJS template.
--- Auto-applies section-slide attributes when a heading has class .section-slide
--- Uses the extracted title slide background image for consistent look.

-- Resolve relative path from filter location to bg image
local function get_bg_image_path()
  local script = PANDOC_SCRIPT_FILE
  local dir = pandoc.path.directory(script)
  local abs = pandoc.path.join({dir, "title-bg.png"})
  local rel = pandoc.path.make_relative(abs, pandoc.system.get_working_directory())
  -- Normalize to forward slashes for HTML compatibility
  return rel:gsub("\\", "/")
end

local bg_image = get_bg_image_path()

function Header(el)
  if el.level == 2 and el.classes:includes("section-slide") then
    el.attributes["data-background-color"] = "#115780"
    el.attributes["data-background-image"] = bg_image
    el.attributes["data-background-size"] = "cover"
    el.attributes["data-background-position"] = "center"
  end
  return el
end
