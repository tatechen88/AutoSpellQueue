------------------------------------------------------------------------------
--  tests/spec_options.lua -- ns.Options (settings panel, status bar, slash)
--
--  The Options file is the only part of the addon a player ever sees, so these
--  tests drive it the way the client does: build the tree once, then click the
--  real OnClick handlers, fire the real OnUpdate tickers (through the stub's
--  visibility rule) and read the real OnShow/OnDragStop handlers. Nothing is
--  re-implemented here - if a handler stops writing to Core, the test goes red.
--
--  Covered:
--    * the panel builds without errors and is built exactly once;
--    * master switch / status card / advanced fold exist and are wired;
--    * toggles, steppers and cycle buttons really write Core's config;
--    * the status card and the status bar text for every core state;
--    * a rejected write is shown as an error, never as a plausible number;
--    * dragging the status bar persists statusBarPos (and clamps it);
--    * the four slash commands (open / status / reset / unlock) plus help;
--    * hidden surfaces are not polled (the engine only calls OnUpdate on
--      visible frames, which the stub models).
------------------------------------------------------------------------------
local T, ns, Stub = ...
local Core = ns.Core
local Options = ns.Options

T.spec("spec_options")

if type(Options) ~= "table" then
    T.test("ns.Options 已加载", function()
        T.truthy(false, "AutoSpellQueue_Options.lua 没有设置 ns.Options")
    end)
    return
end

------------------------------------------------------------------------------
--  World / status helpers
------------------------------------------------------------------------------

local function defaultDB(extra)
    local db = {
        enabled = true, baseMode = "auto", adaptive = true, latencySource = "world",
        margin = 50, minWindow = 50, maxWindow = 400, hysteresis = 10,
        showStatus = true, chatFeedback = false, showAdvanced = false,
    }
    for key, value in pairs(extra or {}) do db[key] = value end
    return db
end

local function resetWorld(extra)
    Stub.Reset()
    Core.StopTicker()
    _G.AutoSpellQueueDB = defaultDB(extra)
    _G.Tate_ASQDB = nil
    Core.db = nil
    Core.inWorld = true
    Core.state = Core.STATE.IDLE
    Core.stateReason = nil
    Core.externalChange = false
    Core.lastTarget = nil
    Core.lastSnapshot = nil
    Core.lastReason = nil
    local cfg = Core.GetConfig()
    -- Drop the panel's cached cfg/status so every test starts from this world.
    if Options.Refresh then Options.Refresh() end
    return cfg
end

T.beforeEach(function() resetWorld() end)

--- A complete synthetic status table (the shape documented in ARCHITECTURE §4).
--  nilKeys lets a case clear fields that must be absent (pairs() cannot set nil).
local function FakeStatus(overrides)
    overrides = overrides or {}
    local status = {
        enabled = true, state = "applied", stateReason = nil, stateReasonKey = nil,
        current = 245, target = 245, baseline = nil, lastApplied = 245, owned = true,
        inCombat = false, inWorld = true, context = "world", role = "ranged", base = 245,
        latency = 100, home = 20, world = 100, specID = 63, specName = "Fire",
        classFile = "MAGE", cvarInfo = { known = true }, lastError = nil, lastErrorAt = nil,
        applyCount = 1, repairs = 0, externalChange = false, schemaFuture = false,
        importedFrom = nil, refreshSeconds = 15, reason = "test", live = 245,
        snapshotAt = Stub.now,
    }
    for key, value in pairs(overrides) do status[key] = value end
    for _, key in ipairs(overrides.nilKeys or {}) do status[key] = nil end
    status.nilKeys = nil
    return status
end

--- Runs fn with Core.GetStatus replaced. Restores even when fn raises.
local function WithStatus(status, fn)
    local saved = Core.GetStatus
    Core.GetStatus = function() return status end
    local ok, err = pcall(fn)
    Core.GetStatus = saved
    if not ok then error(err, 0) end
end

--- Mirrors Options' LocalizedFormat(): use the locale pattern when it carries a
--- placeholder, otherwise the "%d ms" fallback.
local function ExpectedMs(value)
    local pattern = Core.L("UNIT_MS")
    if type(pattern) == "string" and pattern ~= "UNIT_MS" and string.find(pattern, "%%") then
        return pattern:format(value)
    end
    return ("%d ms"):format(value)
end

------------------------------------------------------------------------------
--  Widget lookup (by the labels the panel itself renders)
------------------------------------------------------------------------------

local function FindFontStringWithText(text)
    return Stub.FindWidget(function(widget)
        return widget.__kind == "FontString" and widget.text == text
    end)
end

local function RowOf(key)
    local label = FindFontStringWithText(Core.L(key))
    return label and label.parent or nil
end

local function ButtonsIn(row)
    if not row then return {} end
    return Stub.FindWidgets(function(widget)
        return widget.__kind == "Button" and widget.parent == row
    end)
end

local function SwitchOf(key)
    for _, button in ipairs(ButtonsIn(RowOf(key))) do
        if button._track then return button end
    end
    return nil
end

--- Returns minus, plus for a stepper row (identified by their label text).
local function StepperOf(key)
    local minus, plus
    for _, button in ipairs(ButtonsIn(RowOf(key))) do
        local text = button._text and button._text.text
        if text == "-" then minus = button elseif text == "+" then plus = button end
    end
    return minus, plus
end

local function CycleOf(key)
    return ButtonsIn(RowOf(key))[1]
end

local function FindButtonByText(text)
    return Stub.FindWidget(function(widget)
        return widget.__kind == "Button" and widget._text and widget._text.text == text
    end)
end

--- Any font string whose rendered text contains `needle` (plain find, no patterns).
local function FindFontStringContaining(needle)
    if type(needle) ~= "string" or needle == "" then return nil end
    return Stub.FindWidget(function(widget)
        return widget.__kind == "FontString" and type(widget.text) == "string"
            and string.find(widget.text, needle, 1, true) ~= nil
    end)
end

local function Click(widget)
    T.notNil(widget, "控件不存在，无法点击")
    local handler = widget.__scripts and widget.__scripts.OnClick
    T.notNil(handler, "控件缺少 OnClick 处理器")
    handler(widget, "LeftButton", false)
end

--- The status card badge: the only widget the card updater marks with _title.
local function Badge()
    return Stub.FindWidget(function(widget) return widget._title ~= nil end)
end

local function BadgeText(badge)
    if not badge then return nil end
    return Stub.FindWidget(function(widget)
        return widget.__kind == "FontString" and widget.parent == badge
    end)
end

--- The card's "current" value line: it is created directly after the label that
--- carries LABEL_CURRENT, inside the same card frame.
local function CardCurrentValue()
    local label = FindFontStringWithText(Core.L("LABEL_CURRENT"))
    if not label then return nil end
    local widgets = Stub.Widgets()
    local start = Stub.WidgetIndex(label)
    for index = start + 1, #widgets do
        local widget = widgets[index]
        if widget.__kind == "FontString" and widget.parent == label.parent then
            return widget
        end
    end
    return nil
end

local function StatusBar()
    return Stub.FindFrame("AutoSpellQueueStatusBar")
end

local function Panel()
    return Stub.FindFrame("AutoSpellQueueOptionsPanel")
end

local function AdvancedFrame()
    local row = RowOf("SETTING_BASE_MODE")
    return row and row.parent or nil
end

------------------------------------------------------------------------------
--  Boot: bring the addon up the way the client does, once for the whole spec
------------------------------------------------------------------------------

local booted = false

local function Boot()
    if booted then return end
    booted = true
    resetWorld()
    -- Options initialises on the first ADDON_LOADED / PLAYER_LOGIN it sees.
    -- Both are idempotent (Setup guards itself), so firing them here is safe
    -- even when an earlier spec already triggered it.
    Stub.FireEvent("PLAYER_LOGIN")
    Options.Build()
    local panel = Panel()
    if panel then panel:Show() end -- OnShow -> MarkPanelVisible -> RefreshUI
end

------------------------------------------------------------------------------
--  Build
------------------------------------------------------------------------------

T.test("Boot: 面板、状态条、主区域控件都建起来了，且没有报错", function()
    Boot()
    local panel = Panel()
    T.notNil(panel, "设置分类面板 AutoSpellQueueOptionsPanel 应已创建")
    T.notNil(StatusBar(), "状态条 AutoSpellQueueStatusBar 应已创建")
    T.notNil(Stub.settingsCalls.registerCanvas, "应调用 Settings.RegisterCanvasLayoutCategory")
    T.notNil(Stub.settingsCalls.registerAddOn, "应调用 Settings.RegisterAddOnCategory")

    T.notNil(RowOf("SETTING_ENABLED"), "主区域应有总开关行")
    T.notNil(SwitchOf("SETTING_ENABLED"), "总开关行应有开关控件")
    T.notNil(Badge(), "状态卡徽标应存在（总开关之下）")
    T.notNil(BadgeText(Badge()), "徽标应有文字")
    T.notNil(CardCurrentValue(), "状态卡应有当前值一行")

    local fold = FindButtonByText(Core.L("ADVANCED_SHOW"))
    T.notNil(fold, "应有高级折叠按钮")
    T.notNil(AdvancedFrame(), "高级区域框架应存在")

    Options.Refresh()
    T.notNil(Badge(), "刷新后徽标仍应存在")
    T.truthy(Badge()._title ~= nil, "刷新后徽标应有状态标题")
end)

T.test("UI 只构建一次：重复 Build / Refresh 不再新建控件", function()
    Boot()
    local count = #Stub.Widgets()
    Options.Build()
    Options.Build()
    Options.Refresh()
    Options.Refresh()
    T.eq(#Stub.Widgets(), count, "控件树不得重建（文档：built once, only refreshed）")
end)

------------------------------------------------------------------------------
--  Widgets really write Core's config
------------------------------------------------------------------------------

T.test("总开关：点击写入 Core.SetEnabled（真实配置）", function()
    Boot()
    resetWorld({ enabled = true })
    Options.Refresh()
    T.truthy(Core.GetConfig().enabled)

    local switch = SwitchOf("SETTING_ENABLED")
    Click(switch)
    T.falsy(Core.GetConfig().enabled, "点击后配置里的 enabled 应为 false")
    T.falsy(Core.IsEnabled())

    Click(switch)
    T.truthy(Core.GetConfig().enabled, "再点一次应回到 true")
end)

T.test("高级开关：点击写入 Core 配置（adaptive / chatFeedback）", function()
    Boot()
    resetWorld({ adaptive = true, chatFeedback = false })
    Options.Refresh()

    Click(SwitchOf("SETTING_ADAPTIVE"))
    T.falsy(Core.GetConfig().adaptive, "ADAPTIVE 开关应写入 adaptive=false")

    Click(SwitchOf("SETTING_CHAT_FEEDBACK"))
    T.truthy(Core.GetConfig().chatFeedback, "CHAT_FEEDBACK 开关应写入 chatFeedback=true")

    -- 显示状态条开关有副作用：真的 Show/Hide 状态条
    local bar = StatusBar()
    bar:Show()
    Click(SwitchOf("SETTING_SHOW_STATUS"))
    T.falsy(Core.GetConfig().showStatus)
    T.falsy(bar:IsShown(), "关掉开关后状态条必须隐藏")
    Click(SwitchOf("SETTING_SHOW_STATUS"))
    T.truthy(bar:IsShown(), "重新打开后状态条必须显示")
end)

T.test("步进控件：+/- 写入 Core 配置并被 Core 夹紧", function()
    Boot()
    resetWorld({ margin = 50, hysteresis = 10 })
    Options.Refresh()

    local minus, plus = StepperOf("SETTING_MARGIN")
    T.notNil(minus, "margin 行应有 [-] 按钮")
    T.notNil(plus, "margin 行应有 [+] 按钮")

    Click(plus)
    T.eq(Core.GetConfig().margin, 55, "margin 应 +5")
    Click(minus)
    Click(minus)
    T.eq(Core.GetConfig().margin, 45, "margin 应 -10")

    -- 上限由 Core.Sanitize 保证（Options 自己也夹一层）
    Core.SetConfig("margin", 300, { noRefresh = true })
    Options.Refresh()
    Click(plus)
    T.eq(Core.GetConfig().margin, 300, "超过上限必须被夹回 300")

    -- 步长 1 的控件
    local hysteresisMinus, hysteresisPlus = StepperOf("SETTING_HYSTERESIS")
    Click(hysteresisPlus)
    T.eq(Core.GetConfig().hysteresis, 11, "hysteresis 步长应为 1")
    Click(hysteresisMinus)
    T.eq(Core.GetConfig().hysteresis, 10)
end)

T.test("循环控件：baseMode 两档回绕、latencySource 四档回绕", function()
    Boot()
    resetWorld({ baseMode = "auto", latencySource = "world" })
    Options.Refresh()

    local baseMode = CycleOf("SETTING_BASE_MODE")
    Click(baseMode)
    T.eq(Core.GetConfig().baseMode, "manual")
    Click(baseMode)
    T.eq(Core.GetConfig().baseMode, "auto", "两档控件应回绕到起点")

    local latency = CycleOf("SETTING_LATENCY_SOURCE")
    local seen = {}
    for _ = 1, 4 do
        Click(latency)
        seen[Core.GetConfig().latencySource] = true
    end
    T.eq(Core.GetConfig().latencySource, "world", "转一圈应回到 world")
    for _, value in ipairs({ "home", "avg", "max" }) do
        T.truthy(seen[value], "latencySource 应能循环到 " .. value)
    end
end)

T.test("高级折叠：点击写入 showAdvanced 并真的显示/隐藏高级区域", function()
    Boot()
    resetWorld({ showAdvanced = false })
    Options.Refresh()

    local advanced = AdvancedFrame()
    local fold = FindButtonByText(Core.L("ADVANCED_SHOW"))
    T.notNil(fold, "折叠按钮文案应为 ADVANCED_SHOW")
    T.falsy(advanced:IsShown(), "默认收起")

    Click(fold)
    T.truthy(Core.GetConfig().showAdvanced, "点击应写入 showAdvanced=true")
    T.truthy(advanced:IsShown(), "展开后高级区域必须可见")
    Options.Refresh()
    T.eq(FindButtonByText(Core.L("ADVANCED_HIDE")) ~= nil, true, "展开后按钮文案应变为 ADVANCED_HIDE")

    Click(fold)
    T.falsy(Core.GetConfig().showAdvanced)
    T.falsy(advanced:IsShown(), "再次点击应收起")
end)

T.test("重置按钮：两段确认，4 秒后经 C_Timer 自动解除", function()
    Boot()
    resetWorld({ margin = 200 })
    Options.Refresh()

    local resetButton = FindButtonByText(Core.L("BUTTON_RESET_SETTINGS"))
    T.notNil(resetButton, "应有重置设置按钮")

    Click(resetButton)
    T.eq(resetButton._text.text, Core.L("BUTTON_RESET_SETTINGS_CONFIRM"), "第一次点击进入确认态")
    T.eq(Core.GetConfig().margin, 200, "第一次点击不得真的重置")

    Stub.Advance(5) -- 确认态 4 秒后由 C_Timer 解除
    T.eq(resetButton._text.text, Core.L("BUTTON_RESET_SETTINGS"), "超时后应回到初始文案")

    Click(resetButton)
    Click(resetButton)
    T.eq(Core.GetConfig().margin, 50, "第二次确认应调用 Core.ResetSettings")
    T.truthy(Stub.ChatContains(Core.L("MSG_RESET_DONE")))
end)

------------------------------------------------------------------------------
--  Status card and status bar text
------------------------------------------------------------------------------

local STATE_CASES = {
    {
        name = "applied", state = "applied", label = "STATE_APPLIED", hint = "HINT_APPLIED",
        live = 245, number = 245,
    },
    {
        name = "pending", state = "pending", label = "STATE_PENDING", hint = "HINT_PENDING",
        live = 245, number = 245, extra = { inCombat = true },
    },
    {
        -- Regression: disabling in combat defers the restore, so the panel and
        -- the bar must show "waiting" - not a plain "off". The docs promise it.
        name = "disabled+pending (combat)", state = "pending", label = "STATE_PENDING",
        hint = "HINT_PENDING", live = 245, number = 245,
        extra = { enabled = false, owned = true, baseline = 150, inCombat = true },
    },
    {
        name = "disabled", state = "disabled", label = "STATE_DISABLED", hint = "HINT_DISABLED",
        live = 150, number = 150, extra = { enabled = false, owned = false, baseline = nil },
    },
    {
        name = "disabled+owned", state = "disabled", label = "STATE_DISABLED",
        hint = "HINT_DISABLED_OWNED", live = 150, number = 150,
        extra = { enabled = false, owned = true, baseline = 150 },
    },
    {
        name = "error", state = "error", label = "STATE_ERROR", hint = "HINT_ERROR",
        live = 150, number = 150,
        extra = { stateReason = "rejected", stateReasonKey = "ERR_REJECTED", lastError = "rejected" },
    },
    {
        name = "unavailable", state = "unavailable", label = "STATE_UNAVAILABLE",
        hint = "HINT_UNAVAILABLE", live = nil, number = nil,
        extra = { stateReason = "unavailable", stateReasonKey = "ERR_UNAVAILABLE" },
        nilKeys = { "live", "current", "lastApplied", "target" },
    },
}

T.test("状态卡：六种状态各自的徽标/提示/当前值分支", function()
    Boot()
    local badge = Badge()
    local badgeText = BadgeText(badge)
    local currentValue = CardCurrentValue()
    T.notNil(badgeText)
    T.notNil(currentValue)

    for _, case in ipairs(STATE_CASES) do
        local overrides = { state = case.state, live = case.live }
        for key, value in pairs(case.extra or {}) do overrides[key] = value end
        overrides.nilKeys = case.nilKeys

        WithStatus(FakeStatus(overrides), function()
            Options.Refresh()

            T.eq(badgeText.text, Core.L(case.label), "[" .. case.name .. "] 徽标文案")
            T.truthy(type(badge._body) == "string" and #badge._body > 0,
                "[" .. case.name .. "] 徽标应带解释文字")
            T.contains(badge._body, string.sub(Core.L(case.hint), 1, 8),
                "[" .. case.name .. "] 提示应来自 " .. case.hint)

            if case.number ~= nil then
                T.eq(currentValue.text, ExpectedMs(case.number),
                    "[" .. case.name .. "] 当前值显示真实读到的数字")
            else
                T.eq(currentValue.text, Core.L("VALUE_UNAVAILABLE"),
                    "[" .. case.name .. "] 读不到值时不得编造数字")
            end
        end)
    end
end)

T.test("状态卡：写入失败的 error 优先于 disabled（失败必须让玩家看见）", function()
    Boot()
    local badgeText = BadgeText(Badge())
    WithStatus(FakeStatus({
        enabled = false, state = "error", stateReasonKey = "ERR_VERIFY",
        live = nil, current = nil, lastApplied = nil, target = nil, baseline = nil,
        nilKeys = { "live", "current", "lastApplied", "target", "baseline" },
    }), function()
        Options.Refresh()
        T.eq(badgeText.text, Core.L("STATE_ERROR"),
            "关闭插件但写入失败时，必须显示 error 而不是 disabled")
        T.eq(CardCurrentValue().text, Core.L("VALUE_UNAVAILABLE"), "读不到值时给出 unavailable 文案")
    end)
end)

T.test("状态卡：错误提示里带可本地化的失败原因，不显示目标数字冒充结果", function()
    Boot()
    local badge = Badge()
    local currentValue = CardCurrentValue()
    local status = FakeStatus({
        state = "error", stateReason = "rejected", stateReasonKey = "ERR_REJECTED",
        lastError = "rejected", live = nil, current = nil, lastApplied = nil, target = 245,
        lastErrorAt = Stub.now,
        nilKeys = { "live", "current", "lastApplied" },
    })
    WithStatus(status, function()
        Options.Refresh()
        T.contains(badge._body, Core.L("ERR_REJECTED"), "提示必须写出失败原因")
        T.ne(currentValue.text, ExpectedMs(245), "绝不能把目标值当成当前值显示")
        T.eq(currentValue.text, Core.L("VALUE_UNAVAILABLE"))
    end)
end)

T.test("状态条：error / unavailable / disabled 只显示状态名，绝不显示数字", function()
    Boot()
    local bar = StatusBar()
    bar:Show()

    local function BarTextFor(overrides)
        local text
        WithStatus(FakeStatus(overrides), function()
            bar._accum = 0
            Stub.FireUpdate(1.0)
            text = bar._text.text
        end)
        return text
    end

    local errorText = BarTextFor({ state = "error", live = 150, stateReasonKey = "ERR_REJECTED" })
    T.eq(errorText, Core.L("STATE_ERROR"))
    T.isNil(string.find(errorText, "%d"), "error 状态下状态条不得出现数字")

    T.eq(BarTextFor({ state = "unavailable", live = nil, nilKeys = { "live" } }),
        Core.L("STATE_UNAVAILABLE"))
    T.eq(BarTextFor({ enabled = false, state = "disabled", live = 150 }), Core.L("STATE_DISABLED"))

    -- 关闭中但战斗未结束：归还被推迟，值仍归插件管，所以显示数字（等待色），
    -- 绝不能显示成「已关闭」——那会让玩家以为值已经被还回去了。
    T.eq(BarTextFor({ enabled = false, state = "pending", live = 245 }), ExpectedMs(245),
        "关闭中等待脱战：状态条显示数字而非「已关闭」")

    T.eq(BarTextFor({ state = "applied", live = 245 }), ExpectedMs(245), "正常状态才显示数字")
    -- 完全读不到值：连快照都是空的，才允许说 unavailable
    T.eq(BarTextFor({
        state = "applied", live = nil, current = nil, lastApplied = nil, target = nil,
        nilKeys = { "live", "current", "lastApplied", "target" },
    }), Core.L("VALUE_UNAVAILABLE"), "读不到值时不显示任何数字")
end)

T.test("P1 集成：真实写入被拒后，面板显示 error 且不冒充目标值", function()
    Boot()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Stub.setCVarMode = "reject-false"

    local ok = Core.Refresh("ui-test")
    T.falsy(ok, "前置条件：这次写入必须失败")
    T.eq(Core.state, Core.STATE.ERROR)
    T.eq(Stub.CVarValue(), "150", "客户端值未被改动")

    Options.Refresh()
    local badge = Badge()
    T.eq(BadgeText(badge).text, Core.L("STATE_ERROR"), "面板必须显示 error")
    T.contains(badge._body, Core.L("ERR_REJECTED"), "面板必须说明原因")

    local bar = StatusBar()
    bar:Show()
    bar._accum = 0
    Stub.FireUpdate(1.0)
    T.eq(bar._text.text, Core.L("STATE_ERROR"), "状态条在失败时不能显示数字")
    T.isNil(string.find(bar._text.text, "%d"))

    local currentText = CardCurrentValue().text
    T.eq(currentText, ExpectedMs(150), "当前值显示客户端真实值 150")
    T.ne(currentText, ExpectedMs(245), "绝不能显示目标值 245 冒充已应用")
end)

------------------------------------------------------------------------------
--  Status bar: drag & position
------------------------------------------------------------------------------

T.test("状态条拖动：落点写回 statusBarPos（noRefresh），并夹紧在屏幕内", function()
    Boot()
    resetWorld({ showStatus = true, statusBarPos = nil })
    Options.Refresh()

    local bar = StatusBar()
    bar:SetSize(100, 30)
    bar:Show()
    local dragStart = bar.__scripts.OnDragStart
    local dragStop = bar.__scripts.OnDragStop
    T.notNil(dragStart, "状态条必须能拖动")
    T.notNil(dragStop, "拖动结束必须保存位置")

    -- 客户端把窗口拖到 (300, 250)
    dragStart(bar)
    bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -250)
    dragStop(bar)

    local pos = Core.GetConfig().statusBarPos
    T.notNil(pos, "拖动结束后必须写入 statusBarPos")
    T.eq(pos.x, 300)
    T.eq(pos.y, -250)
    T.isNil(Core.lastReason, "保存位置不应触发 Core 刷新（noRefresh）")

    -- 越界拖动：客户端不会真的移出屏幕，但我们的夹紧逻辑必须兜住
    dragStart(bar)
    bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -500, -5000)
    dragStop(bar)
    local clamped = Core.GetConfig().statusBarPos
    T.eq(clamped.x, 0, "左边越界应夹到 0")
    T.eq(clamped.y, -(Stub.screenHeight - bar:GetHeight()), "上边越界应夹在屏幕内")
end)

T.test("修复: 状态条几何返回 NaN 时不得写出 NaN 坐标，更不得抛错", function()
    Boot()
    resetWorld({ showStatus = true, statusBarPos = nil })
    Options.Refresh()

    local bar = StatusBar()
    bar:SetSize(100, 30)
    bar:Show()
    local dragStop = bar.__scripts.OnDragStop
    T.notNil(dragStop, "拖动结束必须保存位置")

    -- 极端情况下客户端可能给出 NaN 几何；SetPoint 会原样收下。
    bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0 / 0, 0 / 0)
    local ok, err = pcall(dragStop, bar)
    T.truthy(ok, "拖动保存不得抛错（实得：" .. tostring(err) .. "）")

    local pos = Core.GetConfig().statusBarPos
    T.notNil(pos, "仍应写回一个坐标")
    T.eq(pos.x, pos.x, "x 必须是有限数字，不能是 NaN")
    T.eq(pos.y, pos.y, "y 必须是有限数字，不能是 NaN")
end)

T.test("状态条位置：下次登录按 statusBarPos 还原，解锁后回到默认锚点", function()
    Boot()
    resetWorld({ showStatus = true, statusBarPos = { x = 120, y = -240 } })
    Options.Refresh()

    local bar = StatusBar()
    bar:Show()
    -- ResetStatusBarPosition 会清掉记忆并重新应用默认锚点；先验证记忆生效
    T.eq(Core.GetConfig().statusBarPos.x, 120)

    Stub.chat = {}
    Options.ResetStatusBarPosition(true)
    T.isNil(Core.GetConfig().statusBarPos, "解锁应清掉位置记忆")
    local point, rel, relPoint, x, y = bar:GetPoint()
    T.eq(point, "TOP", "解锁后回到默认锚点")
    T.eq(rel, UIParent)
    T.eq(x, 0)
    T.eq(y, -140)
    T.truthy(Stub.ChatContains(Core.L("MSG_POSITION_RESET")), "解锁应给出反馈")
end)

T.test("状态条位置：关闭状态条时解锁会把它重新显示出来", function()
    Boot()
    resetWorld({ showStatus = false, statusBarPos = { x = 10, y = -10 } })
    local bar = StatusBar()
    bar:Hide()
    Stub.chat = {}

    Options.ResetStatusBarPosition(true)
    T.truthy(Core.GetConfig().showStatus, "解锁应把 showStatus 打开")
    T.truthy(bar:IsShown(), "解锁后状态条必须可见")
    T.truthy(Stub.ChatContains(Core.L("MSG_STATUS_BAR_SHOWN")))
end)

------------------------------------------------------------------------------
--  Slash commands
------------------------------------------------------------------------------

T.test("斜杠命令注册：/asq 与 /autospellqueue", function()
    Boot()
    T.eq(SLASH_AUTOSPELLQUEUE1, "/asq")
    T.eq(SLASH_AUTOSPELLQUEUE2, "/autospellqueue")
    T.eq(type(SlashCmdList["AUTOSPELLQUEUE"]), "function", "必须注册 SlashCmdList 处理器")
end)

T.test("斜杠 /asq：打开设置页（走 Settings 分类）", function()
    Boot()
    local slash = SlashCmdList["AUTOSPELLQUEUE"]
    local savedSettings = _G.Settings
    Stub.settingsCalls.openToCategory = {}

    slash("")
    T.eq(#Stub.settingsCalls.openToCategory, 1, "空参数应打开设置页")
    T.eq(Stub.settingsCalls.openToCategory[1], "AutoSpellQueue", "应打开本插件的分类")

    slash("  config  ")
    T.eq(#Stub.settingsCalls.openToCategory, 2, "参数两侧空白要容忍")
    slash("options")
    slash("settings")
    T.eq(#Stub.settingsCalls.openToCategory, 4)

    -- 客户端没有 Settings API 时：绝不能静默什么都不做
    Stub.RemoveSettings()
    T.notNil(Panel(), "面板框架本身仍在（分类注册是初始化时的事）")
    local ok = Options.Open()
    _G.Settings = savedSettings
    T.falsy(ok, "无法打开面板时必须返回 false")
end)

T.test("修复: 状态条字体串必须自带字体（客户端对无字体 FontString 调 SetText 会报错）", function()
    Boot()
    local bar = StatusBar()
    T.notNil(bar, "状态条必须建起来（构建失败会发生在这里）")
    local label = bar._text
    T.notNil(label, "状态条必须有文字对象")
    T.truthy(label.font ~= nil or label.fontObject ~= nil,
        "字体串必须已绑定字体；否则客户端会抛 FontString:SetText(): Font not set")
    T.truthy(type(label.text) == "string" and #label.text > 0, "应当已写入初始文本")
end)

T.test("修复: 上限低于 50ms 时必须给出警告（否则等于悄悄关掉施法队列）", function()
    Boot()
    resetWorld({ maxWindow = 400 })
    Options.Refresh()
    T.isNil(FindFontStringContaining(Core.L("HINT_MAX_TOO_LOW")), "正常上限不该出现警告")

    -- Sanitize 自己挡住了最常见的那条路：只调低上限、下限还是默认 50 → min>max
    -- → 两值双双复位，所以配置根本进不到公式里。
    resetWorld({ maxWindow = 30 })
    T.eq(Core.GetConfig().maxWindow, 400, "只调低上限会被 Sanitize 复位（min>max）")

    -- 真正够得着的情况：上下限都低于 50ms（手改存档或旧配置）。
    resetWorld({ minWindow = 10, maxWindow = 30 })
    Options.Refresh()
    T.eq(Core.GetConfig().maxWindow, 30, "一致的低区间应当被接受（不静默改写用户配置）")
    T.notNil(FindFontStringContaining(Core.L("HINT_MAX_TOO_LOW")),
        "上限 30ms 会让预输入时间几乎消失，必须警告而不是照做")
end)

T.test("斜杠 /asq status：输出诊断行（含状态、公式、CVar 信息）", function()
    Boot()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Core.Refresh("slash-status")
    Stub.chat = {}

    SlashCmdList["AUTOSPELLQUEUE"]("status")
    T.truthy(#Stub.chat >= 15, "status 应输出完整诊断（实得 " .. #Stub.chat .. " 行）")
    T.truthy(Stub.ChatContains(Core.L("LABEL_STATUS")), "应含状态标签")
    T.truthy(Stub.ChatContains(Core.L("LABEL_TARGET")), "应含目标值")
    T.truthy(Stub.ChatContains(Core.L("LABEL_FORMULA")), "应含计算式")
    T.truthy(Stub.ChatContains(Core.L("LABEL_CVAR")), "应含 CVar 元信息")
    T.truthy(Stub.ChatContains("inCombat="), "应含原始运行标志，便于报 bug")

    Stub.chat = {}
    SlashCmdList["AUTOSPELLQUEUE"]("diag")
    T.truthy(#Stub.chat >= 15, "diag 是 status 的别名")
end)

T.test("修复: 诊断里的「当前值」必须是实时读，且标注采样时间", function()
    Boot()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Core.Refresh("slash-status") -- 快照里 current = 150

    Stub.SetCVarValue(300) -- 外部改动，核心还没刷新：live=300 / current=150
    Stub.chat = {}
    SlashCmdList["AUTOSPELLQUEUE"]("status")

    local currentLine
    for _, line in ipairs(Stub.chat) do
        if string.find(line, Core.L("LABEL_CURRENT"), 1, true) then currentLine = line end
    end
    T.notNil(currentLine, "诊断必须含当前值行")
    T.contains(currentLine, ExpectedMs(300),
        "当前值必须是实时读到的 300（快照里仍是 150），否则报 bug 时会误导")

    local agePrefix = string.match(Core.L("HINT_SNAPSHOT_AGE"), "^(.-)%%d")
    T.truthy(agePrefix and Stub.ChatContains(agePrefix),
        "目标值/延迟是采样值，诊断必须标注采样时间")
end)

T.test("斜杠 /asq reset：恢复默认设置并反馈", function()
    Boot()
    resetWorld({ margin = 250, hysteresis = 50, adaptive = false })
    Stub.chat = {}

    SlashCmdList["AUTOSPELLQUEUE"]("reset")
    T.eq(Core.GetConfig().margin, 50, "reset 应恢复默认 margin")
    T.eq(Core.GetConfig().hysteresis, 10)
    T.eq(Core.GetConfig().adaptive, true)
    T.truthy(Stub.ChatContains(Core.L("MSG_RESET_DONE")))
end)

T.test("斜杠 /asq unlock：复位状态条位置（resetpos 同义）", function()
    Boot()
    resetWorld({ statusBarPos = { x = 200, y = -200 }, showStatus = true })
    Stub.chat = {}

    SlashCmdList["AUTOSPELLQUEUE"]("unlock")
    T.isNil(Core.GetConfig().statusBarPos)
    T.truthy(Stub.ChatContains(Core.L("MSG_POSITION_RESET")))

    Core.SetConfig("statusBarPos", { x = 50, y = -50 }, { noRefresh = true })
    SlashCmdList["AUTOSPELLQUEUE"]("resetpos")
    T.isNil(Core.GetConfig().statusBarPos, "resetpos 应与 unlock 等价")
end)

T.test("斜杠 /asq 未知参数：输出帮助（6 行），不静默", function()
    Boot()
    Stub.chat = {}
    SlashCmdList["AUTOSPELLQUEUE"]("definitely-not-a-command")
    T.eq(#Stub.chat, 6, "帮助应为 6 行（标题 + 四条命令 + 说明）")
    T.truthy(Stub.ChatContains(Core.L("SLASH_CMD_OPEN")))
    T.truthy(Stub.ChatContains(Core.L("SLASH_CMD_STATUS")))
    T.truthy(Stub.ChatContains(Core.L("SLASH_CMD_RESET")))
    T.truthy(Stub.ChatContains(Core.L("SLASH_CMD_UNLOCK")))
end)

------------------------------------------------------------------------------
--  Hidden surfaces are not polled
------------------------------------------------------------------------------

T.test("面板不可见时不刷新；重新显示时立刻刷新（OnShow + OnUpdate ticker）", function()
    Boot()
    resetWorld({ showStatus = true })
    local panel = Panel()
    local bar = StatusBar()
    T.notNil(panel)
    T.notNil(bar)

    local calls = 0
    local saved = Core.GetStatus
    Core.GetStatus = function()
        calls = calls + 1
        return saved()
    end

    local ok, err = pcall(function()
        panel:Show()
        bar:Show()
        Stub.FireUpdate(1.0) -- 先吃掉已累积的时间
        calls = 0
        Stub.FireUpdate(1.0)
        local visibleCalls = calls
        T.truthy(visibleCalls > 0, "可见时 OnUpdate 应驱动刷新")

        bar:Hide()
        calls = 0
        Stub.FireUpdate(1.0)
        T.truthy(calls > 0, "面板仍可见 -> ticker 继续刷新")
        T.truthy(calls < visibleCalls, "状态条隐藏后不应再有它的刷新")

        panel:Hide()
        calls = 0
        Stub.FireUpdate(5.0)
        T.eq(calls, 0, "面板与状态条都不可见时，一个刷新都不该发生")

        calls = 0
        panel:Show()
        T.truthy(calls > 0, "面板重新显示应立刻刷新一次（OnShow）")

        calls = 0
        Stub.FireUpdate(1.0)
        T.truthy(calls > 0, "显示后 ticker 恢复")
    end)

    Core.GetStatus = saved
    if not ok then error(err, 0) end
end)

T.test("状态条 tooltip：鼠标移入时把状态与当前值写进提示", function()
    Boot()
    resetWorld({ enabled = true, statusBarPos = nil })
    Options.Refresh()
    local bar = StatusBar()
    local onEnter = bar.__scripts.OnEnter
    T.notNil(onEnter, "状态条应有 OnEnter")

    onEnter(bar)
    T.truthy(GameTooltip:IsShown(), "移入后 tooltip 应显示")
    T.truthy(Stub.TooltipContains(Core.L("PANEL_TITLE")), "提示应含标题")
    T.truthy(Stub.TooltipContains(Core.L("LABEL_STATUS")), "提示应含状态")

    local onLeave = bar.__scripts.OnLeave
    onLeave(bar)
    T.falsy(GameTooltip:IsShown(), "移出后 tooltip 应隐藏")
end)
