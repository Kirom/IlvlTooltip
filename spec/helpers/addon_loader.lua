local Loader = {}

local FULL_MODULE_LIST = {
    "IlvlTooltip_Constants.lua",
    "IlvlTooltip_Settings.lua",
    "IlvlTooltip_Safe.lua",
    "IlvlTooltip_Cache.lua",
    "IlvlTooltip_TooltipView.lua",
    "IlvlTooltip_Inspect.lua",
    "IlvlTooltip_Controller.lua",
    "IlvlTooltip.lua",
}

function Loader.Reset()
    _G.IlvlTooltip = nil
end

function Loader.LoadModules(files)
    Loader.Reset()
    for i = 1, #files do
        dofile(files[i])
    end
    return _G.IlvlTooltip
end

function Loader.LoadCore()
    return Loader.LoadModules({
        "IlvlTooltip_Constants.lua",
        "IlvlTooltip_Settings.lua",
        "IlvlTooltip_Safe.lua",
        "IlvlTooltip_Cache.lua",
        "IlvlTooltip_TooltipView.lua",
        "IlvlTooltip_Inspect.lua",
        "IlvlTooltip_Controller.lua",
    })
end

function Loader.LoadAll()
    return Loader.LoadModules(FULL_MODULE_LIST)
end

return Loader
