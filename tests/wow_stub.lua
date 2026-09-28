------------------------------------------------------------------------------
--  tests/wow_stub.lua
--
--  A deliberately small fake of the parts of the WoW client that the *core*
--  touches, so AutoSpellQueue.lua / _CVar.lua / _Formula.lua can be loaded and
--  driven outside the game.
--
--  Loaded by tools/run-tests.mjs before the addon files. It must run on
--  Lua 5.3 (fengari) and stay 5.1 friendly - no goto, no `//`, no bitwise ops.
--
--  Everything the tests need to steer lives in the `Stub` table, which is also
--  published as the global `AutoSpellQueueStub`:
--
--    Stub.combat            InCombatLockdown()
--    Stub.inInstance        IsInInstance()
--    Stub.homeLatency       GetNetStats() 3rd return
--    Stub.worldLatency      GetNetStats() 4th return
--    Stub.mapID             C_Map.GetBestMapForUnit("player")
--    Stub.mapInfo[id]       C_Map.GetMapInfo(id) -> { flags, parentMapID }
--    Stub.specID/specIndex  C_SpecializationInfo
--    Stub.classFile         UnitClass("player")
--    Stub.setCVarMode       "normal" | "reject-false" | "reject-nil"
--                           | "silent-noop" | "throw"
--    Stub.unreadable        GetCVar/GetCVarInfo return nil (no read-back)
--    Stub.writes            log of every C_CVar.SetCVar call the addon made
--    Stub.chat              every DEFAULT_CHAT_FRAME:AddMessage line
--    Stub.timers            pending C_Timer callbacks, driven by Stub.Advance()
--    Stub.frames            every frame handed out by CreateFrame()
--
--  Stub.Reset() resets *state* (cvars, logs, timers, flags) but keeps the
--  frames, because the addon registers its event handlers once at load time.
------------------------------------------------------------------------------

local Stub = {}
_G.AutoSpellQueueStub = Stub

------------------------------------------------------------------------------
--  Defaults
------------------------------------------------------------------------------

Stub.DEFAULT_CVAR = "SpellQueueWindow"

--- Font objects the client always provides (SharedXML/FontStyles.lua). Used to
--- model CreateFontString's `inherits` argument: an unknown name errors in the
--- client, and a missing font makes FontString:SetText fail at runtime.
local FONT_OBJECTS = {
    GameFontNormal = true, GameFontNormalSmall = true, GameFontNormalLarge = true,
    GameFontNormalHuge = true, GameFontNormalMed1 = true, GameFontNormalMed2 = true,
    GameFontNormalMed3 = true,
    GameFontHighlight = true, GameFontHighlightSmall = true, GameFontHighlightLarge = true,
    GameFontHighlightHuge = true,
    GameFontDisable = true, GameFontDisableSmall = true, GameFontDisableLarge = true,
    GameFontRed = true, GameFontRedSmall = true,
    GameFontGreen = true, GameFontGreenSmall = true,
    GameFontDarkGraySmall = true, GameFontWhite = true, GameFontBlack = true,
    GameFontBlackSmall = true, GameFontGreySmall = true,
    GameFontNormalOutline = true, GameFontHighlightOutline = true,
}
Stub.FONT_OBJECTS = FONT_OBJECTS

local function makeCVarEntry(value)
    return {
        value = tostring(value),
        defaultValue = "400",
        isStoredAccount = true,
        isStoredCharacter = false,
        isLocked = false,
        isSecure = false,
        isReadOnly = false,
    }
end

local function resetState()
    Stub.now = 1000
    Stub.combat = false
    Stub.inInstance = false
    Stub.instanceType = "none"
    Stub.locale = "enUS"
    Stub.homeLatency = 0
    Stub.worldLatency = 0
    Stub.bandwidthIn = 0
    Stub.bandwidthOut = 0

    Stub.specIndex = 1
    Stub.specID = 63
    Stub.specName = "Fire"
    Stub.classFile = "MAGE"
    Stub.className = "Mage"

    Stub.mapID = 2022
    Stub.mapInfo = {
        [2022] = { mapID = 2022, name = "Test City", parentMapID = 0, flags = 0, mapType = 1 },
    }

    Stub.cvars = { [Stub.DEFAULT_CVAR] = makeCVarEntry("150") }
    Stub.setCVarMode = "normal"
    Stub.unreadable = false
    Stub.useLegacySpecApi = false

    Stub.writes = {}
    Stub.writeCalls = 0
    Stub.chat = {}
    Stub.printed = {}
    Stub.timers = {}
    Stub.timerSerial = 0
    Stub.throwOn = {}

    -- Tooltip state is per-scenario; the widget tree and the slash command
    -- registry are built once by the addon and are deliberately kept.
    if _G.GameTooltip then
        _G.GameTooltip.lines = {}
        _G.GameTooltip.shown = false
        _G.GameTooltip.owner = nil
    end
end

--- Full reset, including the frame registry. Tests use Stub.Reset(); this one
--- exists so a future test can prove CreateFrame() itself behaves.
function Stub.ResetAll()
    resetState()
    Stub.frames = {}
end

--- State reset that keeps registered frames alive (the addon's event frame is
--- created once, when AutoSpellQueue.lua is loaded).
function Stub.Reset()
    resetState()
    Stub.frames = Stub.frames or {}
end

resetState()
Stub.frames = {}

------------------------------------------------------------------------------
--  CVar control helpers (called by the tests, never by the addon)
------------------------------------------------------------------------------

--- Changes the stored value without going through C_CVar.SetCVar, i.e. what the
--- player or another addon would do. Does not appear in Stub.writes.
function Stub.SetCVarValue(value)
    local entry = Stub.cvars[Stub.DEFAULT_CVAR]
    if not entry then
        entry = makeCVarEntry(value)
        Stub.cvars[Stub.DEFAULT_CVAR] = entry
    end
    entry.value = tostring(value)
end

function Stub.CVarValue()
    local entry = Stub.cvars[Stub.DEFAULT_CVAR]
    if not entry then return nil end
    return entry.value
end

function Stub.CVarNumber()
    local value = Stub.CVarValue()
    if value == nil then return nil end
    return tonumber(value)
end

function Stub.ClearWrites()
    Stub.writes = {}
    Stub.writeCalls = 0
end

function Stub.MakeUnreadable()
    Stub.unreadable = true
end

------------------------------------------------------------------------------
--  Widgets
------------------------------------------------------------------------------

local function newRegion(kind)
    -- A freshly created frame is SHOWN in the client (that is why addons call
    -- Hide() on helper frames, and why Options' refresh poller runs at all
    -- without ever calling Show()). Visibility is what gates OnUpdate, so this
    -- default decides whether the engine calls a ticker.
    local region = { __kind = kind, shown = true, __w = 0, __h = 0 }

    function region:SetPoint(point, a, b, c, d)
        local rel, relPoint, x, y
        if type(a) == "table" or a == nil then
            rel, relPoint, x, y = a, b, c, d
        else
            -- SetPoint(point, x, y): relativeTo defaults to the parent
            rel, relPoint, x, y = self.parent, point, a, b
        end
        if rel == nil then rel = self.parent end
        if relPoint == nil then relPoint = point end
        self.__point = {
            point = point,
            rel = rel,
            relPoint = relPoint,
            x = tonumber(x) or 0,
            y = tonumber(y) or 0,
        }
    end
    function region:ClearAllPoints() self.__point = nil end
    function region:GetPoint()
        local p = self.__point
        if not p then return nil end
        return p.point, p.rel, p.relPoint, p.x, p.y
    end
    function region:SetAllPoints()
        self.__allPoints = true
        self.__point = { point = "TOPLEFT", rel = self.parent, relPoint = "TOPLEFT", x = 0, y = 0 }
    end
    function region:SetSize(w, h) self.__w, self.__h = tonumber(w) or 0, tonumber(h) or 0 end
    function region:SetWidth(w) self.__w = tonumber(w) or 0 end
    function region:SetHeight(h) self.__h = tonumber(h) or 0 end
    function region:GetWidth()
        if self.__w and self.__w > 0 then return self.__w end
        if self.__allPoints and self.parent and self.parent.GetWidth then
            return self.parent:GetWidth()
        end
        return self.__w or 0
    end
    function region:GetHeight()
        if self.__h and self.__h > 0 then return self.__h end
        if self.__allPoints and self.parent and self.parent.GetHeight then
            return self.parent:GetHeight()
        end
        return self.__h or 0
    end
    function region:GetSize() return self:GetWidth(), self:GetHeight() end
    function region:GetLeft()
        local p = self.__point
        if not p or type(p.rel) ~= "table" or p.rel.GetLeft == nil then return self.__left or 0 end
        local width = self:GetWidth()
        local relLeft, relWidth = p.rel:GetLeft() or 0, p.rel:GetWidth() or 0
        local point = p.point
        if point == "TOPRIGHT" or point == "BOTTOMRIGHT" or point == "RIGHT" then
            return relLeft + relWidth + p.x - width
        end
        if point == "TOP" or point == "BOTTOM" or point == "CENTER" then
            if p.relPoint == "RIGHT" or p.relPoint == "TOPRIGHT" or p.relPoint == "BOTTOMRIGHT" then
                return relLeft + relWidth + p.x - width
            end
            if p.relPoint == "LEFT" or p.relPoint == "TOPLEFT" or p.relPoint == "BOTTOMLEFT" then
                return relLeft + p.x
            end
            return relLeft + (relWidth - width) / 2 + p.x
        end
        return relLeft + p.x
    end
    function region:GetTop()
        local p = self.__point
        if not p or type(p.rel) ~= "table" or p.rel.GetTop == nil then return self.__top or 0 end
        local height = self:GetHeight()
        local relTop, relHeight = p.rel:GetTop() or 0, p.rel:GetHeight() or 0
        local point = p.point
        if point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" or point == "BOTTOM" then
            return relTop + p.y + height
        end
        if point == "LEFT" or point == "RIGHT" or point == "CENTER" then
            if p.relPoint == "TOP" or p.relPoint == "TOPLEFT" or p.relPoint == "TOPRIGHT" then
                return relTop + p.y
            end
            if p.relPoint == "BOTTOM" or p.relPoint == "BOTTOMLEFT" or p.relPoint == "BOTTOMRIGHT" then
                return relTop + p.y + height
            end
            return relTop + (relHeight - height) / 2 + p.y
        end
        return relTop + p.y
    end
    function region:GetRight() return self:GetLeft() + self:GetWidth() end
    function region:GetBottom() return self:GetTop() - self:GetHeight() end
    function region:GetCenter()
        return self:GetLeft() + self:GetWidth() / 2, self:GetTop() - self:GetHeight() / 2
    end
    -- The client refuses to render text on a FontString that has no font yet:
    --   FontString:SetText(): Font not set
    -- That error once aborted the whole UI setup in the live client while the
    -- stub happily accepted it. Model the precondition so the suite catches it.
    function region:SetText(text)
        if self.__kind == "FontString" and not (self.font or self.fontObject) then
            error("FontString:SetText(): Font not set", 2)
        end
        self.text = text
    end
    function region:GetText() return self.text end
    function region:SetFormattedText(fmt, ...)
        if self.__kind == "FontString" and not (self.font or self.fontObject) then
            error("FontString:SetText(): Font not set", 2)
        end
        self.text = string.format(fmt, ...)
    end
    function region:GetStringWidth()
        local text = type(self.text) == "string" and self.text or ""
        return #text * 7
    end
    function region:GetStringHeight() return 14 end
    function region:SetWordWrap() end
    function region:SetNonSpaceWrap() end
    function region:SetFont(font) self.font = font end
    function region:GetFont() return self.font end
    function region:SetFontObject(font) self.fontObject = font end
    function region:SetJustifyH() end
    function region:SetJustifyV() end
    function region:SetTextColor() end
    function region:SetVertexColor() end
    function region:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function region:SetTexture() end
    function region:SetAlpha() end
    function region:GetAlpha() return 1 end
    function region:SetScale() end
    function region:SetParent(parent) self.parent = parent end
    function region:GetParent() return self.parent end
    function region:SetDrawLayer() end
    function region:SetShown(shown)
        if shown then self:Show() else self:Hide() end
    end
    function region:Show()
        if self.shown == true then return end
        self.shown = true
        local handler = self.__scripts and self.__scripts.OnShow
        if handler then handler(self) end
    end
    function region:Hide()
        if self.shown == false then return end
        self.shown = false
        local handler = self.__scripts and self.__scripts.OnHide
        if handler then handler(self) end
    end
    function region:IsShown() return self.shown == true end
    function region:IsVisible()
        local node = self
        while node do
            if node.shown ~= true then return false end
            node = node.parent
        end
        return true
    end
    function region:SetFrameStrata() end
    function region:SetFrameLevel() end

    return region
end

local function newFrame(frameType, name, parent)
    local frame = newRegion(frameType or "Frame")
    frame.name = name
    frame.parent = parent
    frame.__events = {}
    frame.__scripts = {}

    function frame:RegisterEvent(event) self.__events[event] = true end
    function frame:UnregisterEvent(event) self.__events[event] = nil end
    function frame:UnregisterAllEvents() self.__events = {} end
    function frame:IsEventRegistered(event) return self.__events[event] and true or false end
    function frame:SetScript(handler, fn) self.__scripts[handler] = fn end
    function frame:GetScript(handler) return self.__scripts[handler] end
    function frame:HookScript(handler, fn)
        local previous = self.__scripts[handler]
        self.__scripts[handler] = function(...)
            if previous then previous(...) end
            fn(...)
        end
    end
    function frame:CreateTexture(name)
        local texture = newRegion("Texture")
        texture.name = name
        texture.parent = self
        return Stub.RegisterFrame(texture)
    end
    function frame:CreateFontString(name, layer, inherits)
        local text = newRegion("FontString")
        text.name = name
        text.parent = self
        -- `inherits` is a font object name in the client; without it the client
        -- leaves the string fontless and SetText fails (see region:SetText).
        if inherits ~= nil then
            if FONT_OBJECTS[inherits] == nil then
                error("CreateFontString: Unknown font object '" .. tostring(inherits) .. "'", 2)
            end
            text.fontObject = inherits
        end
        return Stub.RegisterFrame(text)
    end
    function frame:SetMovable() end
    function frame:RegisterForDrag() end
    function frame:RegisterForClicks() end
    function frame:SetClampedToScreen() end
    function frame:SetResizable() end
    function frame:SetMinResize() end
    function frame:SetMaxResize() end
    function frame:EnableMouse() end
    function frame:EnableMouseWheel() end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor() end
    function frame:SetStatusBarTexture() end
    function frame:SetStatusBarColor() end
    function frame:SetMinMaxValues(min, max) self.minValue, self.maxValue = min, max end
    function frame:SetValue(v) self.value = v end
    function frame:GetValue() return self.value end
    function frame:SetOrientation() end
    function frame:SetRotatesTexture() end
    function frame:SetHitRectInsets() end
    function frame:StartMoving() self.moving = true end
    function frame:StopMovingOrSizing() self.moving = false end
    function frame:SetScrollChild(child) self.__scrollChild = child; child.parent = self end
    function frame:GetScrollChild() return self.__scrollChild end
    function frame:SetVerticalScroll() end
    function frame:UpdateScrollChildRect() end

    return frame
end

--- Registers a frame in the registry so Stub.FireEvent() can reach it.
function Stub.RegisterFrame(frame)
    Stub.frames = Stub.frames or {}
    frame.__order = #Stub.frames + 1
    Stub.frames[#Stub.frames + 1] = frame
    return frame
end

function Stub.FindFrame(name)
    if name == nil then return nil end
    for _, frame in ipairs(Stub.frames or {}) do
        -- __name is the name passed to CreateFrame. `name` is a normal field the
        -- addon is allowed to overwrite (the Settings API reads frame.name as
        -- the panel title), so it is only a fallback here.
        if frame.__name == name or (frame.__name == nil and frame.name == name) then
            return frame
        end
    end
    return nil
end

--- Every widget ever created, in creation order (index == __order - 1).
function Stub.Widgets() return Stub.frames or {} end

function Stub.WidgetIndex(widget) return widget and widget.__order or nil end

function Stub.WidgetsSince(index)
    local out = {}
    for _, widget in ipairs(Stub.frames or {}) do
        if widget.__order > (index or 0) then out[#out + 1] = widget end
    end
    return out
end

function Stub.FindWidgets(predicate)
    local out = {}
    for _, widget in ipairs(Stub.frames or {}) do
        if predicate(widget) then out[#out + 1] = widget end
    end
    return out
end

function Stub.FindWidget(predicate)
    for _, widget in ipairs(Stub.frames or {}) do
        if predicate(widget) then return widget end
    end
    return nil
end

--- Runs every OnUpdate script, but only for frames the client would actually
--- update: a frame whose own `shown` flag - or any ancestor's - is false gets no
--- OnUpdate. That is the engine rule the "hidden frames are not polled" design
--- depends on.
function Stub.FireUpdate(elapsed)
    elapsed = tonumber(elapsed) or 0
    local called = 0
    for _, widget in ipairs(Stub.frames or {}) do
        local handler = widget.__scripts and widget.__scripts.OnUpdate
        if handler and widget:IsVisible() then
            called = called + 1
            handler(widget, elapsed)
        end
    end
    return called
end

--- Number of frames that would receive OnUpdate right now.
function Stub.VisibleOnUpdateCount()
    local count = 0
    for _, widget in ipairs(Stub.frames or {}) do
        if widget.__scripts and widget.__scripts.OnUpdate and widget:IsVisible() then
            count = count + 1
        end
    end
    return count
end

_G.CreateFrame = function(frameType, name, parent)
    local frame = newFrame(frameType, name, parent)
    frame.__name = name
    if name then _G[name] = frame end
    return Stub.RegisterFrame(frame)
end

Stub.screenWidth = 1920
Stub.screenHeight = 1080

_G.UIParent = Stub.RegisterFrame(newFrame("Frame", "UIParent"))
_G.UIParent:SetSize(Stub.screenWidth, Stub.screenHeight)
_G.UIParent:Show()
-- The screen is the root of the anchor hierarchy: no parent, fixed geometry.
_G.UIParent.GetLeft = function() return 0 end
_G.UIParent.GetTop = function() return Stub.screenHeight end
_G.UIParent.GetWidth = function() return Stub.screenWidth end
_G.UIParent.GetHeight = function() return Stub.screenHeight end

_G.WorldFrame = Stub.RegisterFrame(newFrame("Frame", "WorldFrame"))
_G.WorldFrame:Show()
_G.GameFontNormal = "Fonts\\FRIZQT__.TTF"
_G.GameFontNormalSmall = "Fonts\\FRIZQT__.TTF"
_G.GameFontNormalLarge = "Fonts\\FRIZQT__.TTF"
_G.GameFontHighlight = "Fonts\\FRIZQT__.TTF"
_G.GameFontHighlightSmall = "Fonts\\FRIZQT__.TTF"
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.NORMAL_FONT_COLOR = { r = 0, g = 1, b = 0 }
_G.HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
_G.RED_FONT_COLOR = { r = 1, g = 0, b = 0 }

--- Slash command registry. Like the frame registry this is never reset: the
--- addon registers its commands once, when it initialises.
_G.SlashCmdList = _G.SlashCmdList or {}
_G.UISpecialFrames = _G.UISpecialFrames or {}

------------------------------------------------------------------------------
--  GameTooltip
------------------------------------------------------------------------------

_G.GameTooltip = {
    lines = {},
    shown = false,
    owner = nil,
}

function _G.GameTooltip:SetOwner(owner) self.owner = owner end
function _G.GameTooltip:ClearLines() self.lines = {} end
function _G.GameTooltip:AddLine(text) self.lines[#self.lines + 1] = tostring(text) end
function _G.GameTooltip:AddDoubleLine(left, right)
    self.lines[#self.lines + 1] = tostring(left) .. "\t" .. tostring(right)
end
function _G.GameTooltip:Show() self.shown = true end
function _G.GameTooltip:Hide() self.shown = false end
function _G.GameTooltip:IsShown() return self.shown end

--- Test helper: does any tooltip line contain this substring?
function Stub.TooltipContains(needle)
    for _, line in ipairs(_G.GameTooltip.lines) do
        if string.find(line, needle, 1, true) then return true end
    end
    return false
end

------------------------------------------------------------------------------
--  Settings API (modern client)
--
--  Installed by default, because 12.x always has it - and because the addon
--  initialises on the first ADDON_LOADED / PLAYER_LOGIN it sees, which may
--  happen in any spec. A spec that wants the "no Settings API" fallback removes
--  it for the duration of one test and puts it back.
------------------------------------------------------------------------------

--- Installs a fake Settings API and returns the call recorder.
function Stub.InstallSettings()
    local calls = { openToCategory = {}, registered = {} }
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(panel, name, subName)
            calls.registerCanvas = { panel = panel, name = name, subName = subName }
            local category = { ID = "AutoSpellQueue", name = name }
            function category:GetID() return self.ID end
            calls.registered[#calls.registered + 1] = category
            return category
        end,
        RegisterAddOnCategory = function(category)
            calls.registerAddOn = category
            return true
        end,
        OpenToCategory = function(id)
            calls.openToCategory[#calls.openToCategory + 1] = id
            return true
        end,
    }
    Stub.settingsCalls = calls
    return calls
end

function Stub.RemoveSettings()
    _G.Settings = nil
end

Stub.settingsCalls = Stub.InstallSettings()

------------------------------------------------------------------------------
--  Events
------------------------------------------------------------------------------

--- Fires a game event at every frame that registered for it.
--  Returns the number of handlers invoked.
function Stub.FireEvent(event, ...)
    local invoked = 0
    for _, frame in ipairs(Stub.frames or {}) do
        if frame.__events and frame.__events[event] then
            local handler = frame.__scripts and frame.__scripts.OnEvent
            if handler then
                invoked = invoked + 1
                handler(frame, event, ...)
            end
        end
    end
    return invoked
end

------------------------------------------------------------------------------
--  Timers
------------------------------------------------------------------------------

local function pushTimer(seconds, callback, interval)
    Stub.timerSerial = Stub.timerSerial + 1
    local timer = {
        id = Stub.timerSerial,
        due = Stub.now + (tonumber(seconds) or 0),
        interval = interval,
        callback = callback,
        cancelled = false,
    }
    Stub.timers[#Stub.timers + 1] = timer
    return timer
end

--- Runs every timer that comes due within `seconds`, in chronological order,
--- including timers scheduled by the callbacks themselves (warm-up chain).
function Stub.Advance(seconds)
    local target = Stub.now + (tonumber(seconds) or 0)
    local guard = 0
    while true do
        guard = guard + 1
        if guard > 5000 then
            error("Stub.Advance: timer cascade did not settle (possible loop)")
        end
        local nextTimer, nextIndex
        for index, timer in ipairs(Stub.timers) do
            if not timer.cancelled and timer.due <= target then
                if not nextTimer or timer.due < nextTimer.due then
                    nextTimer, nextIndex = timer, index
                end
            end
        end
        if not nextTimer then break end
        Stub.now = nextTimer.due
        if nextTimer.interval then
            nextTimer.due = nextTimer.due + nextTimer.interval
        else
            table.remove(Stub.timers, nextIndex)
        end
        nextTimer.callback()
    end
    Stub.now = target
end

function Stub.PendingTimers()
    local count = 0
    for _, timer in ipairs(Stub.timers) do
        if not timer.cancelled then count = count + 1 end
    end
    return count
end

_G.C_Timer = {
    After = function(seconds, callback) return pushTimer(seconds, callback, nil) end,
    NewTimer = function(seconds, callback) return pushTimer(seconds, callback, nil) end,
    NewTicker = function(seconds, callback)
        local timer = pushTimer(seconds, callback, tonumber(seconds) or 1)
        timer.Cancel = function(self) self.cancelled = true end
        return timer
    end,
}

------------------------------------------------------------------------------
--  Game state readers
------------------------------------------------------------------------------

_G.GetLocale = function() return Stub.locale end
_G.GetTime = function() return Stub.now end
_G.time = function() return math.floor(Stub.now) end
_G.InCombatLockdown = function() return Stub.combat and true or false end
_G.UnitClass = function() return Stub.className, Stub.classFile end
_G.IsInInstance = function() return Stub.inInstance and true or false, Stub.instanceType end
_G.GetNetStats = function()
    return Stub.bandwidthIn, Stub.bandwidthOut, Stub.homeLatency, Stub.worldLatency
end

_G.C_Map = {
    GetBestMapForUnit = function() return Stub.mapID end,
    GetMapInfo = function(mapID) return Stub.mapInfo[mapID] end,
}

_G.C_SpecializationInfo = {
    GetSpecialization = function() return Stub.specIndex end,
    GetSpecializationInfo = function(index)
        return Stub.specID, Stub.specName, "", 0, "DAMAGER", 0
    end,
}

-- Legacy (pre-C_ namespaces) fallbacks, used when a test nils out the C_ table.
_G.GetSpecialization = function() return Stub.specIndex end
_G.GetSpecializationInfo = function(index)
    return Stub.specID, Stub.specName, "", 0, "DAMAGER", 0
end

------------------------------------------------------------------------------
--  C_CVar
------------------------------------------------------------------------------

local function cvarEntry(name)
    return Stub.cvars[name]
end

_G.C_CVar = {
    GetCVarInfo = function(name)
        if Stub.throwOn.getCVarInfo then error("GetCVarInfo exploded") end
        if Stub.unreadable then return nil end
        local entry = cvarEntry(name)
        if not entry then return nil end
        return entry.value, entry.defaultValue, entry.isStoredAccount,
            entry.isStoredCharacter, entry.isLocked, entry.isSecure, entry.isReadOnly
    end,

    GetCVar = function(name)
        if Stub.throwOn.getCVar then error("GetCVar exploded") end
        if Stub.unreadable then return nil end
        local entry = cvarEntry(name)
        if not entry then return nil end
        return entry.value
    end,

    SetCVar = function(name, value)
        if Stub.throwOn.setCVar then error("SetCVar exploded") end
        Stub.writeCalls = Stub.writeCalls + 1
        Stub.writes[#Stub.writes + 1] = {
            name = name,
            value = value,
            at = Stub.now,
            mode = Stub.setCVarMode,
        }
        local mode = Stub.setCVarMode
        local entry = cvarEntry(name)
        if mode == "throw" then error("SetCVar exploded") end
        if mode == "reject-false" then return false end
        if mode == "reject-nil" then return nil end
        if mode == "silent-noop" then return true end -- API claims success, value unchanged
        if entry then entry.value = tostring(value) end
        return true
    end,
}

-- Same shape through the legacy globals.
_G.GetCVar = function(name) return _G.C_CVar.GetCVar(name) end
_G.SetCVar = function(name, value) return _G.C_CVar.SetCVar(name, value) end

------------------------------------------------------------------------------
--  Chat / print
------------------------------------------------------------------------------

_G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(self, message)
        Stub.chat[#Stub.chat + 1] = tostring(message)
    end,
}

-- The addon may fall back to print() when DEFAULT_CHAT_FRAME is missing, so we
-- capture it. The real printer is kept in Stub.realPrint: the test runner uses
-- it to write its report (overriding print must not swallow the report).
Stub.realPrint = print

_G.print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(index, ...)))
    end
    Stub.printed[#Stub.printed + 1] = table.concat(parts, "\t")
end

--- Convenience for the specs: did any chat line contain this substring?
function Stub.ChatContains(needle)
    for _, line in ipairs(Stub.chat) do
        if string.find(line, needle, 1, true) then return true end
    end
    return false
end

return Stub
