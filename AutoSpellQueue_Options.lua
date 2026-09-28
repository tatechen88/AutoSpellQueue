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

--- Colour of the NUMBER the addon is managing, by connection quality:
---   good/normal -> white (nothing to look at, which is the point)
---   too high    -> red   (clearly worse than this connection's usual)
--- Failure states keep their own colour: they are not about latency.
local QUALITY_COLOR = {
    good    = { 1.00, 1.00, 1.00 },
    unknown = { 1.00, 1.00, 1.00 },
    high    = { 0.95, 0.35, 0.35 },
}

--- The colour to draw a managed value with, given the state it is in.
local function ValueColor(state, status)
    if state == "applied" then
        return QUALITY_COLOR[status.latencyQuality] or QUALITY_COLOR.good
    end
    return STATE_COLOR[state] or STATE_COLOR.idle
end

local PANEL_WIDTH = 640
local PANEL_PAD = 16
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

--- Tooltip helper, same approach as the sibling addon StockTake.
--  Title/body may be strings or functions (for live text). SetScript (not
--  HookScript) takes the event over from the template's DefaultTooltipMixin,
--  whose OnEnter would otherwise show a bright HoverBackground on the dark
--  settings page and pop its own tooltip.
local function AttachTooltip(frame, title, body)
    if frame.HoverBackground then frame.HoverBackground:Hide() end
    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local titleText = type(title) == "function" and title() or title
        local bodyText = type(body) == "function" and body() or body
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if titleText then GameTooltip:AddLine(titleText, 1, 1, 1, true) end
        if bodyText then GameTooltip:AddLine(bodyText, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
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
--  Status bar
-------------------------------------------------------------------------------
local statusBar
local OpenOptions   -- forward declaration: the panel section defines it below

local function StatusBarVisual(status)
    local state = ResolveState(status)
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
    -- The number itself is colour coded by the connection: white while latency is
    -- what this machine normally sees, red once it is clearly worse. Failure and
    -- waiting states keep their own colour - those are not latency problems.
    return text, ValueColor(state, status), state
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
    -- 为什么这个是红的：说清「比平时高多少」，否则红色只是个谜。
    if state == "applied" and status.latencyQuality == "high" then
        local normal = NumText(status.latencyNormal)
        local reading = NumText(status.latency) or 0
        local line
        if normal then
            line = Format("HINT_LATENCY_HIGH", reading, normal)
        else
            line = Format("HINT_LATENCY_HIGH_NO_BASE", reading, NumText(status.latencyHighAt) or 0)
        end
        GameTooltip:AddLine(line, QUALITY_COLOR.high[1], QUALITY_COLOR.high[2],
            QUALITY_COLOR.high[3], true)
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

--- Template introspection, exactly as the client exposes it (StockTake does the
--- same): prefer the modern settings templates, fall back on the older ones.
local function HasTemplate(name)
    local util = C_XMLUtil
    if not (util and util.GetTemplateInfo) then return false end
    local ok, info = pcall(util.GetTemplateInfo, name)
    return ok and info ~= nil
end

local CHECKBOX_TEMPLATE = HasTemplate("SettingsCheckboxTemplate")
    and "SettingsCheckboxTemplate" or "InterfaceOptionsCheckButtonTemplate"
local BUTTON_TEMPLATE = HasTemplate("UIPanelButtonTemplate")
    and "UIPanelButtonTemplate" or "UIPanelButtonTemplate"

--- Checkbox row in the style of the sibling addon StockTake: a Blizzard-native
--- checkbox plus OUR OWN anchored label.
--  Why our own label: SettingsCheckboxTemplate ships no text element, so
--  Button:SetText creates an unanchored FontString - the API reads it back fine
--  while nothing is drawn on screen. (Trap documented in StockTake's source.)
local function AddCheckbox(parent, y, labelKey, get, set, tooltip)
    local checkbox = CreateFrame("CheckButton", nil, parent, CHECKBOX_TEMPLATE)
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)

    local label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    label:SetJustifyH("LEFT")
    label:SetText(L(labelKey))

    checkbox:SetChecked(get() and true or false)
    checkbox:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        RefreshUI()
    end)
    AttachTooltip(checkbox, L(labelKey), tooltip)
    AddUpdater(function()
        checkbox:SetChecked(get() and true or false)
    end)
    return checkbox
end

--- Native button (Blizzard art, no custom drawing).
--  It needs a GLOBAL NAME: UIPanelButtonTemplate's `$parentText` child only
--  exists when the control has a name to expand from, and an unnamed template
--  button silently ends up with an unanchored, invisible label.
local function AddButton(parent, y, labelKey, onClick, tooltip, width)
    local button = CreateFrame("Button", "AutoSpellQueueResetButton", parent, BUTTON_TEMPLATE)
    button:SetSize(width or 140, 22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    button:SetText(L(labelKey))
    button:SetScript("OnClick", onClick)
    AttachTooltip(button, L(labelKey), tooltip)
    return button
end

local function BuildUI(contentParent)
    -- Layout follows the sibling addon StockTake (same author, same client):
    -- native Blizzard controls anchored straight to the panel, no scroll frame,
    -- no custom borders or backgrounds, one line of status text under the title.
    -- Keeping both settings pages the same means players learn one layout.
    local panel = contentParent

    -- Throttled refresh ticker for the panel. It is a child of the panel on
    -- purpose: the client does not call OnUpdate on a frame whose parent is
    -- hidden, so this costs nothing while the settings page is closed.
    local poller = CreateFrame("Frame", nil, panel)
    poller:SetAllPoints(panel)
    local pollAccum = 0
    poller:SetScript("OnUpdate", function(_, elapsed)
        pollAccum = pollAccum + (elapsed or 0)
        if pollAccum < POLL_INTERVAL then return end
        pollAccum = 0
        RefreshUI()
    end)

    local y = -16

    -- Title ------------------------------------------------------------------
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    title:SetText(L("PANEL_TITLE"))
    y = y - 24

    -- One status line --------------------------------------------------------
    -- It lives in a mouse-enabled frame so it can carry the tooltip with the
    -- long explanation (a FontString cannot receive mouse events).
    local statusRow = CreateFrame("Frame", nil, panel)
    statusRow:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    statusRow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, y)
    statusRow:SetHeight(18)
    statusRow:EnableMouse(true)

    local statusLine = statusRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusLine:SetPoint("LEFT", 0, 0)
    statusLine:SetJustifyH("LEFT")
    statusLine:SetText(L("STATE_IDLE"))
    AttachTooltip(statusRow, L("PANEL_TITLE"), function()
        local status = refreshStatus or Core.GetStatus()
        return table.concat({
            L("PANEL_SUBTITLE"),
            FormulaText(refreshCfg, status),
            SampledText(status),
            L("PANEL_FOOTER"),
        }, "\n")
    end)

    AddUpdater(function()
        local status = refreshStatus
        local state = ResolveState(status)
        -- Same colour rule as the floating bar: a managed number is white while
        -- the connection is normal and red once it is clearly worse.
        local color = ValueColor(state, status)
        local current = EffectiveCurrent(status)

        -- Short by design: state, and the number only when the addon really is
        -- managing it (never show a believable number for a value we do not own).
        local text = StateLabel(state)
        if current ~= nil and state ~= "disabled" and state ~= "error"
            and state ~= "unavailable" then
            text = text .. " · " .. Format("UNIT_MS", current)
        end
        if status.externalChange then
            text = text .. " · " .. L("HINT_EXTERNAL_CHANGE")
        end
        statusLine:SetText(text)
        statusLine:SetTextColor(color[1], color[2], color[3])
    end)

    -- Controls ---------------------------------------------------------------
    AddCheckbox(panel, -78, "SETTING_ENABLED",
        function() return Core.IsEnabled() end,
        function(value) Core.SetEnabled(value) end,
        L("SETTING_ENABLED_HINT"))

    AddCheckbox(panel, -110, "SETTING_SHOW_STATUS",
        function() return Cfg().showStatus end,
        function(value)
            Core.SetConfig("showStatus", value, { noRefresh = true })
            CreateStatusBar()
            ApplyStatusBarVisibility()
        end,
        L("TOOLTIP_STATUS_BAR"))

    AddButton(panel, -146, "BUTTON_RESET_POSITION",
        function() ResetStatusBarPosition(true) end,
        L("TOOLTIP_RESET_POSITION"))

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
    if not host then return end
    -- A build failure used to leave a half-built (or blank) page with no
    -- explanation - the worst possible outcome. Report it the same way Setup
    -- reports its steps, and keep the message reachable for diagnostics.
    local ok, err = pcall(BuildUI, host)
    if not ok then
        _G.ASQ_BUILD_ERROR = tostring(err)
        Say(Format("MSG_UI_STEP_FAILED", "panel-content", tostring(err)))
        if type(print) == "function" then
            print("AutoSpellQueue: panel build failed: " .. tostring(err))
        end
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
