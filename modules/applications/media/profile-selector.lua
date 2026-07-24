local mp = require "mp"
local input = require "mp.input"

local profiles = {
  { label = "Anime4K upscaling", name = "anime4k" },
  { label = "Frame interpolation", name = "interpolation" },
  { label = "Anime4K + frame interpolation", name = "anime4k-interpolation" },
  { label = "Standard rendering", name = "standard" },
}

mp.add_key_binding("Ctrl+Shift+p", "profile-selector", function()
  local labels = {}

  for _, profile in ipairs(profiles) do
    labels[#labels + 1] = profile.label
  end

  input.select({
    prompt = "Profile:",
    items = labels,
    submit = function(index)
      if index == nil then
        return
      end

      local profile = profiles[index]
      mp.commandv("apply-profile", profile.name)
      mp.osd_message("Profile: " .. profile.label)
    end,
  })
end)
