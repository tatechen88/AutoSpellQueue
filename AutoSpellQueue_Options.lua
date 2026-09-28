-------------------------------------------------------------------------------
--  AutoSpellQueue_Options.lua
--
--  Blizzard settings panel, floating status bar and slash commands.
--
--  Dependencies are limited to the frozen contract in docs/ARCHITECTURE.md:
--    ns.Core    - GetConfig / SetConfig / SetEnabled / ResetSettings / Refresh
--                 GetStatus / Output / L / REASON_KEY / STATE / NAME / Now
--    ns.Formula - Describe (pure) for the formula line
--    ns.CVar    - read-only, only for CVar.NAME in the event filter
--  The UI never writes the CVar itself: every change goes through the core.
--
--  Rules this file follows (they come from the review findings):
--    * Out of the box the panel is minimal: master switch, status card and one
--      "advanced" fold. Nothing has to be configured for the addon to work.
--    * The status card tells the truth. Every state the core can report has its
--      own text, and a failed write shows the localised reason instead of a
--      plausible looking number.
--    * Wall clock values (current / target / latency) are labelled as the
--      sample of the last computation, never as live readings.
--    * The widget tree is built once and only refreshed: it is never rebuilt.
--    * Hidden frames are not polled. The refresh ticker is a child of the panel
--      and of the status bar, so the engine stops calling it while they are
--      hidden.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Core = ns and ns.Core
if not Core then return end

local Formula = ns.Formula
local CVar = ns.CVar

local Options = {}
ns.Options = Options

local L = function(key) return Core.L(key) end

--- Renders a localised format string: Format("UNIT_MS", 245).
--  Every player facing string comes from L(); nothing is hardcoded here. If a
--  locale entry were missing a placeholder, the raw localised text is shown
--  instead of raising an error inside a UI updater.
local function Format(key, ...)
    local pattern = L(key)
    if type(pattern) ~= "string" then return tostring(pattern) end
    local ok, text = pcall(string.format, pattern, ...)
    if ok then return text end
    return pattern
end

local function Say(text)
    if Core.Output then Core.Output(text) end
end

-------------------------------------------------------------------------------
--  Visuals
-------------------------------------------------------------------------------
local ACCENT = { 12 / 255, 210 / 255, 157 / 255 }

local STATE_COLOR = {
    applied     = { 0.05, 0.83, 0.60 },
    pending     = { 1.00, 0.72, 0.20 },
    error       = { 0.95, 0.35, 0.35 },
    unavailable = { 0.90, 0.50, 0.35 },
    disabled    = { 0.65, 0.65, 0.65 },
    idle        = { 0.55, 0.75, 1.00 },
}

local PANEL_WIDTH = 640
local PANEL_PAD = 16
local INNER_WIDTH = PANEL_WIDTH - PANEL_PAD * 2
local ROW_HEIGHT = 30
local ROW_GAP = 2
local POLL_INTERVAL = 0.5

-------------------------------------------------------------------------------
--  Small helpers
-------------------------------------------------------------------------------
local function NumText(value)
    local n = tonumber(value)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
    return math.floor(n + 0.5)
end

local function Clamp(value, low, high)
    local n = tonumber(value) or low
    if n < low then return low end
    if n > high then return high end
    return n
end

local function MsText(value)
    local n = NumText(value)
    if n == nil then return L("VALUE_UNAVAILABLE") end
    return Format("UNIT_MS", n)
end

local function RoleText(role)
    if role == "melee" then return L("ROLE_MELEE") end
    if role == "ranged" then return L("ROLE_RANGED") end
    return L("ROLE_UNKNOWN")
end

local function ContextText(context)
    if context == "city" then return L("CONTEXT_CITY") end
    if context == "instance" then return L("CONTEXT_INSTANCE") end
    if context == "world" then return L("CONTEXT_WORLD") end
    return L("ROLE_UNKNOWN")
end

local function SpecText(status)
    local name = status and status.specName
    if type(name) == "string" and name ~= "" then return name end
    local id = NumText(status and status.specID)
    if id and id > 0 then return ("#%d"):format(id) end
    return L("ROLE_UNKNOWN")
end

--- The state that should be shown. A failed write always wins over "disabled",
--- because that failure is the thing the player has to know about.
local function ResolveState(status)
    local state = status.state or "idle"
    if state ~= "error" and state ~= "unavailable" and not status.enabled then
        state = "disabled"
    end
    return state
end

local function StateLabel(state)
    return L("STATE_" .. string.upper(state))
end

local function ReasonText(status)
    local key = status.stateReasonKey or status.lastError
    if type(key) ~= "string" or key == "" then return L("VALUE_UNAVAILABLE") end
    return L(key)
end

--- The value the card and the status bar present as "current".
--  Core.GetStatus().live is a direct read of the CVar - never a cached
--  snapshot - so it is always the first choice.
--  The fallback covers a core that does not expose `live` yet and keeps the
--  panel honest anyway: a refresh cycle reads the CVar before it writes, so
--  straight after a verified write the snapshot still holds the pre-write
--  value, and lastApplied (verified by reading the CVar back) is the newer
--  truth. When no write happened - already at target, or inside the hysteresis
--  - the snapshot reading is the fresh one and is used as-is.
--  Everything unreadable stays nil so callers can say "unavailable" instead of
--  inventing a number.
local function EffectiveCurrent(status)
    if status.live ~= nil then
        return NumText(status.live)
    end
    local current = NumText(status.current)
    if status.state ~= "applied" or not status.owned then return current end
    local applied = NumText(status.lastApplied)
    if applied == nil then return current end
    local target = NumText(status.target)
    if current == nil or target == nil then return applied end
    if current == target then return current end
    local cfg = Core.GetConfig()
    if math.abs(target - current) < (NumText(cfg and cfg.hysteresis) or 0) then
        return current
    end
    return applied
end

--- "These numbers are a sample of the last computation" - with its age when the
--- core reports when the snapshot was taken.
local function SampledText(status)
    local text = Format("HINT_SAMPLED", NumText(status.refreshSeconds) or 0)
    local at = NumText(status.snapshotAt)
    if at then
        local seconds = math.max(0, math.floor(Core.Now() - at))
        text = text .. " " .. Format("HINT_SNAPSHOT_AGE", seconds)
    end
    return text
end

local function CvarText(info)
    if type(info) ~= "table" then return L("VALUE_UNAVAILABLE") end
    if not info.known then return L("CVAR_MISSING") end
    local parts = { L("CVAR_NORMAL") }
    if info.isReadOnly then parts[#parts + 1] = L("CVAR_READONLY") end
    if info.isLocked then parts[#parts + 1] = L("CVAR_LOCKED") end
    if info.isSecure then parts[#parts + 1] = L("CVAR_SECURE") end
    if info.isStoredAccount then parts[#parts + 1] = L("CVAR_ACCOUNT") end
    if info.isStoredCharacter then parts[#parts + 1] = L("CVAR_CHARACTER") end
    return table.concat(parts, " · ")
end

local function FormulaText(cfg, status)
    if not (Formula and Formula.Describe) then return L("FORMULA_UNKNOWN") end
    local target = NumText(status.target)
    if target == nil then return L("FORMULA_UNKNOWN") end
    local kind, base, latency, margin = Formula.Describe(
        cfg, status.specID, status.classFile, status.home, status.world, status.context)
    local b = NumText(base) or 0
    local lat = NumText(latency) or 0
    local mar = NumText(margin) or 0
    if kind == "city" then
        return Format("FORMULA_CITY", target, b)
    elseif kind == "adaptive" then
        return Format("FORMULA_ADAPTIVE", target, b, lat, mar)
    end
    return Format("FORMULA_BASE", target, b)
end

-------------------------------------------------------------------------------
--  Widget helpers
-------------------------------------------------------------------------------
local function SetColor(tex, r, g, b, a)
    tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
end

local function AddBorder(frame, r, g, b, a)
    local top = frame:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(1)
    SetColor(top, r, g, b, a)

    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(1)
    SetColor(bottom, r, g, b, a)

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(1)
    SetColor(left, r, g, b, a)

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(1)
    SetColor(right, r, g, b, a)
end

local function NewText(parent, fontObject)
    return parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
end

--- Tooltip helper. Title/body may be strings or functions (for live text).
local function AttachTooltip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        local titleText = type(title) == "function" and title() or title
        local bodyText = type(body) == "function" and body() or body
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if titleText then GameTooltip:AddLine(titleText, 1, 1, 1, true) end
        if bodyText then GameTooltip:AddLine(bodyText, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function NewButton(parent, width, height, text)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetColor(bg, 0.10, 0.13, 0.16, 0.95)
    AddBorder(button, 1, 1, 1, 0.16)
    local label = NewText(button, "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(text or "")
    button._bg = bg
    button._text = label
    button:SetScript("OnEnter", function(self)
        SetColor(self._bg, ACCENT[1], ACCENT[2], ACCENT[3], 0.28)
    end)
    button:SetScript("OnLeave", function(self)
        SetColor(self._bg, 0.10, 0.13, 0.16, 0.95)
    end)
    return button
end

local function SwitchSet(switch, value)
    switch._knob:ClearAllPoints()
    if value then
        SetColor(switch._track, ACCENT[1], ACCENT[2], ACCENT[3], 0.95)
        switch._knob:SetPoint("RIGHT", switch, "RIGHT", -3, 0)
    else
        SetColor(switch._track, 0.16, 0.18, 0.20, 0.90)
        switch._knob:SetPoint("LEFT", switch, "LEFT", 3, 0)
    end
end

local function NewSwitch(parent)
    local switch = CreateFrame("Button", nil, parent)
    switch:SetSize(46, 22)
    switch:RegisterForClicks("LeftButtonUp")
    local track = switch:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    AddBorder(switch, 1, 1, 1, 0.12)
    local knob = switch:CreateTexture(nil, "OVERLAY")
    knob:SetSize(16, 16)
    SetColor(knob, 1, 1, 1, 0.95)
    switch._track = track
    switch._knob = knob
    return switch
end

-------------------------------------------------------------------------------
--  Refresh plumbing
--
--  updaters is a flat list built together with the tree. Refreshing walks that
--  list; it never walks the frame tree and it never creates a widget.
-------------------------------------------------------------------------------
local updaters = {}
local updaterErrors = {}
local built = false

local refreshCfg, refreshStatus

local function PullState()
    refreshCfg = Core.GetConfig()
    refreshStatus = Core.GetStatus()
end

local function Cfg()
    if not refreshCfg then refreshCfg = Core.GetConfig() end
    return refreshCfg
end

local function Status()
    if not refreshStatus then refreshStatus = Core.GetStatus() end
    return refreshStatus
end

local function AddUpdater(fn)
    updaters[#updaters + 1] = fn
end

local function RefreshUI()
    if not built then return end
    PullState()
    for index = 1, #updaters do
        local ok, err = pcall(updaters[index])
        if not ok and not updaterErrors[index] then
            -- Report each broken updater once, but never spam the chat.
            updaterErrors[index] = true
            if type(print) == "function" then
                print("AutoSpellQueue options: updater " .. index .. " failed: " .. tostring(err))
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Row / section builders
-------------------------------------------------------------------------------
local function AddRow(parent, y, height)
    height = height or ROW_HEIGHT
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    row:SetHeight(height)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetColor(bg, 1, 1, 1, 0.04)
    return row, y - height - ROW_GAP
end

local function AddRowLabel(row, key)
    local label = NewText(row, "GameFontNormal")
    label:SetPoint("LEFT", 12, 0)
    label:SetText(L(key))
    label:SetJustifyH("LEFT")
    return label
end

local function AddRowHint(row, key)
    local hint = NewText(row, "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 12, -16)
    hint:SetWidth(INNER_WIDTH - 40)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetTextColor(1, 1, 1, 0.45)
    hint:SetText(L(key))
    return hint
end

local function AddSectionHeader(parent, y, key)
    local header = NewText(parent, "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, y)
    header:SetText("|cff0cd29f" .. L(key) .. "|r")
    header:SetJustifyH("LEFT")
    return y - 22
end

-------------------------------------------------------------------------------
--  Widgets: toggle / stepper / cycle
-------------------------------------------------------------------------------

--- Toggle row: right aligned switch plus a localised on/off word.
local function AddToggle(parent, y, labelKey, get, set, hintKey)
    local height = hintKey and 46 or ROW_HEIGHT
    local row, nextY = AddRow(parent, y, height)
    AddRowLabel(row, labelKey)
    if hintKey then AddRowHint(row, hintKey) end

    local stateText = NewText(row, "GameFontNormalSmall")
    stateText:SetPoint("RIGHT", -68, 0)
    local switch = NewSwitch(row)
    switch:SetPoint("RIGHT", -12, 0)

    switch:SetScript("OnClick", function()
        set(not get())
        RefreshUI()
    end)

    AddUpdater(function()
        local on = get() and true or false
        SwitchSet(switch, on)
        stateText:SetText(on and L("VALUE_ON") or L("VALUE_OFF"))
        stateText:SetTextColor(1, 1, 1, on and 0.90 or 0.50)
    end)

    return row, nextY
end

--- Numeric row: [-] value [+]. The core re-validates and clamps afterwards, so
--- the display always shows the sanitised value.
local function AddStepper(parent, y, labelKey, low, high, step, get, set, unitKey)
    local row, nextY = AddRow(parent, y)
    AddRowLabel(row, labelKey)

    local plus = NewButton(row, 26, 22, L("VALUE_PLUS"))
    plus:SetPoint("RIGHT", -12, 0)

    local value = NewText(row, "GameFontHighlight")
    value:SetPoint("RIGHT", plus, "LEFT", -8, 0)
    value:SetWidth(84)
    value:SetJustifyH("RIGHT")
    value:SetWordWrap(false)

    local minus = NewButton(row, 26, 22, L("VALUE_MINUS"))
    minus:SetPoint("RIGHT", value, "LEFT", -8, 0)

    local function Update()
        local n = NumText(get()) or low
        if unitKey then
            value:SetText(Format(unitKey, n))
        else
            value:SetText(tostring(n))
        end
    end

    local function Nudge(delta)
        set(Clamp((NumText(get()) or low) + delta, low, high))
        Update()
        RefreshUI()
    end

    minus:SetScript("OnClick", function() Nudge(-step) end)
    plus:SetScript("OnClick", function() Nudge(step) end)

    AddUpdater(Update)
    Update()
    return row, nextY
end

--- Cycle row: a button that walks a fixed list of values.
--  entries = { { value = "auto", key = "BASE_MODE_AUTO" }, ... }
--  An entry may carry `label` instead of `key` (LibSharedMedia font names).
local function AddCycle(parent, y, labelKey, entries, get, set, width)
    local row, nextY = AddRow(parent, y)
    AddRowLabel(row, labelKey)

    local button = NewButton(row, width or 200, 24, "")
    button:SetPoint("RIGHT", -12, 0)
    AttachTooltip(button, L(labelKey), L("TOOLTIP_CLICK_CYCLE"))

    local function EntryLabel(entry)
        if entry.key then return L(entry.key) end
        if entry.label then return entry.label end
        return tostring(entry.value)
    end

    local function EntryFor(value)
        for index = 1, #entries do
            if entries[index].value == value then return entries[index] end
        end
        return nil
    end

    local function Update()
        local entry = EntryFor(get())
        if entry then
            button._text:SetText(EntryLabel(entry))
        else
            button._text:SetText(tostring(get()))
        end
    end

    button:SetScript("OnClick", function()
        if #entries == 0 then return end
        local current = get()
        local index = 1
        for i = 1, #entries do
            if entries[i].value == current then
                index = i
            end
        end
        index = (index % #entries) + 1
        set(entries[index].value)
        Update()
        RefreshUI()
    end)

    AddUpdater(Update)
    Update()
    return row, nextY
end

-------------------------------------------------------------------------------
--  Font list (fixed defaults plus LibSharedMedia when it is installed)
-------------------------------------------------------------------------------
local fontEntries

local function GetFontEntries()
    if fontEntries then return fontEntries end
    fontEntries = {
        { value = "Fonts\\FRIZQT__.TTF", key = "FONT_FRIZQUAD" },
        { value = "Fonts\\ARIALN.TTF", key = "FONT_ARIALN" },
        { value = "Fonts\\MORPHEUS.TTF", key = "FONT_MORPHEUS" },
        { value = "Fonts\\skurri.ttf", key = "FONT_SKURRI" },
    }
    local libStub = _G.LibStub
    local lsm = libStub and libStub("LibSharedMedia-3.0", true)
    if lsm and lsm.List then
        local ok, names = pcall(lsm.List, lsm, "font")
        if ok and type(names) == "table" then
            for index = 1, #names do
                local name = names[index]
                if type(name) == "string" and name ~= "" then
                    fontEntries[#fontEntries + 1] = { value = name, label = name }
                end
            end
        end
    end
    return fontEntries
end

local function ResolveFontPath(value)
    if type(value) == "string" and value ~= "" then
        local lower = string.lower(value)
        if string.sub(lower, 1, 6) == "fonts\\" or string.sub(lower, 1, 10) == "interface\\" then
            return value
        end
        local libStub = _G.LibStub
        local lsm = libStub and libStub("LibSharedMedia-3.0", true)
        if lsm and lsm.Fetch then
            local ok, path = pcall(lsm.Fetch, lsm, "font", value)
            if ok and type(path) == "string" and path ~= "" then return path end
        end
    end
    return "Fonts\\FRIZQT__.TTF"
end

-------------------------------------------------------------------------------
--  Status bar
-------------------------------------------------------------------------------
local statusBar
local OpenOptions   -- forward declaration: the panel section defines it below

local function StatusBarVisual(status)
    local state = ResolveState(status)
    local color = STATE_COLOR[state] or STATE_COLOR.idle
    local text
    if state == "error" or state == "unavailable" or state == "disabled" then
        -- Never show a number for a state the addon is not managing.
        text = StateLabel(state)
    else
        local current = EffectiveCurrent(status)
        if current == nil then
            text = L("VALUE_UNAVAILABLE")
        else
            text = Format("UNIT_MS", current)
        end
    end
    return text, color, state
end

local function ApplyStatusBarPosition()
    if not statusBar then return end
    statusBar:ClearAllPoints()
    local pos = Cfg().statusBarPos
    local x, y
    if type(pos) == "table" then
        x, y = NumText(pos.x), NumText(pos.y)
    end
    if x and y then
        statusBar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
    else
        statusBar:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

local function UpdateStatusBar()
    if not statusBar then return end
    local status = Core.GetStatus()
    local text, color = StatusBarVisual(status)
    local label = statusBar._text
    label:SetText(text)
    label:SetTextColor(color[1], color[2], color[3])
    local size = NumText(Cfg().statusFontSize) or 12
    statusBar:SetSize(math.max(64, (label:GetStringWidth() or 40) + 26), math.max(22, size + 12))
end

local function ApplyStatusBarStyle()
    if not statusBar then return end
    local size = NumText(Cfg().statusFontSize) or 12
    local path = ResolveFontPath(Cfg().statusFont)
    local label = statusBar._text
    local ok = pcall(label.SetFont, label, path, size, "OUTLINE")
    if not ok then
        pcall(label.SetFont, label, "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    end
    UpdateStatusBar()
end

local function ApplyStatusBarVisibility()
    if not statusBar then return end
    if Cfg().showStatus then
        statusBar:Show()
    else
        statusBar:Hide()
    end
end

local function SaveStatusBarPosition()
    if not statusBar or not UIParent then return end
    local left, top = statusBar:GetLeft(), statusBar:GetTop()
    local parentLeft, parentTop = UIParent:GetLeft(), UIParent:GetTop()
    if not (left and top and parentLeft and parentTop) then return end
    local x = Clamp(left - parentLeft, 0, math.max(0, UIParent:GetWidth() - statusBar:GetWidth()))
    local y = Clamp(top - parentTop, -math.max(0, UIParent:GetHeight() - statusBar:GetHeight()), 0)
    Core.SetConfig("statusBarPos", { x = math.floor(x + 0.5), y = math.floor(y + 0.5) },
        { noRefresh = true })
end

local function ShowStatusBarTooltip(owner)
    if not GameTooltip then return end
    local status = Core.GetStatus()
    local text, _, state = StatusBarVisual(status)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(L("PANEL_TITLE"), ACCENT[1], ACCENT[2], ACCENT[3])
    GameTooltip:AddDoubleLine(L("LABEL_STATUS"), StateLabel(state), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(L("LABEL_CURRENT"), text, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(L("LABEL_TARGET"), MsText(status.target), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(L("LABEL_LATENCY"), MsText(status.latency), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(L("LABEL_WORLD"), MsText(status.world), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine(L("LABEL_HOME"), MsText(status.home), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine(L("LABEL_SPEC"),
        SpecText(status) .. " · " .. RoleText(status.role), 1, 1, 1, 1, 1, 1)
    if state == "error" or state == "unavailable" then
        GameTooltip:AddLine(ReasonText(status), STATE_COLOR.error[1], STATE_COLOR.error[2],
            STATE_COLOR.error[3], true)
    end
    GameTooltip:AddLine(SampledText(status), 0.80, 0.80, 0.80, true)
    GameTooltip:AddLine(L("TOOLTIP_STATUS_BAR"), 0.80, 0.80, 0.80, true)
    GameTooltip:Show()
end

local function CreateStatusBar()
    if statusBar then return statusBar end
    if not UIParent then return nil end

    local bar = CreateFrame("Frame", "AutoSpellQueueStatusBar", UIParent)
    bar:SetSize(84, 24)
    bar:SetFrameStrata("MEDIUM")
    bar:EnableMouse(true)
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetClampedToScreen(true)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetColor(bg, 0.02, 0.03, 0.04, 0.88)
    AddBorder(bar, ACCENT[1], ACCENT[2], ACCENT[3], 0.55)

    local label = bar:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    label:SetText(L("VALUE_PLACEHOLDER"))
    bar._text = label
    bar._dragging = false
    bar._accum = 0

    bar:SetScript("OnMouseDown", function(self)
        self._dragging = false
    end)
    bar:SetScript("OnDragStart", function(self)
        self._dragging = true
        self:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveStatusBarPosition()
    end)
    bar:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and not self._dragging then
            OpenOptions()
        end
        self._dragging = false
    end)
    bar:SetScript("OnEnter", function(self)
        ShowStatusBarTooltip(self)
    end)
    bar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- Only runs while the bar is visible: a hidden frame gets no OnUpdate.
    bar:SetScript("OnUpdate", function(self, elapsed)
        self._accum = self._accum + (elapsed or 0)
        if self._accum < 1 then return end
        self._accum = 0
        UpdateStatusBar()
    end)

    statusBar = bar
    ApplyStatusBarPosition()
    ApplyStatusBarStyle()
    ApplyStatusBarVisibility()
    return bar
end

local function ResetStatusBarPosition(announce)
    Core.SetConfig("statusBarPos", nil, { noRefresh = true })
    local wasHidden = not Cfg().showStatus
    if wasHidden then
        Core.SetConfig("showStatus", true, { noRefresh = true })
    end
    CreateStatusBar()
    ApplyStatusBarPosition()
    ApplyStatusBarVisibility()
    ApplyStatusBarStyle()
    RefreshUI()
    if announce ~= false then
        Say(L("MSG_POSITION_RESET"))
        if wasHidden then Say(L("MSG_STATUS_BAR_SHOWN")) end
    end
end

-------------------------------------------------------------------------------
--  Settings panel
-------------------------------------------------------------------------------
local host             -- frame the UI is built inside (canvas panel / scroll child)
local category         -- Settings category object
local standalone       -- fallback window when the Settings API is missing
local applyAdvancedView
local panelReady = false

local function SetContentHeight(content, height)
    content:SetHeight(height)
    if host and host.SetHeight then
        host:SetHeight(height + PANEL_PAD * 2)
    end
end

--- Opens the settings page: the Blizzard category when it exists, otherwise the
--- standalone window. Never silently does nothing.
function OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        local id
        if category.GetID then
            local ok, value = pcall(category.GetID, category)
            if ok then id = value end
        end
        if id == nil then id = category.ID end
        if id ~= nil then
            if pcall(Settings.OpenToCategory, id) then return true end
        end
    end
    if standalone then
        standalone:Show()
        return true
    end
    Say(L("MSG_OPEN_FAILED"))
    return false
end

local function BuildUI(contentParent)
    local content = CreateFrame("Frame", nil, contentParent)
    content:SetPoint("TOPLEFT", contentParent, "TOPLEFT", PANEL_PAD, -PANEL_PAD)
    content:SetPoint("TOPRIGHT", contentParent, "TOPRIGHT", -PANEL_PAD, -PANEL_PAD)

    -- Throttled refresh ticker for the panel. It is a child of the panel on
    -- purpose: the client does not call OnUpdate on a frame whose parent is
    -- hidden, so this costs nothing while the settings page is closed, and it
    -- is never called on hidden widgets.
    local poller = CreateFrame("Frame", nil, contentParent)
    poller:SetAllPoints(contentParent)
    local pollAccum = 0
    poller:SetScript("OnUpdate", function(_, elapsed)
        pollAccum = pollAccum + (elapsed or 0)
        if pollAccum < POLL_INTERVAL then return end
        pollAccum = 0
        RefreshUI()
    end)

    local y = 0

    -- Header ---------------------------------------------------------------
    local title = NewText(content, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    title:SetText(L("PANEL_TITLE"))
    title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    y = y - 30

    local subtitle = NewText(content, "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    subtitle:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetWordWrap(true)
    subtitle:SetTextColor(1, 1, 1, 0.55)
    subtitle:SetText(L("PANEL_SUBTITLE"))
    y = y - math.max(16, subtitle:GetStringHeight() or 16) - 10

    -- Master switch --------------------------------------------------------
    y = select(2, AddToggle(content, y, "SETTING_ENABLED",
        function() return Core.IsEnabled() end,
        function(value) Core.SetEnabled(value) end,
        "SETTING_ENABLED_HINT"))

    y = y - 8

    -- Status card ----------------------------------------------------------
    local cardHeight = 208
    local card = CreateFrame("Frame", nil, content)
    card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    card:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    card:SetHeight(cardHeight)
    local cardBg = card:CreateTexture(nil, "BACKGROUND")
    cardBg:SetAllPoints()
    SetColor(cardBg, 0, 0, 0, 0.32)
    AddBorder(card, 1, 1, 1, 0.10)
    y = y - cardHeight - 10

    local badge = CreateFrame("Frame", nil, card)
    badge:SetPoint("TOPLEFT", 12, -12)
    badge:SetSize(96, 22)
    badge:EnableMouse(true)
    local badgeBg = badge:CreateTexture(nil, "BACKGROUND")
    badgeBg:SetAllPoints()
    SetColor(badgeBg, 0.20, 0.20, 0.20, 0.80)
    local badgeText = NewText(badge, "GameFontNormalSmall")
    badgeText:SetPoint("CENTER")
    badgeText:SetText(L("STATE_IDLE"))
    badge:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self._title or "", 1, 1, 1, true)
        if self._body then GameTooltip:AddLine(self._body, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local currentLabel = NewText(card, "GameFontNormalSmall")
    currentLabel:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -10)
    currentLabel:SetText(L("LABEL_CURRENT"))
    currentLabel:SetTextColor(1, 1, 1, 0.55)
    local currentValue = NewText(card, "GameFontNormalLarge")
    currentValue:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -26)
    currentValue:SetText(L("VALUE_PLACEHOLDER"))

    local columnWidth = (INNER_WIDTH - 28) / 2
    local function AddCardField(column, rowIndex, labelText)
        local baseX = 14 + column * columnWidth
        local baseY = -48 - rowIndex * 20
        local label = NewText(card, "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", card, "TOPLEFT", baseX, baseY)
        label:SetText(labelText)
        label:SetTextColor(1, 1, 1, 0.50)
        local value = NewText(card, "GameFontHighlightSmall")
        value:SetPoint("TOPRIGHT", card, "TOPLEFT", baseX + columnWidth - 24, baseY)
        value:SetJustifyH("RIGHT")
        value:SetText(L("VALUE_PLACEHOLDER"))
        return value
    end

    local targetValue = AddCardField(0, 0, L("LABEL_TARGET") .. " (" .. L("TAG_SAMPLED") .. ")")
    local latencyValue = AddCardField(1, 0, L("LABEL_LATENCY") .. " (" .. L("TAG_SAMPLED") .. ")")
    local contextValue = AddCardField(0, 1, L("LABEL_CONTEXT"))
    local specValue = AddCardField(1, 1, L("LABEL_SPEC"))
    local baseValue = AddCardField(0, 2, L("LABEL_BASE"))
    local baselineValue = AddCardField(1, 2, L("LABEL_BASELINE"))

    local formulaLine = NewText(card, "GameFontNormalSmall")
    formulaLine:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -110)
    formulaLine:SetWidth(INNER_WIDTH - 28)
    formulaLine:SetJustifyH("LEFT")
    formulaLine:SetWordWrap(false)
    formulaLine:SetTextColor(1, 1, 1, 0.70)
    formulaLine:SetText(L("FORMULA_UNKNOWN"))

    local sampledLine = NewText(card, "GameFontNormalSmall")
    sampledLine:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -128)
    sampledLine:SetWidth(INNER_WIDTH - 28)
    sampledLine:SetJustifyH("LEFT")
    sampledLine:SetWordWrap(true)
    sampledLine:SetTextColor(1, 1, 1, 0.40)

    local hintLine = NewText(card, "GameFontNormalSmall")
    hintLine:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -146)
    hintLine:SetWidth(INNER_WIDTH - 28)
    hintLine:SetJustifyH("LEFT")
    hintLine:SetWordWrap(true)
    hintLine:SetTextColor(1, 1, 1, 0.75)
    hintLine:SetText(L("HINT_IDLE"))

    AddUpdater(function()
        local status = refreshStatus
        local state = ResolveState(status)
        local color = STATE_COLOR[state] or STATE_COLOR.idle
        local stateText = StateLabel(state)

        badgeText:SetText(stateText)
        badgeText:SetTextColor(color[1], color[2], color[3])
        SetColor(badgeBg, color[1], color[2], color[3], 0.22)
        badge._title = L("LABEL_STATUS") .. ": " .. stateText

        local current = EffectiveCurrent(status)
        if current ~= nil then
            currentValue:SetText(Format("UNIT_MS", current))
            currentValue:SetTextColor(color[1], color[2], color[3])
        else
            currentValue:SetText(L("VALUE_UNAVAILABLE"))
            currentValue:SetTextColor(STATE_COLOR.unavailable[1], STATE_COLOR.unavailable[2],
                STATE_COLOR.unavailable[3])
        end

        targetValue:SetText(MsText(status.target))
        -- Only the picked latency here: the world/home breakdown would collide
        -- with the label in a narrow column. It lives in the tooltip and in
        -- "/asq status".
        latencyValue:SetText(MsText(status.latency))
        contextValue:SetText(ContextText(status.context))
        specValue:SetText(SpecText(status) .. " · " .. RoleText(status.role))
        baseValue:SetText(MsText(status.base))
        if status.owned then
            baselineValue:SetText(MsText(status.baseline))
        else
            -- Not "unavailable": there simply is nothing to put back yet.
            baselineValue:SetText(L("VALUE_NONE"))
        end

        formulaLine:SetText(FormulaText(refreshCfg, status))
        sampledLine:SetText(SampledText(status))

        local hint
        local hintColor = { 1, 1, 1, 0.75 }
        if state == "error" then
            local age = NumText(status.lastErrorAt)
            local text = Format("HINT_ERROR", ReasonText(status))
            if age then
                local seconds = math.max(0, math.floor(Core.Now() - age))
                text = text .. "  " .. Format("HINT_ERROR_AGE", seconds)
            end
            hint = text
            hintColor = { STATE_COLOR.error[1], STATE_COLOR.error[2], STATE_COLOR.error[3], 1 }
            badge._body = hint
        elseif state == "unavailable" then
            hint = Format("HINT_UNAVAILABLE", ReasonText(status))
            hintColor = { STATE_COLOR.unavailable[1], STATE_COLOR.unavailable[2], STATE_COLOR.unavailable[3], 1 }
            badge._body = hint
        elseif state == "pending" then
            hint = L("HINT_PENDING")
            badge._body = hint
        elseif state == "disabled" then
            if status.owned then
                hint = Format("HINT_DISABLED_OWNED", NumText(status.baseline) or 0)
            else
                hint = L("HINT_DISABLED")
            end
            badge._body = hint
        elseif state == "applied" then
            hint = L("HINT_APPLIED")
            badge._body = L("HINT_APPLIED")
        else
            hint = L("HINT_IDLE")
            badge._body = L("HINT_IDLE")
        end

        if status.externalChange then
            hint = hint .. "  " .. L("HINT_EXTERNAL_CHANGE")
        end
        if status.schemaFuture then
            hint = hint .. "  " .. L("HINT_SCHEMA_FUTURE")
        end
        if status.importedFrom then
            hint = hint .. "  " .. L("HINT_IMPORTED")
        end
        if state ~= "disabled" and state ~= "error" and state ~= "unavailable" then
            local latency = NumText(status.latency) or 0
            local world = NumText(status.world) or 0
            local home = NumText(status.home) or 0
            if latency == 0 and world == 0 and home == 0 then
                hint = hint .. "  " .. L("HINT_NO_LATENCY")
            end
        end
        hintLine:SetText(hint)
        hintLine:SetTextColor(hintColor[1], hintColor[2], hintColor[3], hintColor[4])
    end)

    -- Advanced fold --------------------------------------------------------
    local advancedButton = NewButton(content, INNER_WIDTH, 28, "")
    advancedButton:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    AttachTooltip(advancedButton, function()
        return Cfg().showAdvanced and L("ADVANCED_HIDE") or L("ADVANCED_SHOW")
    end, L("TOOLTIP_ADVANCED"))
    advancedButton:SetScript("OnClick", function()
        Core.SetConfig("showAdvanced", not Cfg().showAdvanced, { noRefresh = true })
        if applyAdvancedView then applyAdvancedView() end
        RefreshUI()
    end)
    AddUpdater(function()
        if Cfg().showAdvanced then
            advancedButton._text:SetText(L("ADVANCED_HIDE"))
        else
            advancedButton._text:SetText(L("ADVANCED_SHOW"))
        end
    end)

    local advancedTop = y - 36
    local advancedHeight = 0

    local advanced = CreateFrame("Frame", nil, content)
    advanced:SetPoint("TOPLEFT", content, "TOPLEFT", 0, advancedTop)
    advanced:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, advancedTop)
    advanced:SetHeight(10)

    local ay = 0
    local row

    -- Calculation ----------------------------------------------------------
    ay = AddSectionHeader(advanced, ay, "SECTION_CALC")

    row, ay = AddCycle(advanced, ay, "SETTING_BASE_MODE", {
        { value = "auto", key = "BASE_MODE_AUTO" },
        { value = "manual", key = "BASE_MODE_MANUAL" },
    }, function() return Cfg().baseMode end,
        function(value) Core.SetConfig("baseMode", value) end, 200)

    do
        local manualRow
        manualRow, ay = AddStepper(advanced, ay, "SETTING_MANUAL_BASE", 50, 400, 5,
            function() return Cfg().manualBase end,
            function(value) Core.SetConfig("manualBase", value) end, "UNIT_MS")
        AddUpdater(function()
            manualRow:SetShown(Cfg().baseMode == "manual")
        end)
    end

    row, ay = AddToggle(advanced, ay, "SETTING_ADAPTIVE",
        function() return Cfg().adaptive ~= false end,
        function(value) Core.SetConfig("adaptive", value) end)

    row, ay = AddStepper(advanced, ay, "SETTING_MARGIN", 0, 300, 5,
        function() return Cfg().margin end,
        function(value) Core.SetConfig("margin", value) end, "UNIT_MS")

    row, ay = AddStepper(advanced, ay, "SETTING_MIN", 0, 400, 5,
        function() return Cfg().minWindow end,
        function(value) Core.SetConfig("minWindow", value) end, "UNIT_MS")

    row, ay = AddStepper(advanced, ay, "SETTING_MAX", 0, 400, 5,
        function() return Cfg().maxWindow end,
        function(value) Core.SetConfig("maxWindow", value) end, "UNIT_MS")

    row, ay = AddStepper(advanced, ay, "SETTING_HYSTERESIS", 0, 100, 1,
        function() return Cfg().hysteresis end,
        function(value) Core.SetConfig("hysteresis", value) end, "UNIT_MS")

    row, ay = AddCycle(advanced, ay, "SETTING_LATENCY_SOURCE", {
        { value = "world", key = "LATENCY_WORLD" },
        { value = "home", key = "LATENCY_HOME" },
        { value = "avg", key = "LATENCY_AVG" },
        { value = "max", key = "LATENCY_MAX" },
    }, function() return Cfg().latencySource end,
        function(value) Core.SetConfig("latencySource", value) end, 220)

    -- Status bar -----------------------------------------------------------
    ay = ay - 8
    ay = AddSectionHeader(advanced, ay, "SECTION_STATUS_BAR")

    row, ay = AddToggle(advanced, ay, "SETTING_SHOW_STATUS",
        function() return Cfg().showStatus end,
        function(value)
            Core.SetConfig("showStatus", value, { noRefresh = true })
            CreateStatusBar()
            ApplyStatusBarVisibility()
            if value then ApplyStatusBarStyle() end
        end)

    row, ay = AddCycle(advanced, ay, "SETTING_STATUS_FONT", GetFontEntries(),
        function() return Cfg().statusFont end,
        function(value)
            Core.SetConfig("statusFont", value, { noRefresh = true })
            ApplyStatusBarStyle()
        end, 240)

    row, ay = AddStepper(advanced, ay, "SETTING_STATUS_FONT_SIZE", 8, 32, 1,
        function() return Cfg().statusFontSize end,
        function(value)
            Core.SetConfig("statusFontSize", value, { noRefresh = true })
            ApplyStatusBarStyle()
        end)

    do
        local positionRow
        positionRow, ay = AddRow(advanced, ay, 30)
        local positionButton = NewButton(positionRow, 180, 24, L("BUTTON_RESET_POSITION"))
        positionButton:SetPoint("LEFT", 12, 0)
        AttachTooltip(positionButton, L("BUTTON_RESET_POSITION"), L("TOOLTIP_RESET_POSITION"))
        positionButton:SetScript("OnClick", function() ResetStatusBarPosition(true) end)
    end

    -- Misc -----------------------------------------------------------------
    ay = ay - 8
    ay = AddSectionHeader(advanced, ay, "SECTION_MISC")

    row, ay = AddToggle(advanced, ay, "SETTING_CHAT_FEEDBACK",
        function() return Cfg().chatFeedback end,
        function(value) Core.SetConfig("chatFeedback", value) end,
        "SETTING_CHAT_FEEDBACK_HINT")

    do
        local actionsRow
        actionsRow, ay = AddRow(advanced, ay, 30)

        local refreshButton = NewButton(actionsRow, 180, 24, L("BUTTON_REFRESH"))
        refreshButton:SetPoint("LEFT", 12, 0)
        AttachTooltip(refreshButton, L("BUTTON_REFRESH"), L("TOOLTIP_REFRESH"))
        refreshButton:SetScript("OnClick", function()
            Core.Refresh("ui")
            PullState()
            UpdateStatusBar()
            RefreshUI()
            Say(L("MSG_REFRESHED"))
        end)

        local armed = false
        local resetButton = NewButton(actionsRow, 180, 24, L("BUTTON_RESET_SETTINGS"))
        resetButton:SetPoint("RIGHT", -12, 0)
        AttachTooltip(resetButton, L("BUTTON_RESET_SETTINGS"), L("TOOLTIP_RESET_SETTINGS"))
        local function Disarm()
            armed = false
            resetButton._text:SetText(L("BUTTON_RESET_SETTINGS"))
        end
        resetButton:SetScript("OnClick", function()
            if not armed then
                armed = true
                resetButton._text:SetText(L("BUTTON_RESET_SETTINGS_CONFIRM"))
                if C_Timer and C_Timer.After then
                    C_Timer.After(4, Disarm)
                end
                return
            end
            Disarm()
            Core.ResetSettings()
            PullState()
            if applyAdvancedView then applyAdvancedView() end
            ApplyStatusBarStyle()
            ApplyStatusBarVisibility()
            UpdateStatusBar()
            RefreshUI()
            Say(L("MSG_RESET_DONE"))
        end)
    end

    -- Diagnostics ----------------------------------------------------------
    ay = ay - 8
    ay = AddSectionHeader(advanced, ay, "SECTION_DIAGNOSTICS")

    local function AddDiagLine(labelKey)
        local line = CreateFrame("Frame", nil, advanced)
        line:SetPoint("TOPLEFT", advanced, "TOPLEFT", 2, ay)
        line:SetPoint("TOPRIGHT", advanced, "TOPRIGHT", -2, ay)
        line:SetHeight(16)
        local label = NewText(line, "GameFontNormalSmall")
        label:SetPoint("LEFT", 0, 0)
        label:SetText(L(labelKey))
        label:SetTextColor(1, 1, 1, 0.45)
        local value = NewText(line, "GameFontNormalSmall")
        value:SetPoint("RIGHT", 0, 0)
        value:SetJustifyH("RIGHT")
        value:SetText(L("VALUE_PLACEHOLDER"))
        value:SetTextColor(1, 1, 1, 0.75)
        ay = ay - 16
        return value
    end

    local ownedLine = AddDiagLine("LABEL_OWNED")
    local baselineLine = AddDiagLine("LABEL_BASELINE")
    local lastAppliedLine = AddDiagLine("LABEL_LAST_APPLIED")
    local applyCountLine = AddDiagLine("LABEL_APPLY_COUNT")
    local repairsLine = AddDiagLine("LABEL_REPAIRS")
    local refreshLine = AddDiagLine("LABEL_REFRESH")
    local cvarLine = AddDiagLine("LABEL_CVAR")
    local errorLine = AddDiagLine("LABEL_LAST_ERROR")

    AddUpdater(function()
        local status = refreshStatus
        ownedLine:SetText(status.owned and L("VALUE_YES") or L("VALUE_NO"))
        baselineLine:SetText(MsText(status.baseline))
        lastAppliedLine:SetText(MsText(status.lastApplied))
        applyCountLine:SetText(tostring(NumText(status.applyCount) or 0))
        repairsLine:SetText(tostring(NumText(status.repairs) or 0))
        refreshLine:SetText(Format("UNIT_SECONDS", NumText(status.refreshSeconds) or 0))
        cvarLine:SetText(CvarText(status.cvarInfo))

        local err = status.lastError
        if type(err) == "string" and err ~= "" then
            local key = (Core.REASON_KEY and Core.REASON_KEY[err]) or err
            local text = L(key)
            local age = NumText(status.lastErrorAt)
            if age then
                local seconds = math.max(0, math.floor(Core.Now() - age))
                text = text .. "  (" .. Format("HINT_ERROR_AGE", seconds) .. ")"
            end
            errorLine:SetText(text)
            errorLine:SetTextColor(STATE_COLOR.error[1], STATE_COLOR.error[2], STATE_COLOR.error[3])
        else
            errorLine:SetText(L("VALUE_NONE"))
            errorLine:SetTextColor(1, 1, 1, 0.75)
        end
    end)

    advancedHeight = -ay + 6
    advanced:SetHeight(advancedHeight)

    -- The fold only changes visibility and the content height: no rebuild.
    local mainHeight = -advancedTop
    applyAdvancedView = function()
        local show = Cfg().showAdvanced and true or false
        advanced:SetShown(show)
        SetContentHeight(content, mainHeight + (show and (advancedHeight + 10) or 0) + 6)
    end

    applyAdvancedView()
    built = true
    RefreshUI()
end

-------------------------------------------------------------------------------
--  Hosts
-------------------------------------------------------------------------------
local function EnsureBuilt()
    if panelReady then return end
    panelReady = true
    PullState()
    if host then
        BuildUI(host)
    end
end

local function MarkPanelVisible()
    EnsureBuilt()
    RefreshUI()
end

local function CreateStandaloneWindow()
    local window = CreateFrame("Frame", "AutoSpellQueueOptionsFrame", UIParent)
    window:SetSize(PANEL_WIDTH, 540)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetClampedToScreen(true)
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local bg = window:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetColor(bg, 0.05, 0.07, 0.09, 0.97)
    AddBorder(window, ACCENT[1], ACCENT[2], ACCENT[3], 0.85)

    local title = NewText(window, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText(L("PANEL_TITLE"))
    title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

    local close = NewButton(window, 26, 22, L("BUTTON_CLOSE"))
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() window:Hide() end)

    local scroll = CreateFrame("ScrollFrame", "AutoSpellQueueOptionsScroll", window,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -44)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(PANEL_WIDTH, 420)
    scroll:SetScrollChild(child)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "AutoSpellQueueOptionsFrame")
    end

    window:HookScript("OnShow", MarkPanelVisible)
    window:Hide()

    standalone = window
    host = child
    host:SetHeight(420)
    return window
end

local function TryCreateSettingsCategory()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return false
    end
    local panel = CreateFrame("Frame", "AutoSpellQueueOptionsPanel", UIParent)
    panel.name = L("PANEL_TITLE")
    panel:SetSize(PANEL_WIDTH, 420)
    panel:HookScript("OnShow", MarkPanelVisible)

    local ok, newCategory = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name, panel.name)
    if not ok or type(newCategory) ~= "table" then
        panel:Hide()
        return false
    end
    if newCategory.ID == nil then
        newCategory.ID = panel.name
    end
    if not pcall(Settings.RegisterAddOnCategory, newCategory) then
        panel:Hide()
        return false
    end

    category = newCategory
    host = panel

    -- The client remembers the last settings page: it may already be visible.
    if panel:IsShown() then
        MarkPanelVisible()
    end
    return true
end

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
local function PrintHelp()
    Say(L("SLASH_HELP"))
    Say(L("SLASH_HELP_TITLE"))
    Say(L("SLASH_CMD_OPEN"))
    Say(L("SLASH_CMD_STATUS"))
    Say(L("SLASH_CMD_RESET"))
    Say(L("SLASH_CMD_UNLOCK"))
end

local function DiagnosticLines(status)
    local lines = {}
    local function Add(key, value)
        lines[#lines + 1] = L(key) .. ": " .. tostring(value)
    end

    local state = ResolveState(status)
    Add("LABEL_STATUS", StateLabel(state))
    if state == "error" or state == "unavailable" then
        -- The failure of this very refresh, with the raw reason for bug reports.
        Add("LABEL_LAST_ERROR", ReasonText(status) .. "  ["
            .. tostring(status.stateReason or "-") .. "]")
    elseif type(status.lastError) == "string" and status.lastError ~= "" then
        local key = (Core.REASON_KEY and Core.REASON_KEY[status.lastError]) or status.lastError
        Add("LABEL_LAST_ERROR", L(key) .. "  [" .. status.lastError .. "]")
    end
    Add("LABEL_ENABLED", status.enabled and L("VALUE_ON") or L("VALUE_OFF"))
    Add("LABEL_CURRENT", MsText(status.current))
    Add("LABEL_TARGET", MsText(status.target))
    Add("LABEL_BASE", MsText(status.base))
    Add("LABEL_LATENCY", MsText(status.latency))
    Add("LABEL_WORLD", MsText(status.world))
    Add("LABEL_HOME", MsText(status.home))
    Add("LABEL_CONTEXT", ContextText(status.context))
    Add("LABEL_SPEC", SpecText(status) .. " · " .. RoleText(status.role)
        .. " · " .. tostring(status.classFile or "?"))
    Add("LABEL_FORMULA", FormulaText(Core.GetConfig(), status))
    Add("LABEL_OWNED", status.owned and L("VALUE_YES") or L("VALUE_NO"))
    Add("LABEL_BASELINE", MsText(status.baseline))
    Add("LABEL_LAST_APPLIED", MsText(status.lastApplied))
    Add("LABEL_APPLY_COUNT", NumText(status.applyCount) or 0)
    Add("LABEL_REPAIRS", NumText(status.repairs) or 0)
    Add("LABEL_REFRESH", Format("UNIT_SECONDS", NumText(status.refreshSeconds) or 0))
    Add("LABEL_CVAR", CvarText(status.cvarInfo))
    lines[#lines + 1] = Format("DIAG_FLAGS",
        tostring(status.inWorld and true or false),
        tostring(status.inCombat and true or false),
        tostring(status.externalChange and true or false),
        tostring(status.schemaFuture and true or false))
    return lines
end

local function PrintStatus()
    PullState()
    local status = Core.GetStatus()
    local lines = DiagnosticLines(status)
    if #lines == 0 then
        Say(L("VALUE_UNAVAILABLE"))
        return
    end
    for index = 1, #lines do
        Say(lines[index])
    end
end

local function DoReset()
    Core.ResetSettings()
    PullState()
    if applyAdvancedView then applyAdvancedView() end
    ApplyStatusBarStyle()
    ApplyStatusBarVisibility()
    UpdateStatusBar()
    RefreshUI()
    Say(L("MSG_RESET_DONE"))
end

local function HandleSlash(input)
    local command = string.lower(type(input) == "string" and input or "")
    command = string.gsub(command, "^%s+", "")
    command = string.gsub(command, "%s+$", "")

    if command == "" or command == "config" or command == "options" or command == "settings" then
        OpenOptions()
        return
    end
    if command == "status" or command == "debug" or command == "diag" then
        PrintStatus()
        return
    end
    if command == "reset" then
        DoReset()
        return
    end
    if command == "unlock" or command == "resetpos" then
        ResetStatusBarPosition(true)
        return
    end
    PrintHelp()
end

local function RegisterSlashCommands()
    if not SlashCmdList then return end
    SLASH_AUTOSPELLQUEUE1 = "/asq"
    SLASH_AUTOSPELLQUEUE2 = "/autospellqueue"
    SlashCmdList["AUTOSPELLQUEUE"] = HandleSlash
end

-------------------------------------------------------------------------------
--  Setup
-------------------------------------------------------------------------------
local initialized = false

local function Setup()
    if initialized then return end
    initialized = true
    PullState()
    RegisterSlashCommands()
    CreateStatusBar()
    ApplyStatusBarVisibility()
    if not TryCreateSettingsCategory() then
        CreateStandaloneWindow()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("CVAR_UPDATE")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= Core.NAME then return end
        Setup()
        return
    end
    if event == "PLAYER_LOGIN" then
        Setup()
        return
    end
    if event == "CVAR_UPDATE" then
        if arg1 ~= nil and CVar and arg1 ~= CVar.NAME then return end
    end
    -- Cheap path: the status bar is the only always-on surface. The panel
    -- refreshes itself through its own visible-only ticker.
    UpdateStatusBar()
end)

Options.Open = OpenOptions
Options.Refresh = RefreshUI
Options.PrintStatus = PrintStatus
Options.ResetStatusBarPosition = ResetStatusBarPosition
Options.Build = EnsureBuilt
