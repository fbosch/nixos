local mp = require "mp"
local input = require "mp.input"

local profiles = {
  { label = "Upscaling: None", name = "upscaling-off" },
  { label = "Upscaling: Anime4K", name = "anime4k" },
  { label = "Upscaling: AMD FidelityFX Super Resolution", name = "fsr" },
  { label = "Upscaling: FSRCNNX neural-network", name = "fsrcnnx" },
  { label = "Upscaling: NVIDIA Image Scaling", name = "nvscaler" },
  { label = "Motion: Off", name = "interpolation-off" },
  { label = "Motion: Display-rate interpolation", name = "interpolation" },
  { label = "Debanding: Off", name = "deband-off" },
  { label = "Debanding: Light", name = "deband" },
  { label = "Reset rendering", name = "reset" },
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
