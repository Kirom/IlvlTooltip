local WowMock = {}

local function newLine(text, r, g, b)
    local line = {
        _text = text,
        _r = r,
        _g = g,
        _b = b,
    }

    function line:GetText()
        return self._text
    end

    function line:SetText(value)
        self._text = value
    end

    function line:SetTextColor(red, green, blue)
        self._r = red
        self._g = green
        self._b = blue
    end

    return line
end

local function createTooltip(name)
    local tooltip = {
        _name = name,
        _shown = true,
        _unit = nil,
        _lines = {},
        _hooks = {},
        _hasScript = { OnTooltipSetUnit = true },
    }

    function tooltip:GetName()
        return self._name
    end

    function tooltip:NumLines()
        return #self._lines
    end

    function tooltip:AddLine(text, r, g, b)
        local line = newLine(text, r, g, b)
        self._lines[#self._lines + 1] = line
        _G[self._name .. "TextLeft" .. #self._lines] = line
    end

    function tooltip:IsShown()
        return self._shown
    end

    function tooltip:Show()
        self._shown = true
    end

    function tooltip:Hide()
        self._shown = false
    end

    function tooltip:GetUnit()
        return nil, self._unit
    end

    function tooltip:SetUnit(unit)
        self._unit = unit
        self._shown = true
    end

    function tooltip:HookScript(script, callback)
        if not self._hooks[script] then
            self._hooks[script] = {}
        end
        self._hooks[script][#self._hooks[script] + 1] = callback
    end

    function tooltip:HasScript(script)
        return self._hasScript[script] == true
    end

    function tooltip:FireScript(script, ...)
        local callbacks = self._hooks[script]
        if not callbacks then
            return
        end

        for i = 1, #callbacks do
            callbacks[i](self, ...)
        end
    end

    function tooltip:ClearLines()
        for i = 1, #self._lines do
            _G[self._name .. "TextLeft" .. i] = nil
        end
        self._lines = {}
    end

    function tooltip:GetLineText(index)
        local line = self._lines[index]
        return line and line:GetText() or nil
    end

    return tooltip
end

function WowMock.new()
    local env = {
        now = 0,
        units = {},
        inventory = {},
        itemLevels = {},
        inspectRequests = {},
        clearInspectCalls = 0,
        timerQueue = {},
        frames = {},
        tooltipPostCalls = {},
        worldMouseFocus = false,
        playerIlvl = 0,
        inspectItemLevelFn = function()
            return nil, nil
        end,
    }

    function env:_scheduleTimer(delay, callback, cancellable)
        local timer = {
            due = self.now + (delay or 0),
            callback = callback,
            cancelled = false,
        }

        if cancellable then
            function timer:Cancel()
                self.cancelled = true
            end
        end

        self.timerQueue[#self.timerQueue + 1] = timer
        return cancellable and timer or nil
    end

    function env:advance(delta)
        self.now = self.now + (delta or 0)

        local didRun = true
        while didRun do
            didRun = false
            for i = #self.timerQueue, 1, -1 do
                local timer = self.timerQueue[i]
                if timer.cancelled then
                    table.remove(self.timerQueue, i)
                elseif timer.due <= self.now then
                    table.remove(self.timerQueue, i)
                    timer.callback()
                    didRun = true
                end
            end
        end
    end

    function env:setUnit(token, data)
        self.units[token] = {
            guid = data.guid,
            isPlayer = data.isPlayer == true,
            canInspect = data.canInspect == true,
            inRange = data.inRange == true,
            exists = data.exists ~= false,
        }
    end

    function env:setInventory(token, slots)
        self.inventory[token] = slots or {}
    end

    function env:setItemLevel(link, ilvl)
        self.itemLevels[link] = ilvl
    end

    function env:setInspectItemLevelFn(fn)
        self.inspectItemLevelFn = fn
    end

    function env:newTooltip(name)
        return createTooltip(name)
    end

    function env:fireEvent(event, ...)
        for i = 1, #self.frames do
            local frame = self.frames[i]
            frame:FireEvent(event, ...)
        end
    end

    function env:fireUnitTooltip(tooltip, data)
        local unitType = _G.Enum and _G.Enum.TooltipDataType and _G.Enum.TooltipDataType.Unit
        if not unitType then
            return
        end
        local callbacks = self.tooltipPostCalls[unitType] or {}
        for i = 1, #callbacks do
            callbacks[i](tooltip, data)
        end
    end

    function env:installGlobals()
        _G.GetTime = function()
            return env.now
        end

        _G.UnitExists = function(unit)
            local data = env.units[unit]
            return data ~= nil and data.exists ~= false
        end

        _G.UnitGUID = function(unit)
            local data = env.units[unit]
            return data and data.guid or nil
        end

        _G.UnitIsPlayer = function(unit)
            local data = env.units[unit]
            return data and data.isPlayer or false
        end

        _G.UnitIsUnit = function(a, b)
            local ag = _G.UnitGUID(a)
            local bg = _G.UnitGUID(b)
            return ag ~= nil and ag == bg
        end

        _G.CanInspect = function(unit)
            local data = env.units[unit]
            return data and data.canInspect or false
        end

        _G.CheckInteractDistance = function(unit)
            local data = env.units[unit]
            return data and data.inRange or false
        end

        _G.GetAverageItemLevel = function()
            return 0, env.playerIlvl
        end

        _G.GetInventoryItemLink = function(unit, slot)
            local slots = env.inventory[unit]
            return slots and slots[slot] or nil
        end

        _G.GetDetailedItemLevelInfo = function(link)
            return env.itemLevels[link]
        end

        _G.UnitTokenFromGUID = function(guid)
            for token, data in pairs(env.units) do
                if data.exists ~= false and data.guid == guid then
                    return token
                end
            end
            return nil
        end

        _G.NotifyInspect = function(unit)
            env.inspectRequests[#env.inspectRequests + 1] = unit
        end

        _G.ClearInspectPlayer = function()
            env.clearInspectCalls = env.clearInspectCalls + 1
        end

        _G.C_Timer = {
            NewTimer = function(delay, callback)
                return env:_scheduleTimer(delay, callback, true)
            end,
            After = function(delay, callback)
                env:_scheduleTimer(delay, callback, false)
            end,
        }

        _G.C_PaperDollInfo = {
            GetInspectItemLevel = function(unit)
                return env.inspectItemLevelFn(unit)
            end,
        }

        _G.WorldFrame = {
            IsMouseMotionFocus = function()
                return env.worldMouseFocus
            end,
        }

        _G.Enum = {
            TooltipDataType = {
                Unit = 2,
            },
        }

        _G.TooltipDataProcessor = {
            AddTooltipPostCall = function(dataType, callback)
                if not env.tooltipPostCalls[dataType] then
                    env.tooltipPostCalls[dataType] = {}
                end
                env.tooltipPostCalls[dataType][#env.tooltipPostCalls[dataType] + 1] = callback
            end,
        }

        _G.CreateFrame = function()
            local frame = {
                _events = {},
                _scripts = {},
            }

            function frame:RegisterEvent(event)
                self._events[event] = true
            end

            function frame:SetScript(scriptName, callback)
                self._scripts[scriptName] = callback
            end

            function frame:FireEvent(event, ...)
                if self._events[event] and self._scripts.OnEvent then
                    self._scripts.OnEvent(self, event, ...)
                end
            end

            env.frames[#env.frames + 1] = frame
            return frame
        end

        env.gameTooltip = createTooltip("GameTooltip")
        _G.GameTooltip = env.gameTooltip
    end

    return env
end

return WowMock
