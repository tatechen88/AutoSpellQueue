------------------------------------------------------------------------------
--  tests/spec_core.lua -- ns.Core
--
--  Locks the five core invariants of docs/ARCHITECTURE.md section 3:
--    1. a write only counts when it was verified (see spec_cvar as well);
--    2. ownership (baseline / lastApplied) is explicit and persisted;
--    3. only *our* value is ever restored - never overwrite a foreign change;
--    4. nothing is written in combat, and combat end re-decides from live state
--       (no cached target is replayed);
--    5. logout puts the player's value back;
--    6. a future schemaVersion is never downgraded.
--
--  Everything is driven through the fake client in tests/wow_stub.lua: no
--  Options panel, no Locale file, no game client.
------------------------------------------------------------------------------
local T, ns, Stub = ...
local Core = ns.Core
local CVar = ns.CVar
local Formula = ns.Formula

T.spec("spec_core")

------------------------------------------------------------------------------
--  Fresh world per test
------------------------------------------------------------------------------

--- The saved file, schema v2: the player only owns two switches now.
local function defaultDB(extra)
    local db = {
        schemaVersion = 2,
        enabled = true,
        showStatus = true,
    }
    for key, value in pairs(extra or {}) do db[key] = value end
    return db
end

--- The flat table Core.Decide() consumes: player settings + the measured
--- algorithm values. With no samples pushed, the tracker guarantees a margin of
--- BASE_HEADROOM and a hysteresis of HYSTERESIS_MIN, so the numbers here are
--- deterministic instead of "whatever the settings used to be".
local function DecideOptions(extra)
    local options = {
        enabled = true,
        ownership = nil,
        baseMode = "auto",
        manualBase = 0,
        adaptive = true,
        latencySource = "world",
        margin = ns.Latency.BASE_HEADROOM,
        hysteresis = ns.Latency.HYSTERESIS_MIN,
        minWindow = Core.WINDOW_MIN,
        maxWindow = Core.WINDOW_MAX,
    }
    for key, value in pairs(extra or {}) do options[key] = value end
    return options
end

--- Full reset: fake client, saved variables, module state, injected env.
local function resetWorld(extra)
    Stub.Reset()
    Core.StopTicker()
    CVar.SetEnv(nil)
    ns.Latency.Reset(Core.latency)
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
    Core.initialized = nil
    return Core.GetConfig()
end

T.beforeEach(function() resetWorld() end)

--- Pending timers that are NOT the periodic refresh ticker: the CVAR_UPDATE
--- debounce and the warm-up retries. The ticker is counted separately because
--- its lifecycle follows "enabled OR still owning", not just the switch.
local function PendingNonTicker()
    return Stub.PendingTimers() - (Core.ticker and 1 or 0)
end

--- A synthetic snapshot for pure Decide() calls.
local function baseSnap(overrides)
    local snap = {
        specID = 63, classFile = "MAGE", specName = "Fire",
        home = 0, world = 0, context = "world",
        current = 150, inCombat = false, at = 1000, cvarInfo = { known = true },
    }
    for key, value in pairs(overrides or {}) do snap[key] = value end
    if overrides and overrides.noCurrent then snap.current = nil end
    return snap
end

--- A synthetic options table for pure Decide() calls (deterministic defaults).
local function baseCfg(overrides)
    return DecideOptions(overrides)
end

local function stripComments(source)
    local text = source:gsub("%-%-%[=*%[.-%]=*%]", " ")
    return text:gsub("%-%-[^\n]*", " ")
end

--- Expected target for a steady latency with a fresh tracker: the algorithm
--- adds BASE_HEADROOM on top of the measured latency (jitter is 0 when every
--- sample is identical). Tests derive the number instead of hardcoding it.
local function ExpectedTarget(worldLatency)
    return math.max(245, worldLatency + ns.Latency.BASE_HEADROOM)
end

--- Applies a value as the addon would, then clears all bookkeeping.
--  Returns the ownership record after the write.
local function applyOnce(worldLatency, expected)
    Stub.worldLatency = worldLatency or 0
    local ok = Core.Refresh("test-apply")
    T.truthy(ok, "前置条件：写入应当成功")
    T.eq(Stub.CVarNumber(), expected, "前置条件：CVar 应等于目标值")
    local ownership = Core.GetConfig().ownership
    T.truthy(ownership and ownership.active, "前置条件：应建立所有权")
    Stub.ClearWrites()
    Stub.chat = {}
    return ownership
end

------------------------------------------------------------------------------
--  Decide: the pure decision function
------------------------------------------------------------------------------

T.test("Decide 全分支: none / apply / restore / release / wait / unavailable", function()
    local own = { active = true, baseline = 150, lastApplied = 245 }

    local action = Core.Decide(baseCfg(), baseSnap({ noCurrent = true, readErr = "boom" }))
    T.eq(action.kind, "unavailable")
    T.eq(action.reason, "boom")
    T.eq(action.target, 245, "即使读不到当前值也要给出目标值供 UI 显示")

    action = Core.Decide(baseCfg(), baseSnap({ current = 245 }))
    T.eq(action.kind, "none")
    T.eq(action.state, Core.STATE.APPLIED)

    action = Core.Decide(baseCfg({ enabled = false }), baseSnap({ current = 150 }))
    T.eq(action.kind, "none")
    T.eq(action.state, Core.STATE.DISABLED)

    action = Core.Decide(baseCfg({ enabled = false, ownership = own }), baseSnap({ current = 245 }))
    T.eq(action.kind, "restore")
    T.eq(action.value, 150, "恢复目标是 baseline")
    T.eq(action.state, Core.STATE.DISABLED)

    action = Core.Decide(baseCfg({ enabled = false, ownership = own }), baseSnap({ current = 333 }))
    T.eq(action.kind, "release")
    T.eq(action.reason, "external-change")
    T.eq(action.state, Core.STATE.DISABLED)

    action = Core.Decide(baseCfg(), baseSnap({ current = 150, inCombat = true }))
    T.eq(action.kind, "wait")
    T.eq(action.state, Core.STATE.PENDING)

    action = Core.Decide(baseCfg(), baseSnap({ current = 150 }))
    T.eq(action.kind, "apply")
    T.eq(action.target, 245)

    action = Core.Decide(baseCfg({ enabled = false, ownership = own }),
        baseSnap({ current = 245, inCombat = true }))
    T.eq(action.kind, "wait", "战斗中即使该归还 baseline 也只能等")
    T.eq(action.state, Core.STATE.PENDING)
end)

T.test("Decide: 迟滞带内不写，边界值等于迟滞时要写", function()
    local own = { active = true, baseline = 150, lastApplied = 245 }
    -- 迟滞现在来自算法（HYSTERESIS_MIN），不再是玩家设置。
    local band = ns.Latency.HYSTERESIS_MIN
    T.truthy(band >= 1, "迟滞下限必须为正，否则达不到防抖目的")

    -- |245 - (245 + band - 1)| = band - 1 < band -> 在带内
    local action = Core.Decide(baseCfg({ ownership = own }), baseSnap({ current = 245 + band - 1 }))
    T.eq(action.kind, "none")
    T.truthy(action.externalChange, "current != lastApplied 应标记外部改动")

    -- hysteresis = 0 关闭迟滞
    action = Core.Decide(baseCfg({ ownership = own, hysteresis = 0 }), baseSnap({ current = 246 }))
    T.eq(action.kind, "apply")

    -- 差值正好等于迟滞 -> 写出（边界语义：严格小于才算“在带内”）
    action = Core.Decide(baseCfg({ ownership = own, hysteresis = 5 }), baseSnap({ current = 250 }))
    T.eq(action.kind, "apply")

    -- 差值 4 < 5 -> 在带内
    action = Core.Decide(baseCfg({ ownership = own, hysteresis = 5 }), baseSnap({ current = 249 }))
    T.eq(action.kind, "none")
end)

T.test("Decide: 外部改动只标记，baseline 不被重设", function()
    local own = { active = true, baseline = 150, lastApplied = 245 }
    local cfg = baseCfg({ ownership = own })
    local action = Core.Decide(cfg, baseSnap({ current = 333 }))
    T.eq(action.kind, "apply")
    T.eq(action.target, 245)
    T.truthy(action.externalChange)
    T.eq(cfg.ownership.baseline, 150, "baseline 永远是最初接管前的值")
end)

T.test("Decide: 未知专精/缺失延迟仍给出有限目标值", function()
    local cfg = baseCfg()
    for _, spec in ipairs({ 0, 999999, nil }) do
        local action = Core.Decide(baseCfg(), baseSnap({ specID = spec, classFile = "FOO", current = 0 }))
        T.truthy(action.target ~= nil and action.target == action.target, "target 必须是有限数字")
        T.inRange(action.target, 50, 400, "spec=" .. tostring(spec))
    end
    T.eq(Core.Decide(cfg, baseSnap({ current = 1000 })).kind, "apply")
end)

T.test("Decide 是纯函数：不改 cfg、不写 CVar、不排定时器、不改运行状态", function()
    resetWorld()
    local cfg = Core.GetConfig()
    cfg.ownership = { active = true, baseline = 150, lastApplied = 245 }
    local before = { active = true, baseline = 150, lastApplied = 245 }
    Stub.SetCVarValue(245)
    Stub.ClearWrites()
    Stub.timers = {}

    local snapshots = {
        baseSnap({ current = 150 }),
        baseSnap({ current = 245 }),
        baseSnap({ current = 250 }),
        baseSnap({ current = 333 }),
        baseSnap({ current = 400, inCombat = true }),
        baseSnap({ noCurrent = true, readErr = "x" }),
        baseSnap({ current = 150, specID = 999999 }),
    }
    for index, snap in ipairs(snapshots) do
        local action = Core.Decide(cfg, snap)
        T.truthy(type(action) == "table" and action.kind ~= nil, "快照 #" .. index .. " 应有动作")
    end

    T.eq(#Stub.writes, 0, "Decide 绝不能写 CVar")
    T.deepeq(cfg.ownership, before, "Decide 不得改动 ownership")
    T.eq(Stub.PendingTimers(), 0, "Decide 不得排定时器")
    T.eq(Core.state, Core.STATE.IDLE, "Decide 不得改运行状态（那是 Execute 的事）")
    T.eq(Stub.CVarNumber(), 245, "客户端值不变")
end)

------------------------------------------------------------------------------
--  P1: a failed write must never be reported as applied
------------------------------------------------------------------------------

T.test("P1: API 返回 false（pcall 未抛错）-> error 状态，绝不记为已应用", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Stub.setCVarMode = "reject-false"

    local ok = Core.Refresh("rejected")
    T.falsy(ok, "写入失败时 Refresh 必须返回 false")

    local cfg = Core.GetConfig()
    T.eq(Core.state, Core.STATE.ERROR, "旧代码在这里显示成已应用")
    T.eq(Core.stateReason, CVar.ERR_REJECTED)
    T.eq(cfg.stats.applied, 0, "失败不得增加 apply 计数")
    T.isNil(cfg.ownership and cfg.ownership.lastApplied, "失败不得写 lastApplied")
    T.eq(Stub.CVarValue(), "150", "客户端值未被改动")
    T.eq(#Stub.writes, 1, "确实尝试过一次")

    local status = Core.GetStatus()
    T.eq(status.state, Core.STATE.ERROR)
    T.eq(status.stateReasonKey, "ERR_REJECTED")
    T.eq(status.applyCount, 0)
    T.eq(status.lastError, CVar.ERR_REJECTED)
    T.truthy(status.lastErrorAt ~= nil)
    T.truthy(Stub.ChatContains("AutoSpellQueue"), "失败必须让玩家看见")
end)

T.test("P1: API 谎报 true 但值没变 -> error(verify-failed)，不记为已应用", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Stub.setCVarMode = "silent-noop"

    T.falsy(Core.Refresh("liar"))
    T.eq(Core.state, Core.STATE.ERROR)
    T.eq(Core.stateReason, CVar.ERR_VERIFY)
    T.eq(Core.GetConfig().stats.applied, 0)
    T.isNil(Core.GetConfig().ownership and Core.GetConfig().ownership.lastApplied)
    T.eq(Stub.CVarValue(), "150")
end)

T.test("失败提示限流：同一原因 120 秒内只提示一次", function()
    resetWorld({ enabled = true, chatFeedback = false })
    Stub.SetCVarValue(150)
    Stub.setCVarMode = "reject-false"

    Core.Refresh("fail-1")
    T.eq(#Stub.chat, 1, "关闭 chatFeedback 也要提示错误")
    Core.Refresh("fail-2")
    T.eq(#Stub.chat, 1, "120 秒内不重复刷屏")
    Stub.now = Stub.now + 130
    Core.Refresh("fail-3")
    T.eq(#Stub.chat, 2, "超过 120 秒允许再次提示")
end)

T.test("成功写入：ownership 记录 baseline/lastApplied 并计入统计", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    local ok = Core.Refresh("apply")
    T.truthy(ok)
    T.eq(Stub.CVarValue(), "245")

    local cfg = Core.GetConfig()
    T.eq(cfg.ownership.active, true)
    T.eq(cfg.ownership.baseline, 150, "baseline 是接管前玩家的值")
    T.eq(cfg.ownership.lastApplied, 245)
    T.truthy(cfg.ownership.startedAt ~= nil)
    T.eq(cfg.stats.applied, 1)
    T.eq(Core.state, Core.STATE.APPLIED)

    local status = Core.GetStatus()
    T.truthy(status.owned)
    T.eq(status.baseline, 150)
    T.eq(status.lastApplied, 245)
    T.eq(status.target, 245)
    T.eq(status.live, 245)
    T.eq(status.applyCount, 1)
    T.eq(#Stub.chat, 0, "改值不再刷屏：只有错误才会说话")
end)

T.test("读不到 CVar：unavailable，不写也不报成功", function()
    resetWorld({ enabled = true })
    Stub.MakeUnreadable()

    local ok = Core.Refresh("unreadable")
    T.falsy(ok)
    T.eq(Core.state, Core.STATE.UNAVAILABLE)
    T.eq(Core.stateReason, CVar.ERR_UNAVAILABLE)
    T.eq(#Stub.writes, 0)
    T.isNil(Core.GetStatus().live)
end)

------------------------------------------------------------------------------
--  P1: combat never writes; combat end re-decides from live state
------------------------------------------------------------------------------

T.test("P1: 战斗中不写；脱战后按实时状态重新决策，不重放战斗前的旧目标", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Stub.worldLatency = 300 -- 目标 = max(245, 300 + 自适应余量)
    Stub.combat = true

    Core.Refresh("combat-start")
    T.eq(Core.state, Core.STATE.PENDING)
    T.eq(#Stub.writes, 0, "战斗中绝不能写 CVar")
    T.eq(Stub.CVarValue(), "150")
    T.isNil(Core.GetConfig().ownership, "没写入就不该有所有权")

    -- 战斗中改配置：现在只有「基础值覆盖」这一条命令级通道。
    -- 它只改基础值，延迟自适应永远生效（这正是本次简化的语义）。
    Core.SetBaseOverride(120)
    -- 战斗中玩家/别的插件改了值
    Stub.SetCVarValue(260)
    T.eq(#Stub.writes, 0, "战斗中改配置也不得写")
    T.eq(Core.state, Core.STATE.PENDING)

    Stub.combat = false
    Stub.FireEvent("PLAYER_REGEN_ENABLED")

    T.eq(#Stub.writes, 1, "脱战后恰好写一次")
    -- 脱战后按「实时延迟 + 算法余量」重新算，基础值是被覆盖的 120
    local expected = math.max(120, Stub.worldLatency + ns.Latency.Margin(Core.latency))
    expected = math.min(Core.WINDOW_MAX, math.max(Core.WINDOW_MIN, expected))
    T.eq(tonumber(Stub.writes[1].value), expected,
        "写的是脱战后重新算出的目标，而不是战斗前算的旧值")
    T.eq(Core.state, Core.STATE.APPLIED)

    local ownership = Core.GetConfig().ownership
    T.truthy(ownership and ownership.active)
    T.eq(ownership.baseline, 260, "baseline 是接管那一刻客户端的值")
    T.eq(ownership.lastApplied, expected)
end)

T.test("P1: 战斗中禁用再启用，脱战必须重新决策（不得重放旧目标）", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Stub.worldLatency = 300
    Stub.combat = true

    Core.Refresh("combat")
    T.eq(Core.state, Core.STATE.PENDING)
    T.eq(#Stub.writes, 0)

    Core.SetEnabled(false)
    T.eq(#Stub.writes, 0, "战斗中禁用不得写")
    T.eq(Core.state, Core.STATE.DISABLED)
    T.isNil(Core.GetConfig().ownership, "从未写入过，就没有所有权要归还")

    Stub.worldLatency = 100 -- 重新启用后的实时延迟回到 100
    Core.SetEnabled(true)
    T.eq(#Stub.writes, 0, "战斗中启用也不得写")
    T.eq(Core.state, Core.STATE.PENDING)

    Stub.combat = false
    Stub.FireEvent("PLAYER_REGEN_ENABLED")
    T.eq(#Stub.writes, 1, "脱战后只写一次")
    -- 必须按脱战后的实时状态算：延迟已回到 100，绝不能沿用战斗中的 300。
    -- （余量由算法按刚看到的 300→100 波动给得偏保守，所以这里不断言具体数值，
    --   只断言「和当前实时目标一致」且「明显不是战斗中那 300ms 算出来的」。）
    local written = tonumber(Stub.writes[1].value)
    T.notNil(written)
    T.eq(written, Core.GetStatus().target, "按脱战后的实时目标写")
    T.truthy(written < 400, "不能是战斗中 300ms 延迟算出的上限值（实得 " .. tostring(written) .. "）")
    T.eq(Core.state, Core.STATE.APPLIED)
    T.eq(Core.GetConfig().ownership.baseline, 150)
end)

T.test("P1: 启用中在战斗里禁用 -> 只标记 pending，脱战后归还 baseline", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    local ownership = applyOnce(300, ExpectedTarget(300))
    T.eq(ownership.baseline, 150)
    T.eq(ownership.lastApplied, ExpectedTarget(300))

    Stub.combat = true
    Core.SetEnabled(false)
    T.eq(#Stub.writes, 0, "战斗中不能写回 baseline")
    T.eq(Core.state, Core.STATE.PENDING)
    T.truthy(Core.GetConfig().ownership, "所有权必须保留，等脱战再归还")
    T.eq(Stub.CVarValue(), tostring(ExpectedTarget(300)))

    Stub.combat = false
    Stub.FireEvent("PLAYER_REGEN_ENABLED")
    T.eq(#Stub.writes, 1)
    T.eq(Stub.writes[1].value, "150", "脱战后归还 baseline")
    T.eq(Stub.CVarValue(), "150")
    T.isNil(Core.GetConfig().ownership)
    T.eq(Core.state, Core.STATE.DISABLED)
end)

------------------------------------------------------------------------------
--  Ownership: logout, external changes
------------------------------------------------------------------------------

T.test("登出归还 baseline 并清空所有权", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    applyOnce(300, ExpectedTarget(300))

    Stub.FireEvent("PLAYER_LOGOUT")
    T.eq(#Stub.writes, 1)
    T.eq(Stub.writes[1].value, "150")
    T.eq(Stub.CVarValue(), "150")
    T.isNil(Core.GetConfig().ownership)
    T.isNil(Core.ticker, "登出应停止定时器")
end)

T.test("P1: 登出归还失败时保留所有权，下次登录仍能归还", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    applyOnce(300, ExpectedTarget(300))

    Stub.setCVarMode = "reject-false"
    Stub.FireEvent("PLAYER_LOGOUT")
    T.eq(Stub.CVarValue(), tostring(ExpectedTarget(300)), "归还失败，值留在插件写过的状态")
    T.eq(Core.state, Core.STATE.ERROR)

    local ownership = Core.GetConfig().ownership
    T.truthy(ownership and ownership.active, "失败必须保留所有权（持久化后下次登录还能归还）")
    T.eq(ownership.baseline, 150)
    T.eq(ownership.lastApplied, ExpectedTarget(300))

    -- 模拟下一次登录：同一份 SavedVariables 重新加载
    Core.db = nil
    Stub.setCVarMode = "normal"
    local cfg = Core.GetConfig()
    T.truthy(cfg.ownership and cfg.ownership.active, "ownership 必须能从存档里恢复")
    T.eq(cfg.ownership.baseline, 150)
    T.eq(cfg.ownership.lastApplied, ExpectedTarget(300))

    local ok, reason = Core.RestoreOwnership("next-login")
    T.truthy(ok)
    T.isNil(reason)
    T.eq(Stub.CVarValue(), "150")
    T.isNil(Core.GetConfig().ownership)
end)

T.test("P1: 禁用时若值被外部改过 -> 只释放所有权，不覆盖", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    applyOnce(300, ExpectedTarget(300))

    Stub.SetCVarValue(333) -- 玩家/别的插件改了
    Core.SetEnabled(false)
    T.eq(Stub.CVarValue(), "333", "绝不能把别人的值改回我们的 baseline")
    T.isNil(Core.GetConfig().ownership, "放弃所有权即可")
    T.eq(Core.state, Core.STATE.DISABLED)
    T.eq(#Stub.writes, 0, "释放不该产生写入")
end)

T.test("P1: RestoreOwnership 遇到外部改动只释放、不写入", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    applyOnce(300, ExpectedTarget(300))
    Stub.SetCVarValue(333)

    local ok, reason = Core.RestoreOwnership("manual")
    T.truthy(ok)
    T.eq(reason, "external-change")
    T.eq(Stub.CVarValue(), "333")
    T.isNil(Core.GetConfig().ownership)
    T.eq(#Stub.writes, 0)
end)

T.test("RestoreOwnership: 没有所有权时是空操作", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    local ok, reason = Core.RestoreOwnership("nothing")
    T.truthy(ok)
    T.eq(reason, "not-owned")
    T.eq(#Stub.writes, 0)
end)

T.test("启用中遇到外部改值：重新夺回管理，但 baseline 保持不变", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    applyOnce(300, ExpectedTarget(300))

    Stub.SetCVarValue(333)
    Core.Refresh("external")
    T.eq(Stub.CVarValue(), tostring(ExpectedTarget(300)), "启用状态下重新写回我们的目标")
    T.eq(#Stub.writes, 1)
    T.eq(Core.GetConfig().ownership.baseline, 150, "baseline 不得被重设为 333")
    T.eq(Core.GetConfig().ownership.lastApplied, ExpectedTarget(300))
    T.eq(Core.GetConfig().stats.applied, 2, "重新夺回也是一次成功的写入")
    T.eq(Core.state, Core.STATE.APPLIED)
end)

-- 回归锁定（2026-09-28 已修复）：Execute 过去只在 action.kind == "none" 时设置
-- Core.externalChange 与 stats.externalChangeAt，于是“重新夺回管理”（apply）
-- 时 Decide 算好的外部改动诊断被丢掉，UI 无从知道值被动过。
-- 最小复现（当时）：写 350 → 外部改 333 → Refresh 后 externalChange == false。
T.test("外部改值后重新夺回管理时 externalChange 诊断不应丢失", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    applyOnce(300, ExpectedTarget(300))
    Stub.SetCVarValue(333)

    Core.Refresh("external")
    T.eq(Stub.CVarValue(), tostring(ExpectedTarget(300)), "重新夺回我们的目标值")
    T.truthy(Core.GetStatus().externalChange, "值被动过就该如实告诉 UI")
    T.truthy(Core.GetConfig().stats.externalChangeAt ~= nil)
end)

T.test("迟滞范围内的外部小幅改动不触发写入", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    local ownership = applyOnce(300, ExpectedTarget(300))
    local target = ownership.lastApplied

    -- 迟滞由算法按抖动给出（稳定连接 = HYSTERESIS_MIN），因此从算法取值，
    -- 不写死一个「10ms」——那正是本次重构要消灭的东西。
    local band = ns.Latency.Hysteresis(Core.latency)
    T.truthy(band >= 1, "迟滞必须为正，否则防抖失效")

    Stub.SetCVarValue(target + band - 1) -- 差值 band-1 < band -> 带内
    Core.Refresh("jitter")
    T.eq(#Stub.writes, 0, "小幅抖动不该反复写 CVar")
    T.truthy(Core.GetStatus().externalChange, "但仍要如实标记值被动过")
    T.eq(Stub.CVarValue(), tostring(target + band - 1))
end)

------------------------------------------------------------------------------
--  Config: Sanitize / Migrate / ImportLegacy / SetConfig / Reset
------------------------------------------------------------------------------

T.test("Sanitize: 错类型与越界被修正，v1 退休键被清掉并计数", function()
    local db = {
        enabled = "yes",
        showStatus = false,
        baseOverride = 9999,
        statusBarPos = { x = "a", y = 1 },
        junk = "keep",
        -- v1 的旋钮：现在全部退休，Sanitize 必须把它们从存档里清掉
        adaptive = 0,
        manualBase = 9999,
        margin = -50,
        minWindow = 300,
        maxWindow = 100,
        hysteresis = 1000,
        statusFontSize = 100,
        latencySource = "nonsense",
        baseMode = 123,
        statusFont = 42,
        chatFeedback = true,
        showAdvanced = true,
    }
    local sanitized, repairs = Core.Sanitize(db)

    T.eq(sanitized, db, "应原地修正并返回同一个表")
    T.eq(sanitized.enabled, true, "非布尔值按 Lua 真假归一（\"yes\" 为真）")
    T.eq(sanitized.showStatus, false, "false 保持 false")
    T.eq(sanitized.baseOverride, 400, "越界的基础值覆盖被夹到上限")
    T.isNil(sanitized.statusBarPos)
    T.eq(sanitized.junk, "keep", "未知键不该被删（用户数据保留）")

    for _, retired in ipairs({ "adaptive", "manualBase", "margin", "minWindow", "maxWindow",
        "hysteresis", "statusFontSize", "latencySource", "baseMode", "statusFont",
        "chatFeedback", "showAdvanced" }) do
        T.isNil(sanitized[retired], "退休键必须从存档里消失: " .. retired)
    end

    T.truthy(repairs > 0, "repairs 计数应大于 0")
    T.truthy(sanitized.stats.repairs >= repairs, "累计 repairs 应包含本次修正")
    T.eq(sanitized.schemaVersion, Core.DEFAULTS.schemaVersion)
end)

T.test("Sanitize: 非表输入/空表/缺失键都被补全", function()
    local db, repairs = Core.Sanitize("garbage")
    T.eq(type(db), "table")
    T.truthy(repairs > 0)
    T.eq(db.enabled, Core.DEFAULTS.enabled)
    T.eq(db.showStatus, Core.DEFAULTS.showStatus)
    T.eq(type(db.stats), "table")
    T.isNil(db.ownership)

    local empty = Core.Sanitize({})
    T.eq(empty.enabled, true)
    T.eq(empty.showStatus, true)
    T.isNil(empty.baseOverride, "默认跟随专精表")
    T.isNil(empty.statusBarPos)
    T.eq(empty.stats.applied, 0)

    -- 数字型字符串会被接受并取整；nil 保持 nil（不是坏值）
    T.eq(Core.Sanitize({ baseOverride = "180" }).baseOverride, 180)
    T.isNil(Core.Sanitize({ baseOverride = nil }).baseOverride)
    -- 非数字才是坏值 -> 回到 nil（跟随专精表）
    T.isNil(Core.Sanitize({ baseOverride = "abc" }).baseOverride)
end)

T.test("Sanitize: 非法 ownership 记录被丢弃，合法记录被规范化", function()
    local bad = {
        { active = true, baseline = -5 },
        { active = true, baseline = 1000 },
        { active = true, baseline = "abc" },
        { active = false, baseline = 200 },
        { baseline = 200 },
        { active = true, baseline = 0 / 0 },
        "garbage",
    }
    for index, ownership in ipairs(bad) do
        local db = Core.Sanitize({ ownership = ownership })
        T.isNil(db.ownership, "ownership #" .. index .. " 应被丢弃")
    end

    local db = Core.Sanitize({
        ownership = { active = true, baseline = 150.4, lastApplied = 245.6, startedAt = 1000 },
    })
    T.truthy(db.ownership and db.ownership.active)
    T.eq(db.ownership.baseline, 150)
    T.eq(db.ownership.lastApplied, 246)
    T.eq(db.ownership.schema, Core.SCHEMA_VERSION)
    T.eq(db.ownership.startedAt, 1000)

    -- lastApplied 缺失时保留 nil（表示“还没成功写入过”）
    local noApplied = Core.Sanitize({ ownership = { active = true, baseline = 150 } })
    T.truthy(noApplied.ownership)
    T.isNil(noApplied.ownership.lastApplied)
end)

-- 回归锁定（2026-09-28 已修复）：Sanitize 过去对“非表且非 nil”的 ownership
-- 只保护了 baseline 的读取，却直接索引 own.active；字符串因 string 元表侥幸
-- 不报错，数字/布尔会抛 attempt to index a number value (local 'own')，
-- 于是一份损坏的 SavedVariables 能让插件在 ADDON_LOADED 时直接报错
-- ——而 Sanitize 存在的唯一理由就是对付这种文件。
-- 最小复现（当时）：ns.Core.Sanitize({ ownership = 42 })。
T.test("Sanitize: ownership 是数字/布尔/字符串时必须丢弃而不是抛错", function()
    for _, ownership in ipairs({ 42, 0, true, false, "garbage", function() end }) do
        local db = Core.Sanitize({ ownership = ownership })
        T.isNil(db.ownership, "ownership = " .. type(ownership) .. " 应被丢弃")
    end
    -- 顶层不是表也一样
    local db = Core.Sanitize({ ownership = { active = true, baseline = 100 } })
    T.truthy(db.ownership and db.ownership.active, "合法记录仍要保留")
end)

T.test("GetConfig 加载脏存档时先 Sanitize（脏值不进运行时）", function()
    Stub.Reset()
    Core.StopTicker()
    CVar.SetEnv(nil)
    _G.Tate_ASQDB = nil
    _G.AutoSpellQueueDB = {
        enabled = "yes",
        baseOverride = 9999,
        ownership = { active = true, baseline = 9999 },
        stats = { applied = -5, repairs = "x" },
        -- v1 的旋钮：必须被清掉
        margin = 9999,
        latencySource = "??",
    }
    Core.db = nil
    local cfg = Core.GetConfig()

    T.eq(cfg.enabled, true)
    T.eq(cfg.baseOverride, 400, "越界的基础值覆盖被夹到上限")
    T.isNil(cfg.margin, "v1 的 margin 不再存在")
    T.isNil(cfg.latencySource, "v1 的 latencySource 不再存在")
    T.isNil(cfg.ownership)
    T.eq(cfg.stats.applied, 0, "负数统计归零")
    T.truthy(cfg.stats.repairs > 0)
    T.eq(cfg.schemaVersion, Core.SCHEMA_VERSION)
end)

T.test("Migrate: schemaVersion 更高时不降级、不丢字段", function()
    local db = {
        schemaVersion = 99,
        enabled = false,
        myCustomField = "keep",
        ownership = { active = true, baseline = 150 },
    }
    local migrated = Core.Migrate(db)
    T.eq(migrated.schemaVersion, 99, "未来版本必须原样保留")
    T.eq(migrated.schemaFuture, true)
    T.eq(migrated.enabled, false)
    T.eq(migrated.myCustomField, "keep")
    T.truthy(migrated.ownership and migrated.ownership.active)

    -- 走完整的 LoadConfig 路径也一样
    _G.Tate_ASQDB = nil
    _G.AutoSpellQueueDB = { schemaVersion = 99, enabled = false, myCustomField = "keep" }
    Core.db = nil
    local cfg = Core.GetConfig()
    T.eq(cfg.schemaVersion, 99)
    T.eq(cfg.schemaFuture, true)
    T.eq(cfg.myCustomField, "keep")
    T.eq(cfg.enabled, false, "未来 schema 的用户设置不得被默认值覆盖")
    T.truthy(Core.GetStatus().schemaFuture)
end)

T.test("Migrate: 旧版本升到当前版本，并清掉 schemaFuture", function()
    local db = { schemaVersion = 0, schemaFuture = true }
    Core.Migrate(db)
    T.eq(db.schemaVersion, Core.SCHEMA_VERSION)
    T.isNil(db.schemaFuture)

    local missing = {}
    Core.Migrate(missing)
    T.eq(missing.schemaVersion, Core.SCHEMA_VERSION)
end)

T.test("ImportLegacy: 旧 Tate_ASQDB 导入新变量并清空旧变量", function()
    resetWorld()
    _G.AutoSpellQueueDB = nil
    _G.Tate_ASQDB = {
        enabled = false,
        baseMode = "manual",
        manualBase = 180,
        margin = 70,
        latencySource = "home",
        junk = "x",
    }
    Core.db = nil
    local cfg = Core.GetConfig()

    T.eq(cfg.enabled, false)
    -- v1 的「手动基础值」是玩家唯一可能刻意设置过的东西，必须活下来：
    -- 它降级为命令级覆盖 baseOverride，而不是被丢掉。
    T.eq(cfg.baseOverride, 180, "手动基础值必须迁移为 baseOverride")
    T.isNil(cfg.baseMode, "v1 的 baseMode 已退休")
    T.isNil(cfg.manualBase, "v1 的 manualBase 已退休")
    T.isNil(cfg.margin, "v1 的 margin 已退休（改由算法计算）")
    T.isNil(cfg.latencySource, "v1 的 latencySource 已退休")
    T.eq(cfg.importedFrom, "Tate_ASQ")
    T.truthy(type(cfg.importedAt) == "number")
    T.isNil(cfg.junk, "白名单外的旧字段不导入")
    T.isNil(_G.Tate_ASQDB, "导入后必须清空旧 SavedVariables")
    T.truthy(_G.AutoSpellQueueDB == cfg, "导入结果写入新的 SavedVariables")
    T.eq(Core.GetStatus().importedFrom, "Tate_ASQ")
    T.eq(cfg.showStatus, true, "未导入的键用默认值补齐")
end)

T.test("ImportLegacy: 自动基础值模式不产生覆盖（保持跟随专精表）", function()
    resetWorld()
    _G.AutoSpellQueueDB = nil
    _G.Tate_ASQDB = { enabled = true, baseMode = "auto", manualBase = 180 }
    Core.db = nil
    local cfg = Core.GetConfig()
    T.isNil(cfg.baseOverride, "auto 模式不应留下任何覆盖")
end)

T.test("ImportLegacy: 已存在新配置时不被旧变量覆盖", function()
    resetWorld()
    _G.AutoSpellQueueDB = { enabled = true, baseOverride = 60 }
    _G.Tate_ASQDB = { enabled = false, baseOverride = 999 }
    Core.db = nil
    local cfg = Core.GetConfig()
    T.eq(cfg.enabled, true, "新变量优先")
    T.eq(cfg.baseOverride, 60)
    T.isNil(cfg.importedFrom)
end)

T.test("SetConfig: 未知键拒绝、越界夹紧、noRefresh 生效", function()
    resetWorld()
    local ok, reason = Core.SetConfig("nope", 1)
    T.falsy(ok)
    T.eq(reason, "unknown-key")
    T.isNil(Core.GetConfig().nope)

    -- 已退休的键必须被拒绝，否则旧设置会靠代码路径偷偷复活
    for _, retired in ipairs({ "margin", "hysteresis", "adaptive", "latencySource",
        "baseMode", "manualBase", "minWindow", "maxWindow", "statusFont",
        "statusFontSize", "chatFeedback", "showAdvanced" }) do
        local retiredOk = Core.SetConfig(retired, 123, { noRefresh = true })
        T.falsy(retiredOk, "退休键必须被拒绝: " .. retired)
        T.isNil(Core.GetConfig()[retired], "退休键不得写进配置: " .. retired)
    end

    Stub.worldLatency = 0
    Core.SetConfig("baseOverride", 9999)
    T.eq(Core.GetConfig().baseOverride, 400, "越界值被夹到上限")
    T.eq(Core.lastReason, "config:baseOverride", "SetConfig 默认立即刷新")

    Core.SetConfig("baseOverride", 180, { noRefresh = true })
    T.eq(Core.GetConfig().baseOverride, 180)
    T.eq(Core.lastReason, "config:baseOverride", "noRefresh 不应触发刷新")

    T.truthy(Core.SetConfig("statusBarPos", { x = 1, y = 2 }, { noRefresh = true }))
    T.deepeq(Core.GetConfig().statusBarPos, { x = 1, y = 2 })
    Core.SetConfig("statusBarPos", { x = "bad" }, { noRefresh = true })
    T.isNil(Core.GetConfig().statusBarPos, "坏位置信息被清掉")
end)

T.test("SetBaseOverride: 命令级逃生口的三种输入", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)

    T.truthy(Core.SetBaseOverride(180))
    T.eq(Core.GetConfig().baseOverride, 180)
    -- 改基础值会立刻重算并接管（这正是玩家输入命令后期待的行为）
    T.eq(Core.GetStatus().base, 180, "基础值立即生效")
    T.eq(Stub.CVarValue(), tostring(Core.GetStatus().target))

    T.truthy(Core.SetBaseOverride("auto"))
    T.isNil(Core.GetConfig().baseOverride, "auto 恢复跟随专精表")
    T.eq(Core.GetStatus().base, 245, "回到该专精表的基础值")

    local ok = Core.SetBaseOverride("abc")
    T.falsy(ok, "非数字必须被拒绝")
    T.isNil(Core.GetConfig().baseOverride)
end)

T.test("ResetSettings: 恢复默认但保留所有权与统计", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    applyOnce(300, ExpectedTarget(300))
    local cfg = Core.GetConfig()
    cfg.stats.applied = 7
    cfg.baseOverride = 180
    cfg.showStatus = false

    local ok = Core.ResetSettings()
    T.truthy(ok)
    local after = Core.GetConfig()
    T.truthy(after.ownership and after.ownership.active, "reset 不得丢下已接管的 CVar")
    T.deepeq(after.ownership, {
        active = true, schema = Core.SCHEMA_VERSION, baseline = 150, lastApplied = ExpectedTarget(300), startedAt = 1000,
    }, "ownership 字段必须原样保留（Sanitize 会重建表，内容不变）")
    T.eq(after.stats.applied, 7, "统计不因 reset 归零")
    T.isNil(after.baseOverride, "reset 清掉命令级覆盖，回到跟随专精表")
    T.eq(after.showStatus, true)
    T.eq(after.enabled, true)
    T.eq(after.schemaVersion, Core.SCHEMA_VERSION)
    -- reset 之后即使 baseOverride 没了，所有权仍在：值不会被丢在半路
    T.eq(Core.state, Core.STATE.APPLIED)
end)

T.test("SetEnabled/IsEnabled 与 ticker 生命周期", function()
    resetWorld({ enabled = false })
    Stub.SetCVarValue(150)
    T.falsy(Core.IsEnabled())
    T.isNil(Core.ticker)

    Core.SetEnabled(true)
    T.truthy(Core.IsEnabled())
    T.notNil(Core.ticker, "启用后应启动刷新定时器")
    T.eq(Stub.CVarValue(), "245", "启用立即重新决策并写入")
    T.eq(Core.state, Core.STATE.APPLIED)

    Core.SetEnabled(false)
    T.falsy(Core.IsEnabled())
    T.isNil(Core.ticker, "禁用后应停止定时器")
    T.eq(Stub.CVarValue(), "150", "禁用归还 baseline")
end)

T.test("修复: 归还被推迟或失败时，定时器必须继续跑（否则原地不动就永远不还）", function()
    -- 场景 A：战斗中关闭 → 归还被推迟
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Stub.worldLatency = 100
    Core.Refresh("apply")
    T.eq(Stub.CVarValue(), "245", "先接管并写入")
    T.notNil(Core.ticker)

    Stub.combat = true
    Core.SetEnabled(false)
    T.eq(Core.state, Core.STATE.PENDING, "战斗中禁用应推迟归还")
    T.eq(Stub.CVarValue(), "245", "战斗中不写")
    T.notNil(Core.ticker, "还没归还 → 定时器必须继续（否则玩家原地不动就永远不还）")

    Stub.combat = false
    Core.Refresh("combat-end")
    T.eq(Stub.CVarValue(), "150", "脱战后归还 baseline")
    T.isNil(Core.ticker, "归还完成且已禁用 → 定时器停止")

    -- 场景 B：归还写失败 → 靠定时器重试直到成功
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Core.Refresh("apply")
    T.eq(Stub.CVarValue(), "245")
    Stub.combat = true
    Core.SetEnabled(false)
    T.notNil(Core.ticker, "推迟中定时器仍在")

    Stub.combat = false
    Stub.setCVarMode = "reject-false" -- 归还这一笔写失败
    Core.Refresh("combat-end")
    T.eq(Core.state, Core.STATE.ERROR, "归还失败必须报错而不是静默")
    T.notNil(Core.ticker, "归还失败后必须继续重试")

    Stub.setCVarMode = "normal"
    -- 失败重试走退避（Core.RETRY_INTERVAL），不再每 15 秒轰一次
    Stub.Advance(Core.RETRY_INTERVAL + 1)
    T.eq(Stub.CVarValue(), "150", "定时器重试最终完成归还")
    T.isNil(Core.ticker, "归还完成后定时器停止")
end)

------------------------------------------------------------------------------
--  Snapshot / status / events / timers
------------------------------------------------------------------------------

T.test("Snapshot: 专精、职业、延迟、场景、当前值都读对", function()
    resetWorld()
    Stub.specID = 253
    Stub.specName = "Beast Mastery"
    Stub.classFile = "HUNTER"
    Stub.className = "Hunter"
    Stub.homeLatency = 30
    Stub.worldLatency = 120
    Stub.SetCVarValue(215)
    Stub.mapInfo = { [2022] = { flags = Formula.CITY_MAP_FLAG, parentMapID = 0 } }

    local snap = Core.Snapshot()
    T.eq(snap.specID, 253)
    T.eq(snap.classFile, "HUNTER")
    T.eq(snap.specName, "Beast Mastery")
    T.eq(snap.home, 30)
    T.eq(snap.world, 120)
    T.eq(snap.context, "city")
    T.eq(snap.current, 215)
    T.eq(snap.inCombat, false)
    T.truthy(snap.cvarInfo and snap.cvarInfo.known)
    T.truthy(type(snap.at) == "number")
end)

T.test("Snapshot: 子地图没有城市标记时沿 parentMapID 上溯", function()
    resetWorld()
    Stub.mapID = 10
    Stub.mapInfo = {
        [10] = { flags = 0, parentMapID = 20 },
        [20] = { flags = 0x200000, parentMapID = 30 },
        [30] = { flags = Formula.CITY_MAP_FLAG, parentMapID = 0 },
    }
    local snap = Core.Snapshot()
    T.eq(snap.context, "city")
    T.eq(snap.mapFlags, Formula.CITY_MAP_FLAG, "应返回命中城市标记那一层的 flags")
end)

T.test("Snapshot: 副本优先，战斗中 inCombat 为真", function()
    resetWorld()
    Stub.inInstance = true
    Stub.instanceType = "party"
    Stub.mapInfo = { [2022] = { flags = Formula.CITY_MAP_FLAG, parentMapID = 0 } }
    Stub.combat = true

    local snap = Core.Snapshot()
    T.eq(snap.context, "instance", "IsInInstance 优先于地图标记")
    T.isNil(snap.mapFlags)
    T.eq(snap.inCombat, true)
end)

T.test("GetStatus: 字段齐全（含源码级契约检查），live 与 current 语义不同", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Core.Refresh("apply")

    local status = Core.GetStatus()
    local documented = {
        "enabled", "state", "stateReason", "stateReasonKey", "current", "target",
        "baseline", "lastApplied", "owned", "inCombat", "inWorld", "context", "role",
        "base", "latency", "home", "world", "specID", "specName", "classFile", "cvarInfo",
        "lastError", "lastErrorAt", "applyCount", "repairs", "externalChange",
        "schemaFuture", "importedFrom", "reason",
        -- 采样策略（不再有 refreshSeconds）
        "cadence", "settleReason", "settleSamples", "intervalSeconds", "heartbeatSeconds",
        "converged", "cachedLatency", "cachedLatencyAt", "margin", "hysteresis",
        "jitter", "smoothed", "samples", "stable", "baseOverride",
    }
    -- 数值型字段：直接核对取值
    T.eq(status.target, 245)
    T.eq(status.current, 150, "current 是决策那一刻读到的快照值")
    T.eq(status.live, 245, "live 是刚向客户端读到的实时值（写入之后）")
    T.truthy(status.cadence == "settling" or status.cadence == "fixed"
        or status.cadence == "pending", "cadence 必须是三者之一（实得 " .. tostring(status.cadence) .. "）")
    T.eq(status.reason, "apply")
    T.eq(status.enabled, true)
    T.eq(status.state, Core.STATE.APPLIED)
    T.eq(status.owned, true)
    T.eq(status.inWorld, true)
    T.eq(status.context, "world")
    T.eq(status.home, 0)
    T.eq(status.world, 0)
    T.eq(status.specID, 63)
    T.eq(status.classFile, "MAGE")
    T.isNil(status.stateReason, "成功后没有失败原因")
    T.isNil(status.lastError)

    -- nil 值的字段无法用 pairs() 检测存在性，改为在源码里核对返回表包含这些键
    local source = _G.ASQ_TEST_SOURCES["AutoSpellQueue.lua"]
    T.notNil(source)
    local code = stripComments(source)
    local startIndex = code:find("function Core.GetStatus", 1, true)
    T.notNil(startIndex, "找不到 Core.GetStatus")
    local body = code:sub(startIndex, #code)
    local timersAt = body:find("--  Timers", 1, true)
    if timersAt then body = body:sub(1, timersAt) end
    for _, key in ipairs(documented) do
        T.truthy(body:find("%f[%w]" .. key .. "%s*=") ~= nil,
            "GetStatus() 返回表里缺少文档字段 " .. key)
    end

    Stub.SetCVarValue(77) -- 外部改动，未刷新
    local stale = Core.GetStatus()
    T.eq(stale.live, 77, "live 必须是刚读到的实时值")
    T.eq(stale.current, 150, "current 仍是上一次快照，二者语义不同")
end)

-- 回归锁定（2026-09-28 已修复）：GetStatus() 过去从 Core.lastSnapshot 取
-- role/base/latency，而 lastSnapshot 是 Core.Snapshot() 的原始游戏快照，
-- 里面没有这三个字段（它们只存在于 Core.Decide() 的 action 上，Execute 只用了
-- action.target）。于是三个字段恒为 nil，ARCHITECTURE §5 的
-- LABEL_ROLE / LABEL_BASE / LABEL_LATENCY（设置页“计算式”）拿不到数据。
-- 最小复现（当时）：Core.Refresh("x") 之后 Core.GetStatus().role == nil。
T.test("GetStatus 的 role/base/latency 必须来自最近一次决策", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Stub.worldLatency = 120
    Core.Refresh("apply")

    local status = Core.GetStatus()
    T.eq(status.role, "ranged")
    T.eq(status.base, 245, "Fire 的基础值")
    T.eq(status.latency, 120, "世界延迟")
    T.eq(status.context, "world")
    T.eq(status.target, 245)

    -- 换场景/换专精后必须跟着变，而不是留着第一次决策的旧值
    Stub.worldLatency = 400
    Core.Refresh("latency-change")
    T.eq(Core.GetStatus().latency, 400)
    T.eq(Core.GetStatus().target, 400, "245 基础 vs 400+50 -> 夹到上限 400")
end)

T.test("Core.L 无 Locale 时回退 key，ns.L 存在时使用翻译", function()
    resetWorld()
    -- ns.L is normally installed by AutoSpellQueue_Locale.lua; the core must
    -- still work (and return the key) when it is missing, so nil it out here.
    local saved = ns.L
    ns.L = nil
    T.eq(Core.L("CHAT_CHANGED"), "CHAT_CHANGED")
    T.eq(Core.L("ERR_COMBAT"), "ERR_COMBAT")

    ns.L = function(key) return "T:" .. key end
    T.eq(Core.L("ANYTHING"), "T:ANYTHING")

    ns.L = saved
end)

T.test("REASON_KEY 覆盖全部 CVar 失败原因", function()
    local reasons = {
        CVar.ERR_READONLY, CVar.ERR_COMBAT, CVar.ERR_UNAVAILABLE, CVar.ERR_REJECTED,
        CVar.ERR_VERIFY, CVar.ERR_NO_API, CVar.ERR_INVALID_VALUE,
    }
    for _, reason in ipairs(reasons) do
        T.truthy(type(Core.REASON_KEY[reason]) == "string", "REASON_KEY 缺少 " .. reason)
    end
    T.eq(Core.REASON_KEY[CVar.ERR_VERIFY], "ERR_VERIFY_FAILED")
end)

T.test("未进入世界时 Refresh 什么都不做", function()
    resetWorld()
    Core.inWorld = false
    Core.state = Core.STATE.IDLE
    local before = Stub.CVarValue()
    T.isNil(Core.Refresh("early"))
    T.eq(#Stub.writes, 0)
    T.eq(Stub.CVarValue(), before)
    T.eq(Core.state, Core.STATE.IDLE)
end)

T.test("事件: ADDON_LOADED 只认自己的名字", function()
    resetWorld()
    -- Core 和 Options 都监听这个事件，所以只断言“有人处理 + Core 的行为正确”
    T.truthy(Stub.FireEvent("ADDON_LOADED", "SomeOtherAddon") >= 1, "事件框架应已注册")
    T.isNil(Core.initialized, "别的插件加载不得初始化")
    T.truthy(Stub.FireEvent("ADDON_LOADED", "AutoSpellQueue") >= 1)
    T.eq(Core.initialized, true)
end)

T.test("事件: 专精变更只处理 player", function()
    resetWorld()
    Core.lastReason = nil
    Stub.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "party1")
    T.isNil(Core.lastReason, "队友换专精不该刷新")
    Stub.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    T.eq(Core.lastReason, "spec")
    Stub.FireEvent("PLAYER_SPECIALIZATION_CHANGED", nil)
    T.eq(Core.lastReason, "spec", "nil 参数按玩家处理")
end)

T.test("事件: 区域变化触发刷新", function()
    resetWorld()
    Core.lastReason = nil
    Stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    T.eq(Core.lastReason, "zone")
    Stub.FireEvent("ZONE_CHANGED")
    T.eq(Core.lastReason, "zone-changed")
end)

T.test("事件: CVAR_UPDATE 去抖 0.5 秒，且忽略别的 CVar", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Core.Refresh("apply")
    Stub.ClearWrites()
    Core.lastReason = nil

    Stub.FireEvent("CVAR_UPDATE", "SomeOtherCVar")
    T.eq(PendingNonTicker(), 0, "别的 CVar 不该排定时器")
    T.isNil(Core.lastReason)

    Stub.FireEvent("CVAR_UPDATE", CVar.NAME)
    T.eq(PendingNonTicker(), 1)
    T.isNil(Core.lastReason, "不是立刻刷新（去抖）")
    Stub.Advance(0.6)
    T.eq(Core.lastReason, "cvar-update")
end)

T.test("采样策略: 学习期密集采样，稳定后停止轮询（不再每 15 秒读一次）", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Stub.worldLatency = 100

    Stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(Stub.CVarValue(), "245", "Fire 基础 245，延迟 100 加余量后仍不超过它")
    T.truthy(Core.settling, "进入世界后应处于学习期")
    T.eq(Core.DesiredInterval(), Core.SETTLE_INTERVAL, "学习期用密集间隔")
    T.eq(Core.tickerInterval, Core.SETTLE_INTERVAL)

    Stub.Advance(41) -- 暖机定时器全部跑完
    T.eq(Stub.PendingTimers(), 1, "暖机结束后只剩 ticker")

    -- 延迟一直没变 → 平滑值不再移动 → 学习期结束
    T.falsy(Core.settling, "读数稳定后必须结束学习期")
    T.truthy(Core.GetStatus().converged, "应判定为已收敛")
    T.eq(Core.DesiredInterval(), Core.HEARTBEAT_SECONDS,
        "稳定后只保留心跳（实得 " .. tostring(Core.DesiredInterval()) .. " 秒）")
    T.eq(Core.tickerInterval, Core.HEARTBEAT_SECONDS, "定时器必须换成心跳间隔")
    T.truthy(Core.HEARTBEAT_SECONDS >= Core.SETTLE_INTERVAL * 10,
        "心跳至少要比学习期稀疏一个数量级")

    -- 心跳到点但延迟没动：不写、不重新决策
    Stub.ClearWrites()
    Stub.Advance(Core.HEARTBEAT_SECONDS + 1)
    T.eq(#Stub.writes, 0, "心跳发现没漂移时不得写 CVar")
    T.truthy(Core.heartbeatSteady, "应记录为「稳定」而不是重新学习")
    T.eq(Core.lastReason, "ticker", "心跳走的是 ticker 路径")

    -- 延迟真的漂移了 → 重新学习并跟着改
    Stub.worldLatency = 320
    Stub.Advance(Core.HEARTBEAT_SECONDS + 1)
    T.truthy(Core.settling, "漂移超过阈值后必须重新学习")
    Stub.Advance(Core.SETTLE_INTERVAL * (Core.MAX_SETTLE_SAMPLES + 2))
    local written = tonumber(Stub.writes[#Stub.writes] and Stub.writes[#Stub.writes].value)
    T.notNil(written, "延迟大幅上升后必须写入新值")
    T.truthy(written > 245, "目标必须跟着上升（实得 " .. tostring(written) .. "）")
    T.inRange(written, Core.WINDOW_MIN, Core.WINDOW_MAX)
    T.eq(Stub.CVarValue(), tostring(written))
end)

T.test("采样策略: 进入副本 / 团本会重新采样一次", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Stub.worldLatency = 100
    Stub.FireEvent("PLAYER_ENTERING_WORLD")
    Stub.Advance(41)
    T.falsy(Core.settling, "先进入稳定状态")
    T.eq(Core.tickerInterval, Core.HEARTBEAT_SECONDS)

    -- 进副本：客户端会发 ZONE_CHANGED_NEW_AREA + PLAYER_ENTERING_WORLD
    Stub.inInstance = true
    Stub.instanceType = "party"
    Stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.truthy(Core.settling, "进副本必须重新采样")
    T.eq(Core.settleReason, "enter-world")
    T.eq(Core.tickerInterval, Core.SETTLE_INTERVAL, "学习期立刻恢复密集采样")

    Stub.Advance(41)
    T.falsy(Core.settling, "副本里读数稳定后再次停止轮询")
    T.eq(Core.tickerInterval, Core.HEARTBEAT_SECONDS)

    -- 换区（野外 → 野外）同样重测一次
    Stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    T.truthy(Core.settling, "换区也要重新采样")
    T.eq(Core.settleReason, "zone")
end)

T.test("采样策略: 登录时先用记住的延迟，不等 GetNetStats", function()
    -- 上一次会话学到了 300ms
    resetWorld({ enabled = true, latencyCache = { value = 300, jitter = 0, samples = 5, at = 1000 } })
    Stub.SetCVarValue(150)
    Stub.worldLatency = 0 -- 客户端还没报出延迟（登录初期的真实情况）
    Stub.homeLatency = 0

    Stub.FireEvent("PLAYER_ENTERING_WORLD")
    local target = tonumber(Stub.CVarValue())
    T.truthy(target and target > 245,
        "必须用记住的延迟立刻算出目标，而不是先写一个偏低的 245（实得 " .. tostring(target) .. "）")
    T.inRange(target, Core.WINDOW_MIN, Core.WINDOW_MAX)

    -- 客户端随后报出真实延迟：学习期会把它校准过来
    Stub.worldLatency = 100
    Stub.Advance(41)
    T.falsy(Core.settling, "校准后结束学习期")
    local status = Core.GetStatus()
    T.eq(status.cachedLatency, 100, "记住的延迟必须更新为实测值")
    T.truthy(status.cachedLatencyAt ~= nil, "要记住学到的时间")
end)

T.test("暖机: 延迟未知时按计划重试，拿到延迟后停止重试", function()
    resetWorld({ enabled = true })
    Stub.SetCVarValue(150)
    Stub.worldLatency = 0
    Stub.homeLatency = 0
    Core.inWorld = true
    Core.Refresh("enter-world")
    T.eq(Stub.CVarValue(), "245")
    Core.ScheduleWarmup()

    Stub.ClearWrites()
    Stub.Advance(11) -- 2s / 5s / 10s 三次重试，都还没拿到延迟
    T.eq(#Stub.writes, 0, "目标没变就不写")
    T.eq(PendingNonTicker(), 1, "延迟未知时应继续排下一次重试")

    Stub.worldLatency = 300
    Stub.Advance(10) -- 命中 20s 那一步
    T.eq(Stub.CVarValue(), tostring(ExpectedTarget(300)), "重试必须使用刚拿到的延迟")
    T.eq(PendingNonTicker(), 0, "拿到延迟后不再重试")
    T.notNil(Core.ticker, "启用状态下周期刷新继续存在（与暖机重试是两件事）")
end)

------------------------------------------------------------------------------
--  Structural invariants
------------------------------------------------------------------------------

T.test("结构: 除 CVar.lua 外没有文件直接碰 SpellQueueWindow / C_CVar", function()
    local sources = _G.ASQ_TEST_SOURCES
    T.notNil(sources)
    local rules = {
        { "C_CVar", "C_CVar" },
        { "SetCVar%s*%(", "SetCVar(" },
        { "GetCVar", "GetCVar" },
        { '"SpellQueueWindow"', "SpellQueueWindow 字面量" },
    }
    local targets = {
        "AutoSpellQueue.lua",
        "AutoSpellQueue_Formula.lua",
        "AutoSpellQueue_Options.lua",
        "AutoSpellQueue_Locale.lua",
    }
    local checked = 0
    for _, name in ipairs(targets) do
        local source = sources[name]
        if source then
            checked = checked + 1
            local code = stripComments(source)
            for _, rule in ipairs(rules) do
                local _, count = code:gsub(rule[1], "")
                T.eq(count, 0, name .. " 不应直接出现 " .. rule[2])
            end
        end
    end
    T.truthy(checked >= 2, "至少应检查核心与 Formula 两个文件")

    local cvarCode = stripComments(sources["AutoSpellQueue_CVar.lua"])
    T.truthy(cvarCode:find("SpellQueueWindow", 1, true) ~= nil, "CVar.lua 才是唯一读写点")
    T.truthy(cvarCode:find("GetCVarInfo", 1, true) ~= nil)
end)

T.test("结构: 配置白名单必须正好是「玩家能决定的 + 插件自己的账本」", function()
    -- 这条用例是「设置不许悄悄长回来」的守门人：新增任何配置键都必须先
    -- 说明它为什么必须由玩家决定，否则就该是算法常量。
    local expected = {
        schemaVersion = true,
        enabled = true,        -- 玩家：总开关
        showStatus = true,     -- 玩家：要不要显示读数
        statusBarPos = true,   -- 插件账本：状态条位置（拖动产生）
        baseOverride = true,   -- 逃生口：仅 /asq base 写入
        ownership = true,      -- 插件账本：接管状态
        stats = true,          -- 插件账本：统计
    }
    local actual = {}
    for key in pairs(Core.DEFAULTS) do actual[key] = true end
    for key in pairs(expected) do
        T.truthy(Core.DEFAULTS[key] ~= nil or key == "statusBarPos" or key == "baseOverride"
            or key == "ownership" or key == "stats", "DEFAULTS 缺少 " .. key)
    end
    for key in pairs(actual) do
        T.truthy(expected[key], "出现了未经审阅的配置键: " .. key ..
            "（如果玩家不需要决定它，就应该是算法常量而不是设置）")
    end

    -- 玩家可见的设置必须只有两个开关（面板里也只允许有这两个）
    local playerKeys = {}
    for key in pairs(Core.DEFAULTS) do
        if key == "enabled" or key == "showStatus" then playerKeys[#playerKeys + 1] = key end
    end
    T.eq(#playerKeys, 2, "玩家可见设置必须恰好两个：enabled / showStatus")

    T.eq(Core.SV, "AutoSpellQueueDB")
    T.eq(Core.LEGACY_SV, "Tate_ASQDB")
    T.eq(Core.NAME, "AutoSpellQueue")
    T.eq(Core.SCHEMA_VERSION, 2, "schema v2 = 只留两个设置")
    T.eq(Core.STATE.IDLE, "idle")
    T.eq(Core.STATE.DISABLED, "disabled")
    T.eq(Core.STATE.APPLIED, "applied")
    T.eq(Core.STATE.PENDING, "pending")
    T.eq(Core.STATE.ERROR, "error")
    T.eq(Core.STATE.UNAVAILABLE, "unavailable")
end)
