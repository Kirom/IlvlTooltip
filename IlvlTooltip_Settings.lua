local NS = IlvlTooltip or {}
IlvlTooltip = NS

local C = NS.Constants
local API = NS.Api

local math_floor = math.floor
local math_max = math.max
local pcall = pcall
local string_format = string.format
local tonumber = tonumber
local type = type

local SettingsService = NS.Settings or {}
NS.Settings = SettingsService

local initialized = false
local optionsRegistered = false
local optionsPanel = nil

local function clampInteger(value, minValue, maxValue, defaultValue)
    local numeric = tonumber(value)
    if not numeric then
        numeric = defaultValue
    end

    numeric = math_floor(numeric + 0.5)
    if numeric < minValue then
        numeric = minValue
    elseif numeric > maxValue then
        numeric = maxValue
    end

    return numeric
end

local function ensureDatabase()
    if type(_G.IlvlTooltipDB) ~= "table" then
        _G.IlvlTooltipDB = {}
    end

    local db = _G.IlvlTooltipDB
    local hot = clampInteger(db.hotCacheTTL, C.HOT_CACHE_TTL_MIN, C.HOT_CACHE_TTL_MAX, C.HOT_CACHE_TTL)
    local warm = clampInteger(db.warmCacheTTL, C.WARM_CACHE_TTL_MIN, C.WARM_CACHE_TTL_MAX, C.WARM_CACHE_TTL)
    warm = math_max(warm, hot)

    db.hotCacheTTL = hot
    db.warmCacheTTL = warm
    return db
end

function SettingsService.Initialize()
    if initialized then
        return
    end

    initialized = true
    ensureDatabase()
end

function SettingsService.GetHotCacheTTL()
    return ensureDatabase().hotCacheTTL
end

function SettingsService.GetWarmCacheTTL()
    return ensureDatabase().warmCacheTTL
end

function SettingsService.SetHotCacheTTL(value)
    local db = ensureDatabase()
    local hot = clampInteger(value, C.HOT_CACHE_TTL_MIN, C.HOT_CACHE_TTL_MAX, db.hotCacheTTL)

    db.hotCacheTTL = hot
    if db.warmCacheTTL < hot then
        db.warmCacheTTL = hot
    end
end

function SettingsService.SetWarmCacheTTL(value)
    local db = ensureDatabase()
    local warm = clampInteger(value, C.WARM_CACHE_TTL_MIN, C.WARM_CACHE_TTL_MAX, db.warmCacheTTL)

    db.warmCacheTTL = warm
    if db.hotCacheTTL > warm then
        db.hotCacheTTL = warm
    end
end

local function registerLegacyCategory(panel)
    if _G.InterfaceOptions_AddCategory then
        _G.InterfaceOptions_AddCategory(panel)
        return true
    end

    if _G.InterfaceOptionsFrame_AddCategory then
        _G.InterfaceOptionsFrame_AddCategory(panel)
        return true
    end

    return false
end

local function createOptionsPanel()
    local settingsApi = _G.Settings
    local hasSettingsApi = settingsApi and settingsApi.RegisterCanvasLayoutCategory and settingsApi.RegisterAddOnCategory
    local hasLegacyApi = _G.InterfaceOptions_AddCategory or _G.InterfaceOptionsFrame_AddCategory
    if not hasSettingsApi and not hasLegacyApi then
        return nil
    end

    if not API.CreateFrame then
        return nil
    end

    local panel = API.CreateFrame("Frame", "IlvlTooltipSettingsPanel", _G.UIParent)
    if not panel then
        return nil
    end

    panel.name = "iLvl Tooltip"

    if panel.SetSize then
        panel:SetSize(640, 480)
    end

    local title = panel.CreateFontString and panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge") or nil
    if title and title.SetPoint and title.SetText then
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
        title:SetText("iLvl Tooltip")
    end

    local subtitle = panel.CreateFontString and panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight") or nil
    if subtitle and subtitle.SetPoint and subtitle.SetText then
        subtitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -42)
        subtitle:SetText("Configure item level cache time-to-live values (seconds).")
    end

    local hotSlider = API.CreateFrame("Slider", "IlvlTooltipHotCacheTTLSlider", panel, "OptionsSliderTemplate")
    local warmSlider = API.CreateFrame("Slider", "IlvlTooltipWarmCacheTTLSlider", panel, "OptionsSliderTemplate")
    if not hotSlider or not warmSlider then
        return nil
    end

    hotSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -82)
    hotSlider:SetWidth(360)
    hotSlider:SetMinMaxValues(C.HOT_CACHE_TTL_MIN, C.HOT_CACHE_TTL_MAX)
    hotSlider:SetValueStep(C.HOT_CACHE_TTL_STEP)
    if hotSlider.SetObeyStepOnDrag then
        hotSlider:SetObeyStepOnDrag(true)
    end

    warmSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -152)
    warmSlider:SetWidth(360)
    warmSlider:SetValueStep(C.WARM_CACHE_TTL_STEP)
    if warmSlider.SetObeyStepOnDrag then
        warmSlider:SetObeyStepOnDrag(true)
    end

    local function setSliderBounds(slider, minValue, maxValue)
        slider:SetMinMaxValues(minValue, maxValue)

        local low = _G[slider:GetName() .. "Low"]
        if low and low.SetText then
            low:SetText(tostring(minValue))
        end

        local high = _G[slider:GetName() .. "High"]
        if high and high.SetText then
            high:SetText(tostring(maxValue))
        end
    end

    local function setSliderCaption(slider, label, value)
        local caption = _G[slider:GetName() .. "Text"]
        if caption and caption.SetText then
            caption:SetText(string_format("%s: %ds", label, value))
        end
    end

    local isRefreshing = false
    local function refreshControls()
        isRefreshing = true

        local hotValue = SettingsService.GetHotCacheTTL()
        local warmValue = SettingsService.GetWarmCacheTTL()

        setSliderBounds(hotSlider, C.HOT_CACHE_TTL_MIN, C.HOT_CACHE_TTL_MAX)
        setSliderBounds(warmSlider, math_max(C.WARM_CACHE_TTL_MIN, hotValue), C.WARM_CACHE_TTL_MAX)

        hotSlider:SetValue(hotValue)
        warmSlider:SetValue(warmValue)

        setSliderCaption(hotSlider, "Hot cache TTL", hotValue)
        setSliderCaption(warmSlider, "Warm cache TTL", warmValue)

        isRefreshing = false
    end

    hotSlider:SetScript("OnValueChanged", function(_, value)
        if isRefreshing then
            return
        end

        local rounded = clampInteger(value, C.HOT_CACHE_TTL_MIN, C.HOT_CACHE_TTL_MAX, SettingsService.GetHotCacheTTL())
        SettingsService.SetHotCacheTTL(rounded)
        refreshControls()
    end)

    warmSlider:SetScript("OnValueChanged", function(_, value)
        if isRefreshing then
            return
        end

        local rounded = clampInteger(value, C.WARM_CACHE_TTL_MIN, C.WARM_CACHE_TTL_MAX, SettingsService.GetWarmCacheTTL())
        SettingsService.SetWarmCacheTTL(rounded)
        refreshControls()
    end)

    local defaultsButton = API.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    if defaultsButton then
        defaultsButton:SetPoint("TOPLEFT", warmSlider, "BOTTOMLEFT", 0, -18)
        defaultsButton:SetSize(140, 24)
        defaultsButton:SetText("Reset To Defaults")
        defaultsButton:SetScript("OnClick", function()
            SettingsService.SetHotCacheTTL(C.HOT_CACHE_TTL)
            SettingsService.SetWarmCacheTTL(C.WARM_CACHE_TTL)
            refreshControls()
        end)
    end

    if panel.SetScript then
        panel:SetScript("OnShow", refreshControls)
    end

    refreshControls()

    if hasSettingsApi then
        local category
        local ok
        ok, category = pcall(settingsApi.RegisterCanvasLayoutCategory, panel, panel.name, panel.name)
        if (not ok) or (not category) then
            ok, category = pcall(settingsApi.RegisterCanvasLayoutCategory, panel, panel.name)
        end
        if ok and category then
            pcall(settingsApi.RegisterAddOnCategory, category)
        elseif hasLegacyApi then
            registerLegacyCategory(panel)
        end
    else
        registerLegacyCategory(panel)
    end

    return panel
end

function SettingsService.RegisterOptions()
    if optionsRegistered then
        return optionsPanel
    end

    local ok, panel = pcall(createOptionsPanel)
    if not ok or not panel then
        return nil
    end

    optionsRegistered = true
    optionsPanel = panel
    return optionsPanel
end
