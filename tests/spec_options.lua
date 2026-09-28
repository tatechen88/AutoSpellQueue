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
        importedFrom = nil, reason = "test", live = 245,
        -- 数字颜色用的延迟品质（默认：正常，白色）
        latencyQuality = "good", latencyNormal = 30, latencyHighAt = 120,
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

--- Template buttons carry their label in `.Text` (the `$parentText` child);
--- hand-made ones put it in `._text`. Both exist in the client.
local function FindButtonByText(text)
    return Stub.FindWidget(function(widget)
        if widget.__kind ~= "Button" then return false end
        local label = widget._text or widget.Text
        return label ~= nil and label.text == text
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
    -- 桩模拟客户端：复选框会先翻转勾选状态，再触发 OnClick
    Stub.Click(widget)
end

--- A checkbox located by its (own, anchored) label - StockTake style.
local function CheckboxOf(labelKey)
    local label = FindFontStringWithText(Core.L(labelKey))
    if not label then return nil end
    local checkbox = label.parent
    if checkbox and checkbox.__checkButton then return checkbox end
    return nil
end

local function MasterSwitch()
    return CheckboxOf("SETTING_ENABLED")
end

--- The single status line: the last FontString created directly on the panel
--- content that is not a row label. Identified by what it renders instead.
local function StatusLine()
    return Stub.FindWidget(function(widget)
        if widget.__kind ~= "FontString" or type(widget.text) ~= "string" then return false end
        for _, state in pairs(Core.STATE) do
            if string.find(widget.text, Core.L("STATE_" .. string.upper(state)), 1, true) then
                return true
            end
        end
        return false
    end)
end

local function Panel()
    return Stub.FindFrame("AutoSpellQueueOptionsPanel")
end

--- Every FontString the player can actually read on the panel.
local function VisibleTexts()
    if not Panel() then return {} end
    local scroll = Stub.FindFrame("AutoSpellQueueOptionsScroll")
    local content = scroll and scroll.__scrollChild
    if not content then return {} end
    local texts = {}
    for _, widget in ipairs(Stub.Widgets()) do
        if widget.__kind == "FontString" and type(widget.text) == "string" and widget.text ~= "" then
            -- walk up to the content frame
            local node, inside = widget, false
            while node do
                if node == content then inside = true break end
                node = node.parent
            end
            if inside then texts[#texts + 1] = widget end
        end
    end
    return texts
end

local function StatusBar()
    return Stub.FindFrame("AutoSpellQueueStatusBar")
end

--- Rows whose label text matches a locale key (or a raw key name when the key
--- no longer exists). Used to assert the panel stays minimal.
local function RowsWithLabel(labelKey)
    local text = Core.L(labelKey)
    local found = {}
    for _, widget in ipairs(Stub.Widgets()) do
        if widget.__kind == "FontString" and widget.text == text then
            found[#found + 1] = widget.parent
        end
    end
    return found
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

T.test("Boot: 面板、状态条、极简面板的三个部件都建起来了，且没有报错", function()
    Boot()
    local panel = Panel()
    T.notNil(panel, "设置分类面板 AutoSpellQueueOptionsPanel 应已创建")
    T.notNil(StatusBar(), "状态条 AutoSpellQueueStatusBar 应已创建")
    T.notNil(Stub.settingsCalls.registerCanvas, "应调用 Settings.RegisterCanvasLayoutCategory")
    T.notNil(Stub.settingsCalls.registerAddOn, "应调用 Settings.RegisterAddOnCategory")

    T.notNil(MasterSwitch(), "标题行应有总开关")
    T.notNil(StatusLine(), "应有一行状态")
    T.notNil(CheckboxOf("SETTING_SHOW_STATUS"), "应有显示悬浮状态条复选框")
    T.notNil(FindButtonByText(Core.L("BUTTON_RESET_POSITION")), "应有重置位置按钮")
    -- 构建失败过去会留下半页/空页且没有任何说明——这里把它变成可见的失败
    T.isNil(_G.ASQ_BUILD_ERROR, "面板构建不得有错误（实得 " .. tostring(_G.ASQ_BUILD_ERROR) .. "）")

    Options.Refresh()
    T.notNil(StatusLine(), "刷新后状态行仍应存在")
end)

T.test("面板必须极简：两个开关 + 一行状态 + 一个动作按钮，且不许出现长句（守门用例）", function()
    Boot()
    -- 玩家可见设置只有 enabled / showStatus，面板里就只允许这两个复选框。
    T.notNil(MasterSwitch(), "总开关")
    T.notNil(CheckboxOf("SETTING_SHOW_STATUS"), "状态条开关")

    -- v1 的旋钮必须一个都不剩（它们现在是算法的一部分，不再由玩家决定）。
    local removed = {
        "SETTING_BASE_MODE", "SETTING_MANUAL_BASE", "SETTING_ADAPTIVE",
        "SETTING_MARGIN", "SETTING_MIN", "SETTING_MAX", "SETTING_HYSTERESIS",
        "SETTING_LATENCY_SOURCE", "SETTING_STATUS_FONT", "SETTING_STATUS_FONT_SIZE",
        "SETTING_CHAT_FEEDBACK",
    }
    for _, key in ipairs(removed) do
        T.eq(#RowsWithLabel(key), 0, "面板里不该再有这个设置: " .. key)
    end

    local checkboxes = 0
    for _, widget in ipairs(Stub.Widgets()) do
        if widget.__checkButton then checkboxes = checkboxes + 1 end
    end
    T.eq(checkboxes, 2, "面板里只允许两个复选框（实得 " .. checkboxes .. "）")

    -- StockTake 的两个坑（它们自己在注释里记着，这里变成断言）：
    --   1) 现代复选框模板没有文本元素，Button:SetText 会造一个**无锚点**字体串
    --      —— API 读回正常但屏幕上看不见。所以标签必须自建且带锚点。
    --   2) 不该再有任何自绘开关（旧版用 _track 纹理画的那个）。
    for _, checkbox in ipairs(Stub.Widgets()) do
        if checkbox.__checkButton then
            T.isNil(checkbox.Text, "复选框不得用 Button:SetText 当标签（会是无锚点字体串）")
            T.eq(checkbox.__template, "SettingsCheckboxTemplate",
                "应使用暴雪原生设置复选框模板")
        end
    end
    for _, widget in ipairs(Stub.Widgets()) do
        T.isNil(widget._track, "不该再有自绘开关（_track 纹理）")
    end

    -- 保留的唯一按钮是「重置位置」：它是动作，不是参数。
    T.notNil(FindButtonByText(Core.L("BUTTON_RESET_POSITION")), "重置位置按钮应保留")

    -- 玩家反馈：说明太多，普通玩家不需要知道。所以面板里每一行都必须短，
    -- 长解释只能出现在悬停提示里（提示不是 FontString，不会被这里扫到）。
    local texts = VisibleTexts()
    T.truthy(#texts <= 6, "面板可见文字不应超过 6 行（实得 " .. #texts .. "）")
    for _, widget in ipairs(texts) do
        T.truthy(#widget.text <= 60,
            "面板里出现了长句（" .. #widget.text .. " 字节）：" .. widget.text)
    end

    -- 副标题/脚注这类整段说明必须已经从页面上消失
    T.isNil(FindFontStringWithText(Core.L("PANEL_SUBTITLE")), "副标题不应再占用页面")
    T.isNil(FindFontStringWithText(Core.L("PANEL_FOOTER")), "脚注不应再占用页面")
end)

T.test("StockTake 风格：面板直接锚在画布上，不再需要滚动框（那类坑随之消失）", function()
    Boot()
    -- 真机曾因滚动子框宽度=0 整页空白（PANEL 665x604 / SCROLL 639x602 / CHILD 0x440）。
    -- 参照 StockTake 的做法后不再有滚动框：控件直接挂在面板上，宽度来自面板本身。
    T.isNil(Stub.FindFrame("AutoSpellQueueOptionsScroll"),
        "极简面板不该再有滚动框（StockTake 风格：直锚面板）")

    local panel = Panel()
    T.notNil(panel, "面板应存在")
    local title = FindFontStringWithText(Core.L("PANEL_TITLE"))
    T.notNil(title, "标题应存在")
    T.eq(title.parent, panel, "标题必须直接挂在面板上")
    T.eq(title:GetNumPoints(), 1, "标题只用一个锚点（左上），不做左右拉伸")
end)

T.test("StockTake 风格布局：标题 → 状态行 → 两个复选框 → 按钮，逐层向下不重叠", function()
    Boot()
    local panel = Panel()
    local title = FindFontStringWithText(Core.L("PANEL_TITLE"))
    local status = StatusLine()
    T.notNil(panel, "面板应存在")
    T.notNil(title, "标题应存在")
    T.notNil(status, "状态行应存在")
    T.eq(title.parent, panel, "标题直接锚在面板上（StockTake 风格）")

    local _, _, _, _, titleY = title:GetPoint()
    local statusRow = status.parent
    local _, _, _, _, statusY = statusRow:GetPoint()
    T.truthy(statusY <= titleY - 20,
        "状态行必须在标题下方（标题 y=" .. tostring(titleY) .. "，状态行 y=" .. tostring(statusY) .. "）")

    local enabled = CheckboxOf("SETTING_ENABLED")
    local shown = CheckboxOf("SETTING_SHOW_STATUS")
    T.notNil(enabled, "总开关复选框应存在")
    T.notNil(shown, "状态条复选框应存在")

    local _, _, _, _, enabledY = enabled:GetPoint()
    local _, _, _, _, shownY = shown:GetPoint()
    T.truthy(enabledY <= statusY - 18,
        "总开关必须在状态行下方（状态行 y=" .. tostring(statusY) .. "，开关 y=" .. tostring(enabledY) .. "）")
    T.truthy(shownY <= enabledY - 24,
        "两个复选框之间至少 24px，否则会挤在一起（" .. tostring(enabledY) .. " → " .. tostring(shownY) .. "）")

    local reset = FindButtonByText(Core.L("BUTTON_RESET_POSITION"))
    T.notNil(reset, "重置位置按钮应存在")
    local _, _, _, _, resetY = reset:GetPoint()
    T.truthy(resetY <= shownY - 24,
        "按钮必须在第二个复选框下方（" .. tostring(shownY) .. " → " .. tostring(resetY) .. "）")

    -- 左对齐一致：StockTake 里所有控件都在 x=16
    for name, widget in pairs({ enabled = enabled, shown = shown, reset = reset }) do
        local _, _, _, x = widget:GetPoint()
        T.eq(x, 16, name .. " 的左边界应与 StockTake 一致（x=16），实得 " .. tostring(x))
    end

    -- 状态行不许换行：单行高度，换行会压到下面的控件
    T.truthy(status:GetHeight() <= 20, "状态行必须是单行（实得高度 " .. tostring(status:GetHeight()) .. "）")
end)

T.test("UI 只构建一次：重复 Build / Refresh 不再新建控件", function()    Boot()
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

    local switch = MasterSwitch()
    Click(switch)
    T.falsy(Core.GetConfig().enabled, "点击后配置里的 enabled 应为 false")
    T.falsy(Core.IsEnabled())

    Click(switch)
    T.truthy(Core.GetConfig().enabled, "再点一次应回到 true")
end)

T.test("开关：只有 enabled 与 showStatus 两个，且都真的写进配置并生效", function()
    Boot()
    resetWorld({ enabled = true, showStatus = true })
    Options.Refresh()

    -- showStatus：写配置 + 真的 Show/Hide 状态条（副作用必须与开关一致）
    local bar = StatusBar()
    bar:Show()
    Click(CheckboxOf("SETTING_SHOW_STATUS"))
    T.falsy(Core.GetConfig().showStatus)
    T.falsy(bar:IsShown(), "关掉开关后状态条必须隐藏")
    Click(CheckboxOf("SETTING_SHOW_STATUS"))
    T.truthy(bar:IsShown(), "重新打开后状态条必须显示")

    -- enabled：总开关写入后必须真的接管/归还
    Stub.SetCVarValue(150)
    Click(MasterSwitch())
    T.falsy(Core.GetConfig().enabled, "点击总开关应写入 enabled=false")
    T.eq(Stub.CVarValue(), "150", "关闭后必须归还玩家原本的值")
    Click(MasterSwitch())
    T.truthy(Core.GetConfig().enabled)
    T.eq(Stub.CVarValue(), "245", "重新打开后应立即接管")
end)

T.test("面板不再暴露任何可调参数：Sanitize 会自动清掉旧存档里的旋钮", function()
    Boot()
    -- 模拟一份从 v1 升级上来的存档（满是旧旋钮）
    resetWorld({
        adaptive = false,
        margin = 250,
        hysteresis = 30,
        minWindow = 300,
        maxWindow = 100,
        baseMode = "manual",
        manualBase = 180,
        latencySource = "home",
        statusFont = "Fonts\\ARIALN.TTF",
        statusFontSize = 20,
        chatFeedback = true,
        showAdvanced = true,
    })
    local cfg = Core.GetConfig()
    for _, retired in ipairs({ "adaptive", "margin", "hysteresis", "minWindow", "maxWindow",
        "baseMode", "manualBase", "latencySource", "statusFont", "statusFontSize",
        "chatFeedback", "showAdvanced" }) do
        T.isNil(cfg[retired], "旧旋钮必须被清掉: " .. retired)
    end
    -- 唯一保留下来的是玩家刻意设置过的「手动基础值」，降级为命令级覆盖
    T.eq(cfg.baseOverride, 180, "手动基础值必须作为逃生口保留")
    -- 算法照常工作：仍然按延迟自适应
    Stub.SetCVarValue(150)
    Stub.worldLatency = 300
    Core.Refresh("after-migration")
    T.eq(Stub.CVarValue(), tostring(Core.GetStatus().target), "迁移后算法必须照常工作")
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

T.test("状态行：六种状态各自的文案与颜色（失败必须一眼看见）", function()
    Boot()
    local line = StatusLine()
    T.notNil(line, "面板应有一行状态")

    for _, case in ipairs(STATE_CASES) do
        local overrides = { state = case.state, live = case.live }
        for key, value in pairs(case.extra or {}) do overrides[key] = value end
        overrides.nilKeys = case.nilKeys

        WithStatus(FakeStatus(overrides), function()
            Options.Refresh()
            local text = line.text
            T.contains(text, Core.L(case.label), "[" .. case.name .. "] 状态行必须写明状态")

            -- 只在插件确实管着这个值时才显示数字（不许拿目标值冒充结果）
            local managing = case.state ~= "disabled" and case.state ~= "error"
                and case.state ~= "unavailable"
            if managing and case.number ~= nil then
                T.contains(text, ExpectedMs(case.number),
                    "[" .. case.name .. "] 应显示实时读到的数字")
            else
                T.isNil(string.find(text, "%d"),
                    "[" .. case.name .. "] 不该显示任何数字（实得：" .. text .. "）")
            end

            -- 颜色跟着状态走：error 必须是红的，否则「让玩家看见」就是空话
            if case.state == "error" then
                local r, g, b = line:GetTextColor()
                T.truthy(r > g and r > b, "[" .. case.name .. "] 失败状态必须是暖色（醒目）")
            end
        end)
    end
end)

T.test("状态行：写入失败的 error 优先于 disabled，且长度保持一行", function()
    Boot()
    local line = StatusLine()
    WithStatus(FakeStatus({
        enabled = false, state = "error", stateReasonKey = "ERR_VERIFY",
        live = nil, current = nil, lastApplied = nil, target = nil, baseline = nil,
        nilKeys = { "live", "current", "lastApplied", "target", "baseline" },
    }), function()
        Options.Refresh()
        T.contains(line.text, Core.L("STATE_ERROR"),
            "关闭插件但写入失败时，必须显示 error 而不是 disabled")
        T.isNil(string.find(line.text, "%d"), "读不到值时不得编造数字")
        T.truthy(#line.text <= 40, "状态行必须短（实得 " .. #line.text .. " 字节）")
    end)
end)

T.test("状态行：失败原因放在悬停提示里，不把目标值当结果显示", function()
    Boot()
    local line = StatusLine()
    local status = FakeStatus({
        state = "error", stateReason = "rejected", stateReasonKey = "ERR_REJECTED",
        lastError = "rejected", live = nil, current = nil, lastApplied = nil, target = 245,
        lastErrorAt = Stub.now,
        nilKeys = { "live", "current", "lastApplied" },
    })
    WithStatus(status, function()
        Options.Refresh()
        -- 页面上只留短状态；长解释在悬停提示里（下一个用例验证它没丢）
        T.contains(line.text, Core.L("STATE_ERROR"))
        T.isNil(string.find(line.text, ExpectedMs(245), 1, true),
            "绝不能把目标值当成当前值显示")
    end)
end)

T.test("状态行：失败原因与算式都在悬停提示里（移到提示≠丢掉信息）", function()
    Boot()
    local line = StatusLine()
    WithStatus(FakeStatus({
        state = "error", stateReason = "rejected", stateReasonKey = "ERR_REJECTED",
        lastError = "rejected", live = nil, current = nil, lastApplied = nil, target = 245,
        lastErrorAt = Stub.now,
        nilKeys = { "live", "current", "lastApplied" },
    }), function()
        Options.Refresh()
        if _G.GameTooltip then _G.GameTooltip.lines = {} end
        -- 提示挂在父帧上：字体串在客户端收不到鼠标事件（真机上因此抛过 HookScript nil）
        local host = line.parent
        local handler = host and host.__scripts and host.__scripts.OnEnter
        T.notNil(handler, "状态行必须有悬停提示（挂在可接收鼠标事件的帧上）")
        handler(host)
        T.truthy(_G.GameTooltip and #_G.GameTooltip.lines > 0, "提示必须有内容")
        local joined = table.concat(_G.GameTooltip.lines, "\n")
        T.contains(joined, Core.L("PANEL_SUBTITLE"), "提示要说明这个插件做什么")
        T.contains(joined, Core.L("PANEL_FOOTER"), "提示要给出诊断与逃生口的入口")
        T.truthy(string.find(joined, "ms", 1, true) ~= nil, "提示里要给出算式（带 ms 的数字）")
    end)
end)

T.test("数字颜色随延迟品质变化：正常=白，明显偏高=红（状态色只在失败/等待时用）", function()
    Boot()
    local bar = StatusBar()
    bar:Show()
    local line = StatusLine()

    local function BarColorFor(overrides)
        local r, g, b
        WithStatus(FakeStatus(overrides), function()
            bar._accum = 0
            Stub.FireUpdate(1.0)
            r, g, b = bar._text:GetTextColor()
        end)
        return r, g, b
    end

    local function IsWhite(r, g, b) return r > 0.9 and g > 0.9 and b > 0.9 end
    local function IsRed(r, g, b) return r > 0.8 and g < 0.6 and b < 0.6 end

    -- 延迟正常 → 白色（"没什么可看的"才是正常状态）
    local r, g, b = BarColorFor({ state = "applied", live = 245, latencyQuality = "good" })
    T.truthy(IsWhite(r, g, b), "延迟正常时数字应为白色（实得 " .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b) .. "）")

    -- 延迟明显偏高 → 红色
    r, g, b = BarColorFor({ state = "applied", live = 245, latencyQuality = "high" })
    T.truthy(IsRed(r, g, b), "延迟偏高时数字应为红色（实得 " .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b) .. "）")

    -- 还没读到延迟 → 不猜，保持中性白
    r, g, b = BarColorFor({ state = "applied", live = 245, latencyQuality = "unknown" })
    T.truthy(IsWhite(r, g, b), "未知延迟时保持白色（不猜）")

    -- 等待脱战：这是状态信息，不该被延迟品质改色
    r, g, b = BarColorFor({ state = "pending", live = 245, inCombat = true, latencyQuality = "high" })
    T.truthy(r > 0.9 and g > 0.6 and b < 0.4, "pending 仍用等待色（橙），与延迟品质无关")

    -- 写入失败：仍然是红色，且不是"因为延迟高"
    r, g, b = BarColorFor({ state = "error", live = 150, stateReasonKey = "ERR_REJECTED",
        latencyQuality = "good" })
    T.truthy(IsRed(r, g, b), "失败状态必须红（与延迟品质无关）")

    -- 边框必须跟数字同色（玩家要求：边框也要跟着变）
    local function BorderRGB()
        local colors = {}
        for _, texture in ipairs(bar._border or {}) do
            if texture.color then colors[#colors + 1] = texture.color end
        end
        return colors
    end
    T.eq(#BorderRGB(), 4, "状态条边框应有四条边纹理")

    local function BorderMatches(r, g, b)
        for _, c in ipairs(BorderRGB()) do
            if math.abs(c[1] - r) > 0.05 or math.abs(c[2] - g) > 0.05
                or math.abs(c[3] - b) > 0.05 then
                return false
            end
        end
        return true
    end

    local tr, tg, tb = BarColorFor({ state = "applied", live = 245, latencyQuality = "good" })
    T.truthy(BorderMatches(tr, tg, tb), "边框必须与数字同色（正常→白）")

    tr, tg, tb = BarColorFor({ state = "applied", live = 245, latencyQuality = "high" })
    T.truthy(BorderMatches(tr, tg, tb), "边框必须与数字同色（偏高→红）")

    tr, tg, tb = BarColorFor({ state = "disabled", live = 150, enabled = false })
    T.truthy(BorderMatches(tr, tg, tb), "关闭状态边框也要跟着状态色（灰）")
    -- 面板状态行用的是同一套规则
    WithStatus(FakeStatus({ state = "applied", live = 245, latencyQuality = "high" }), function()
        Options.Refresh()
        local pr, pg, pb = line:GetTextColor()
        T.truthy(IsRed(pr, pg, pb), "面板状态行也要跟着变红")
    end)
    WithStatus(FakeStatus({ state = "applied", live = 245, latencyQuality = "good" }), function()
        Options.Refresh()
        local pr, pg, pb = line:GetTextColor()
        T.truthy(IsWhite(pr, pg, pb), "面板状态行正常时为白色")
    end)
end)

T.test("偏高时悬停提示必须说明「为什么是红的」", function()
    Boot()
    local bar = StatusBar()
    bar:Show()
    WithStatus(FakeStatus({
        state = "applied", live = 245, latencyQuality = "high", latencyNormal = 30,
        latency = 210, latencyHighAt = 120,
    }), function()
        if _G.GameTooltip then _G.GameTooltip.lines = {} end
        bar.__scripts.OnEnter(bar)
        local joined = table.concat(_G.GameTooltip.lines, "\n")
        T.contains(joined, "210", "提示里要有当前延迟数值")
        T.contains(joined, "30", "提示里要有本机平时的延迟")
    end)

    -- 正常时不出现这条解释（别把提示写成噪音）
    WithStatus(FakeStatus({ state = "applied", live = 245, latencyQuality = "good" }), function()
        if _G.GameTooltip then _G.GameTooltip.lines = {} end
        bar.__scripts.OnEnter(bar)
        local joined = table.concat(_G.GameTooltip.lines, "\n")
        T.isNil(string.find(joined, Core.L("HINT_LATENCY_HIGH"), 1, true),
            "正常时不该出现「延迟偏高」的说明")
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
    local line = StatusLine()
    T.contains(line.text, Core.L("STATE_ERROR"), "面板必须显示 error")
    T.isNil(string.find(line.text, "%d"), "失败时状态行不得显示数字")

    local bar = StatusBar()
    bar:Show()
    bar._accum = 0
    Stub.FireUpdate(1.0)
    T.eq(bar._text.text, Core.L("STATE_ERROR"), "状态条在失败时不能显示数字")
    T.isNil(string.find(bar._text.text, "%d"))

    -- 原因与细节在悬停提示里（失败原因不能丢）
    local host = line.parent
    if _G.GameTooltip then _G.GameTooltip.lines = {} end
    host.__scripts.OnEnter(host)
    T.truthy(_G.GameTooltip and #_G.GameTooltip.lines > 0, "失败时提示必须有内容")
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

T.test("安全边界由算法内部负责：旧存档里的低上限不再能把队列关掉", function()
    Boot()
    -- v1 允许把上限调到 30ms（等于悄悄关掉施法队列）。现在这个设置没了，
    -- Sanitize 会把它清掉，公式只使用内部安全区间。
    resetWorld({ minWindow = 10, maxWindow = 30 })
    local cfg = Core.GetConfig()
    T.isNil(cfg.minWindow, "旧下限设置已被清除")
    T.isNil(cfg.maxWindow, "旧上限设置已被清除")

    Stub.SetCVarValue(150)
    Stub.worldLatency = 0
    Core.Refresh("bounds")
    local target = Core.GetStatus().target
    T.inRange(target, Core.WINDOW_MIN, Core.WINDOW_MAX, "目标必须落在内部安全区间内")
    T.truthy(target >= Core.WINDOW_MIN, "绝不允许低于内部下限（那等于关掉队列）")
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
    resetWorld({ enabled = true, showStatus = false, baseOverride = 180 })
    Stub.chat = {}

    SlashCmdList["AUTOSPELLQUEUE"]("reset")
    local cfg = Core.GetConfig()
    T.eq(cfg.enabled, true, "reset 应恢复默认开关")
    T.eq(cfg.showStatus, true)
    T.isNil(cfg.baseOverride, "reset 应清掉命令级覆盖")
    T.truthy(Stub.ChatContains(Core.L("MSG_RESET_DONE")))
end)

T.test("斜杠 /asq base：命令级逃生口（设置面板里没有它）", function()
    Boot()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Stub.chat = {}

    SlashCmdList["AUTOSPELLQUEUE"]("base 180")
    T.eq(Core.GetConfig().baseOverride, 180, "应写入基础值覆盖")
    T.eq(Core.GetStatus().base, 180, "立即生效")

    Stub.chat = {}
    SlashCmdList["AUTOSPELLQUEUE"]("base")
    T.truthy(Stub.ChatContains("180"), "不带参数应回报当前覆盖值")

    Stub.chat = {}
    SlashCmdList["AUTOSPELLQUEUE"]("base auto")
    T.isNil(Core.GetConfig().baseOverride, "auto 应恢复跟随专精表")
    T.truthy(Stub.ChatContains(Core.L("CHAT_BASE_AUTO")))

    Stub.chat = {}
    SlashCmdList["AUTOSPELLQUEUE"]("base abc")
    T.isNil(Core.GetConfig().baseOverride, "非法输入不得写入")
    T.truthy(Stub.ChatContains(Core.L("CHAT_BASE_INVALID")), "非法输入必须给出用法")

    -- 面板里绝不能有这个设置（它只存在于命令行）
    T.eq(#RowsWithLabel("SETTING_MANUAL_BASE"), 0, "基础值覆盖不得出现在面板里")
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
