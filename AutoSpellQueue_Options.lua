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

--- Clamps a number into [low, high]. Non-numeric and NaN input becomes `low`
--- (same contract as Formula.Clamp) so a broken value can never reach a widget.
local function Clamp(value, low, high)
    local n = tonumber(value)
    if n == nil or n ~= n then return low end
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
--- because that failure is the thing the player has to know about. A pending
--- action also survives: disabling in combat defers the restore until combat
--- ends, and the player must see "waiting" rather than a plain "off" - the
--- docs promise exactly that.
local function ResolveState(status)
    local state = status.state or "idle"
    if state ~= "error" and state ~= "unavailable" and state ~= "pending"
        and not status.enabled then
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
    -- No fixed refresh interval any more: say what the sampler is actually doing.
    local key = "HINT_SAMPLED_SETTLING"
    if status.cadence == "fixed" then key = "HINT_SAMPLED_FIXED" end
    local text = L(key)
    local at = NumText(status.snapshotAt)
    if at then
        local seconds = math.max(0, math.floor(Core.Now() - at))
        text = text .. " " .. Format("HINT_SNAPSHOT_AGE", seconds)
    end
    return text
end

--- Human wording for the sampling policy the core reports.
local function CadenceText(status)
    local cadence = status.cadence
    local interval = NumText(status.intervalSeconds)
    if cadence == "settling" then
        return Format("CADENCE_SETTLING", NumText(status.settleSamples) or 0)
    end
    if cadence == "pending" then
        return Format("CADENCE_PENDING", interval or 15)
    end
    return Format("CADENCE_FIXED", interval or NumText(status.heartbeatSeconds) or 300)
end

local function CvarText(info)    if type(info) ~= "table" then return L("VALUE_UNAVAILABLE") end
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

--- Turns on wrapping that also works for Chinese/Japanese text.
--  `SetWordWrap(true)` alone only breaks at spaces, so a long Chinese sentence
--  has nowhere to break and the client truncates it with an ellipsis (seen
--  in-game: the panel subtitle ended in "**不..."). SetNonSpaceWrap lets the
--  client break inside space-less runs, which is what CJK needs.
local function EnableWrap(fontString)
    fontString:SetWordWrap(true)
    fontString:SetNonSpaceWrap(true)
    return fontString
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

--- Row label. `stacked` is for rows that also carry a hint: the label then sits
--- at the top of the row instead of being vertically centred, otherwise it is
--- drawn on top of the hint (the client has no automatic layout).
local function AddRowLabel(row, key, stacked)
    local label = NewText(row, "GameFontNormal")
    if stacked then
        label:SetPoint("TOPLEFT", 12, -6)
    else
        label:SetPoint("LEFT", 12, 0)
    end
    label:SetText(L(key))
    label:SetJustifyH("LEFT")
    return label
end

local function AddRowHint(row, key)
    local hint = NewText(row, "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 12, -25)
    hint:SetWidth(INNER_WIDTH - 40)
    hint:SetJustifyH("LEFT")
    EnableWrap(hint)
    hint:SetTextColor(1, 1, 1, 0.45)
    hint:SetText(L(key))
    return hint
end

--- Toggle row: right aligned switch plus a localised on/off word.
local function AddToggle(parent, y, labelKey, get, set, hintKey)
    -- Hinted rows are two lines: label on top, hint underneath.
    local height = hintKey and 56 or ROW_HEIGHT
    local row, nextY = AddRow(parent, y, height)
    AddRowLabel(row, labelKey, hintKey ~= nil)
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
    statusBar:SetSize(math.max(64, (label:GetStringWidth() or 40) + 26), 22)
end

--- The bar deliberately uses the client's own small font (inherited at
--- creation) instead of carrying font and size settings of its own: it then
--- follows the game's font and UI scale for free, and there is one less knob.
local function ApplyStatusBarStyle()
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

    -- A font object must be given here: the client raises
    -- "FontString:SetText(): Font not set" if SetText runs before any font is
    -- set, and that error used to abort the whole UI setup. ApplyStatusBarStyle
    -- replaces this font with the player's choice later.
    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    -- Only the scroll child grows; the host (settings canvas or standalone
    -- window) keeps the size the client gave it, otherwise the panel pushes
    -- itself past the bottom of the settings window.
    content:SetHeight(height)
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
    -- Everything lives inside a scroll frame. The advanced section is taller
    -- than the settings area, and the client scrolls nothing for us: without
    -- this the lower rows were drawn outside the window (on top of Blizzard's
    -- own Close button) instead of being clipped and scrollable.
    local scroll = CreateFrame("ScrollFrame", "AutoSpellQueueOptionsScroll", contentParent,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", contentParent, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", contentParent, "BOTTOMRIGHT", -26, 2)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", PANEL_PAD, -PANEL_PAD)
    -- A scroll child MUST carry an explicit width. The client does not derive it
    -- from anchors inside a ScrollFrame, and every widget here is anchored
    -- left+right to the content, so a zero-width child renders as *nothing at
    -- all* - that is exactly what left the settings page blank in-game
    -- (measured: SCROLL 639x602 but CHILD 0x440). Verified against GearInsight,
    -- which sets the width explicitly and re-applies it from OnSizeChanged.
    content:SetWidth(math.max(240, (scroll:GetWidth() or 0) - 2 * PANEL_PAD))
    content:SetHeight(10)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(math.max(240, (width or 0) - 2 * PANEL_PAD))
    end)

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

    -- Wrapping strings need an EXPLICIT width. A FontString that derives its
    -- width from left+right anchors does not re-flow in the client: it gets
    -- ellipsized mid-sentence ("...不需…" was measured in-game). So every
    -- wrapping string is registered here and given a width whenever the content
    -- frame is (re)sized.
    local wrappers = {}
    --- Registers a wrapping string and sets its width immediately.
    --  The width must be in place *before* the caller measures GetStringHeight:
    --  measuring a still-widthless string reports one line, so the next row is
    --  placed too high and the wrapped second line is drawn over it (seen
    --  in-game: the panel subtitle overlapped the master-switch row).
    local function WrapToWidth(fontString, inset)
        inset = inset or 0
        EnableWrap(fontString)
        wrappers[#wrappers + 1] = { fs = fontString, inset = inset }
        local width = content:GetWidth() or 0
        if width <= 0 then width = math.max(240, PANEL_WIDTH - 2 * PANEL_PAD) end
        fontString:SetWidth(math.max(120, width - inset))
        return fontString
    end
    local function ApplyWrapWidths()
        local width = content:GetWidth() or 0
        if width <= 0 then return end
        for _, entry in ipairs(wrappers) do
            entry.fs:SetWidth(math.max(120, width - entry.inset))
        end
    end

    -- Header ---------------------------------------------------------------
    local title = NewText(content, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    title:SetText(L("PANEL_TITLE"))
    title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    y = y - 30

    local subtitle = NewText(content, "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    subtitle:SetJustifyH("LEFT")
    WrapToWidth(subtitle)
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
    -- Tall enough for the field rows plus two wrapped lines each for the formula,
    -- the sample note and the state hint.
    local cardHeight = 224
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

    -- Fixed line slots, each sized for up to two wrapped lines. They used to be
    -- 18 px apart, which was fine while every string was short; the moment one
    -- wrapped (measured in-game) the two lines were drawn on top of each other.
    local sampledLine = NewText(card, "GameFontNormalSmall")
    sampledLine:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -130)
    sampledLine:SetWidth(INNER_WIDTH - 28)
    sampledLine:SetJustifyH("LEFT")
    EnableWrap(sampledLine)
    sampledLine:SetTextColor(1, 1, 1, 0.40)

    local hintLine = NewText(card, "GameFontNormalSmall")
    hintLine:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -166)
    hintLine:SetWidth(INNER_WIDTH - 28)
    hintLine:SetJustifyH("LEFT")
    EnableWrap(hintLine)
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

    -- Display ---------------------------------------------------------------
    -- That is the whole panel: the algorithm configures itself, so the only
    -- thing left for the player to decide is whether the readout is drawn.
    local row
    row, y = AddToggle(content, y, "SETTING_SHOW_STATUS",
        function() return Cfg().showStatus end,
        function(value)
            Core.SetConfig("showStatus", value, { noRefresh = true })
            CreateStatusBar()
            ApplyStatusBarVisibility()
        end)

    do
        local positionRow
        positionRow, y = AddRow(content, y, 30)
        local positionButton = NewButton(positionRow, 180, 24, L("BUTTON_RESET_POSITION"))
        positionButton:SetPoint("LEFT", 12, 0)
        AttachTooltip(positionButton, L("BUTTON_RESET_POSITION"), L("TOOLTIP_RESET_POSITION"))
        positionButton:SetScript("OnClick", function() ResetStatusBarPosition(true) end)
    end

    local footer = NewText(content, "GameFontNormalSmall")
    footer:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y - 6)
    footer:SetJustifyH("LEFT")
    WrapToWidth(footer, 4)
    footer:SetTextColor(1, 1, 1, 0.40)
    footer:SetText(L("PANEL_FOOTER"))
    y = y - 6 - math.max(16, footer:GetStringHeight() or 16) - 8

    ApplyWrapWidths()
    SetContentHeight(content, -y + 6)
    built = true
    RefreshUI()

    -- Keep the wrapping strings in step with the viewport: the canvas sizes our
    -- frame only after it is shown, and the player can resize the window.
    scroll:HookScript("OnSizeChanged", function(_, width)
        if (width or 0) > 0 then ApplyWrapWidths() end
    end)
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

    -- No scroll frame of its own: BuildUI owns one for every host, so nesting
    -- two of them would fight over the same content height.
    local body = CreateFrame("Frame", nil, window)
    body:SetPoint("TOPLEFT", 8, -44)
    body:SetPoint("BOTTOMRIGHT", -8, 10)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "AutoSpellQueueOptionsFrame")
    end

    window:HookScript("OnShow", MarkPanelVisible)
    window:Hide()

    standalone = window
    host = body
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
    -- Same rule as the status card: prefer the live read, fall back to the
    -- snapshot, and never invent a number. The sample age is printed below so
    -- "current" and "target" are not read as if they were taken together.
    if status.live ~= nil then
        Add("LABEL_CURRENT", MsText(status.live))
    else
        Add("LABEL_CURRENT", MsText(status.current))
    end
    Add("LABEL_TARGET", MsText(status.target))
    Add("LABEL_BASE", MsText(status.base))
    Add("LABEL_LATENCY", MsText(status.latency))
    Add("LABEL_WORLD", MsText(status.world))
    Add("LABEL_HOME", MsText(status.home))
    -- 算法自己决定的量：报 bug 时这两行走查「为什么是这个数」。
    Add("LABEL_MARGIN", MsText(status.margin))
    Add("LABEL_JITTER", MsText(status.jitter))
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
    -- 采样策略：让玩家能看到「它没有在一直轮询」。
    Add("LABEL_CADENCE", CadenceText(status))
    if NumText(status.cachedLatency) then
        Add("LABEL_CACHED_LATENCY", MsText(status.cachedLatency))
    end
    -- "target / latency are a sample of the last computation" - with its age,
    -- so a bug report can tell a fresh value from a stale one.
    lines[#lines + 1] = SampledText(status)
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
    if string.sub(command, 1, 4) == "base" then
        -- Escape hatch for the rare spec where the table's feel value is wrong.
        -- Deliberately command-only: it must not become a panel setting again.
        local argument = string.gsub(string.sub(command, 5), "^%s+", "")
        if argument == "" then
            local current = Core.GetConfig().baseOverride
            if current then
                Say(Format("CHAT_BASE_CURRENT", current))
            else
                Say(L("CHAT_BASE_AUTO"))
            end
            return
        end
        if argument == "auto" then
            Core.SetBaseOverride(nil)
            Say(L("CHAT_BASE_AUTO"))
            return
        end
        -- Must be validated here: tonumber("abc") is nil, and nil means "auto"
        -- to SetBaseOverride, so passing it through would silently reset the
        -- override instead of telling the player the input was wrong.
        local numeric = tonumber(argument)
        if numeric == nil then
            Say(L("CHAT_BASE_INVALID"))
            return
        end
        local ok = Core.SetBaseOverride(numeric)
        if ok then
            Say(Format("CHAT_BASE_SET", NumText(Core.GetConfig().baseOverride) or 0))
        else
            Say(L("CHAT_BASE_INVALID"))
        end
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

--- Runs one setup step in isolation.
--  A single broken surface must never take the rest of the UI down with it -
--  that is exactly how a font error once left the player with no panel, no bar
--  and no message. Failures are reported in chat instead of vanishing.
local function TryStep(stepName, fn)
    local ok, err = pcall(fn)
    if not ok then
        Say(Format("MSG_UI_STEP_FAILED", stepName, tostring(err)))
        if type(print) == "function" then
            print("AutoSpellQueue: UI step '" .. tostring(stepName) .. "' failed: " .. tostring(err))
        end
    end
    return ok
end

local function Setup()
    if initialized then return end
    initialized = true
    TryStep("state", PullState)
    TryStep("slash", RegisterSlashCommands)

    -- Panel first: it is the surface players go looking for, so it must not
    -- depend on the status bar being constructible.
    if not TryStep("panel", TryCreateSettingsCategory) then
        TryStep("standalone", CreateStandaloneWindow)
    end

    TryStep("statusbar", function()
        CreateStatusBar()
        ApplyStatusBarVisibility()
    end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "PLAYER_SPECIALIZATION_CHANGED", "ZONE_CHANGED_NEW_AREA", "CVAR_UPDATE",
}) do
    -- One bad event name must not stop the others (and must not abort the file
    -- before the Options table below is exported).
    local ok, err = pcall(events.RegisterEvent, events, event)
    if not ok and type(print) == "function" then
        print("AutoSpellQueue: cannot register event " .. event .. ": " .. tostring(err))
    end
end

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
