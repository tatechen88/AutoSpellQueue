------------------------------------------------------------------------------
--  tests/spec_formula.lua -- ns.Formula
--
--  The formula module is the only place that decides "what value should
--  SpellQueueWindow have". It must be pure (docs/ARCHITECTURE.md section 2:
--  Formula is forbidden from calling any WoW API) and must never return nil.
------------------------------------------------------------------------------
local T, ns, Stub = ...
local F = ns.Formula
local ROOT = _G.ASQ_TEST_ROOT or "."

T.spec("spec_formula")

------------------------------------------------------------------------------
--  Fixtures
------------------------------------------------------------------------------

-- specID, classFile, expected base (ms), expected role
local SPECS = {
    { 250, "DEATHKNIGHT", 160, "melee" },
    { 251, "DEATHKNIGHT", 150, "melee" },
    { 252, "DEATHKNIGHT", 150, "melee" },
    { 577, "DEMONHUNTER", 145, "melee" },
    { 581, "DEMONHUNTER", 160, "melee" },
    { 1480, "DEMONHUNTER", 145, "melee" },
    { 102, "DRUID", 230, "ranged" },
    { 103, "DRUID", 145, "melee" },
    { 104, "DRUID", 150, "melee" },
    { 105, "DRUID", 220, "ranged" },
    { 1467, "EVOKER", 230, "ranged" },
    { 1468, "EVOKER", 220, "ranged" },
    { 1473, "EVOKER", 235, "ranged" },
    { 253, "HUNTER", 190, "ranged" },
    { 254, "HUNTER", 210, "ranged" },
    { 255, "HUNTER", 160, "melee" },
    { 62, "MAGE", 235, "ranged" },
    { 63, "MAGE", 245, "ranged" },
    { 64, "MAGE", 240, "ranged" },
    { 268, "MONK", 150, "melee" },
    { 269, "MONK", 140, "melee" },
    { 270, "MONK", 180, "melee" },
    { 65, "PALADIN", 230, "ranged" },
    { 66, "PALADIN", 150, "melee" },
    { 70, "PALADIN", 150, "melee" },
    { 256, "PRIEST", 220, "ranged" },
    { 257, "PRIEST", 220, "ranged" },
    { 258, "PRIEST", 225, "ranged" },
    { 259, "ROGUE", 140, "melee" },
    { 260, "ROGUE", 145, "melee" },
    { 261, "ROGUE", 140, "melee" },
    { 262, "SHAMAN", 220, "ranged" },
    { 263, "SHAMAN", 150, "melee" },
    { 264, "SHAMAN", 220, "ranged" },
    { 265, "WARLOCK", 240, "ranged" },
    { 266, "WARLOCK", 240, "ranged" },
    { 267, "WARLOCK", 245, "ranged" },
    { 71, "WARRIOR", 150, "melee" },
    { 72, "WARRIOR", 150, "melee" },
    { 73, "WARRIOR", 160, "melee" },
}

-- classFile -> { melee = <class base>, ranged = <class base> }; missing role = FALLBACK
local CLASS_BASE = {
    DEATHKNIGHT = { melee = 150 },
    DEMONHUNTER = { melee = 145 },
    DRUID = { melee = 145, ranged = 225 },
    EVOKER = { ranged = 230 },
    HUNTER = { melee = 160, ranged = 200 },
    MAGE = { ranged = 240 },
    MONK = { melee = 140 },
    PALADIN = { melee = 150, ranged = 230 },
    PRIEST = { ranged = 225 },
    ROGUE = { melee = 140 },
    SHAMAN = { melee = 150, ranged = 220 },
    WARLOCK = { ranged = 240 },
    WARRIOR = { melee = 150 },
}
local FALLBACK = { melee = 150, ranged = 220 }

local function autoCfg(extra)
    local cfg = { baseMode = "auto", adaptive = true, latencySource = "world", margin = 50,
        minWindow = 50, maxWindow = 400 }
    for key, value in pairs(extra or {}) do cfg[key] = value end
    return cfg
end

------------------------------------------------------------------------------
--  Clamp / Round / SafeNumber
------------------------------------------------------------------------------

T.test("Clamp 上下限、交换边界、非数字输入", function()
    T.eq(F.Clamp(500, 0, 400), 400)
    T.eq(F.Clamp(-5, 0, 400), 0)
    T.eq(F.Clamp(200, 0, 400), 200)
    T.eq(F.Clamp(200, 400, 0), 200, "交换过的边界也要容忍")
    T.eq(F.Clamp(0, 400, 0), 0)
    T.eq(F.Clamp(nil, 50, 400), 50)
    T.eq(F.Clamp("abc", 50, 400), 50)
    T.eq(F.Clamp("200", 50, 400), 200)
    T.eq(F.Clamp(1 / 0, 0, 400), 400, "inf 被夹到上限")
    T.eq(F.Clamp(-1 / 0, 0, 400), 0, "-inf 被夹到下限")
end)

-- 回归锁定（2026-09-28 已修复）：Clamp 曾经对 NaN 输入返回 NaN，与函数注释
-- 「Swapped bounds are tolerated (never returns NaN)」矛盾。
-- 最小复现（当时）：Formula.Clamp(0/0, 50, 400) == NaN。
-- 现在这里是硬门禁：再退化就会红。
T.test("Clamp(NaN) 的结果必须是有限数字（文档承诺 never returns NaN）", function()
    T.inRange(F.Clamp(0 / 0, 50, 400), 50, 400, "Clamp(NaN, 50, 400)")
    T.inRange(F.Clamp(0 / 0, 400, 50), 50, 400, "交换边界 + NaN")
    T.inRange(F.Clamp(0 / 0, 0, 0), 0, 0, "上下限相同")
    T.inRange(F.Clamp(1 / 0, 50, 400), 50, 400, "+inf 夹到上限")
    T.inRange(F.Clamp(-1 / 0, 50, 400), 50, 400, "-inf 夹到下限")
end)

T.test("Round 取整到整数毫秒", function()
    T.eq(F.Round(199.4), 199)
    T.eq(F.Round(199.5), 200)
    T.eq(F.Round("150"), 150)
    T.eq(F.Round(nil), 0)
    T.eq(F.Round(-0.4), 0)
end)

T.test("SafeNumber: nil/NaN/inf/字符串归零，数字透传", function()
    T.eq(F.SafeNumber(nil), 0)
    T.eq(F.SafeNumber("abc"), 0)
    T.eq(F.SafeNumber(0 / 0), 0, "NaN -> 0")
    T.eq(F.SafeNumber(1 / 0), 0, "+inf -> 0")
    T.eq(F.SafeNumber(-1 / 0), 0, "-inf -> 0")
    T.eq(F.SafeNumber("12.5"), 12.5)
    T.eq(F.SafeNumber(7), 7)
    T.eq(F.SafeNumber(0), 0)
    T.eq(F.SafeNumber(-7), -7, "负值本身不归零（由 Clamp 负责夹紧）")
end)

------------------------------------------------------------------------------
--  HasFlag
------------------------------------------------------------------------------

T.test("HasFlag: 位测试不依赖 bit 库", function()
    local city = F.CITY_MAP_FLAG
    T.eq(city, 0x100000, "CITY_MAP_FLAG == Enum.UIMapFlag.IsCityMap")
    T.truthy(F.HasFlag(city, city))
    T.truthy(F.HasFlag(0x300000, city), "0x300000 含 0x100000 位")
    T.falsy(F.HasFlag(0x200000, city))
    T.truthy(F.HasFlag(0x300000, 0x200000))
    T.falsy(F.HasFlag(0, city))
    T.falsy(F.HasFlag(city, 0), "flag 为 0 -> false")
    T.falsy(F.HasFlag(nil, city))
    T.falsy(F.HasFlag(city, nil))
    T.falsy(F.HasFlag(-1, city), "负数不是合法位域")
    T.falsy(F.HasFlag(city, -1))
    T.truthy(F.HasFlag("1048576", "1048576"), "字符串数字也接受")
end)

------------------------------------------------------------------------------
--  Spec classification and base values
------------------------------------------------------------------------------

T.test("每个职业/专精都有确定的基础值与定位（无 nil 回退）", function()
    local seen = {}
    for _, row in ipairs(SPECS) do
        local specID, classFile, base, role = row[1], row[2], row[3], row[4]
        T.falsy(seen[specID], "专精 " .. specID .. " 在测试表里重复")
        seen[specID] = true
        T.eq(F.GetBase(autoCfg(), specID, classFile), base, "spec " .. specID .. " base")
        T.eq(F.Classify(specID, classFile), role, "spec " .. specID .. " role")
        T.truthy(F.IsKnownSpec(specID), "spec " .. specID .. " 应被识别")
    end
    T.eq(#SPECS, 40, "覆盖了 40 个专精（13 职业）")
end)

T.test("未知专精回退到职业值（按定位）", function()
    T.eq(F.GetBase(autoCfg(), 999999, "WARRIOR"), 150, "未知专精 + 近战职业 -> 职业近战值")
    T.eq(F.GetBase(autoCfg(), 999999, "MAGE"), 240)
    T.eq(F.GetBase(autoCfg(), 999999, "HUNTER"), 200, "未知专精 -> 远程定位 -> 职业远程值")
    T.eq(F.GetBase(autoCfg(), 0, "PRIEST"), 225)
    T.eq(F.GetBase(autoCfg(), -1, "DRUID"), 225, "非法 specID 按未知处理")
    T.falsy(F.IsKnownSpec(999999))
    T.falsy(F.IsKnownSpec(nil))
    T.falsy(F.IsKnownSpec("63"), "只接受数字 specID")
end)

T.test("未知职业 / nil 输入回退到 FALLBACK（永不 nil）", function()
    T.eq(F.GetBase(autoCfg(), nil, nil), FALLBACK.ranged)
    T.eq(F.GetBase(autoCfg(), 999999, "FOO"), FALLBACK.ranged)
    T.eq(F.GetBase(autoCfg(), 999999, "DEATHKNIGHT"), 150, "近战职业类回退")
    T.eq(F.GetBase(nil, nil, nil), FALLBACK.ranged, "cfg 为 nil 也要能算")
    T.eq(F.GetBase(autoCfg(), nil, "EVOKER"), 230)
    T.eq(F.Classify(999999, "ROGUE"), "melee")
    T.eq(F.Classify(999999, "FOO"), "ranged")
    T.eq(F.Classify(nil, nil), "ranged")
end)

T.test("每个职业的 CLASS_BASE 都能被未知专精取到", function()
    for classFile, entry in pairs(CLASS_BASE) do
        local role = F.Classify(999999, classFile)
        local expected = entry[role] or FALLBACK[role]
        T.eq(F.GetBase(autoCfg(), 999999, classFile), expected, classFile .. " (" .. role .. ")")
    end
end)

T.test("baseMode=manual 使用 manualBase，非法值回退", function()
    T.eq(F.GetBase({ baseMode = "manual", manualBase = 200 }, 63, "MAGE"), 200)
    T.eq(F.GetBase({ baseMode = "manual", manualBase = "180" }, 63, "MAGE"), 180)
    T.eq(F.GetBase({ baseMode = "manual", manualBase = 0 }, 63, "MAGE"), FALLBACK.ranged, "0 视为未设置")
    T.eq(F.GetBase({ baseMode = "manual", manualBase = -10 }, 63, "MAGE"), FALLBACK.ranged)
    T.eq(F.GetBase({ baseMode = "manual", manualBase = "abc" }, 63, "MAGE"), FALLBACK.ranged)
    T.eq(F.GetBase({ baseMode = "manual", manualBase = 0 / 0 }, 63, "MAGE"), FALLBACK.ranged)
    T.eq(F.GetBase({ baseMode = "manual", manualBase = 1 / 0 }, 63, "MAGE"), FALLBACK.ranged)
    T.eq(F.GetBase({ baseMode = "auto" }, 63, "MAGE"), 245, "auto 模式忽略 manualBase")
end)

------------------------------------------------------------------------------
--  Context and latency
------------------------------------------------------------------------------

T.test("ClassifyContext: 城市 / 副本 / 野外", function()
    T.eq(F.ClassifyContext(false, F.CITY_MAP_FLAG), "city")
    T.eq(F.ClassifyContext(false, 0x100000 + 0x200000), "city", "多个 flag 同时置位")
    T.eq(F.ClassifyContext(false, 0), "world")
    T.eq(F.ClassifyContext(false, nil), "world")
    T.eq(F.ClassifyContext(true, F.CITY_MAP_FLAG), "instance", "副本优先于城市标记")
    T.eq(F.ClassifyContext(true, nil), "instance")
    T.eq(F.ClassifyContext(nil, nil), "world")
end)

T.test("PickLatency: world/home/avg/max 四选一", function()
    T.eq(F.PickLatency("world", 40, 80), 80)
    T.eq(F.PickLatency("home", 40, 80), 40)
    T.eq(F.PickLatency("avg", 40, 80), 60)
    T.eq(F.PickLatency("max", 40, 80), 80)
    T.eq(F.PickLatency("max", 80, 40), 80)

    T.eq(F.PickLatency("world", 40, 0), 40, "world 不可用时回退 home")
    T.eq(F.PickLatency("world", 0, 0), 0)
    T.eq(F.PickLatency("home", 0, 80), 0, "home 源不偷偷回退 world")
    T.eq(F.PickLatency("avg", 0, 80), 40)
    T.eq(F.PickLatency("bogus", 40, 80), 80, "未知来源按默认 world 处理")
    T.eq(F.PickLatency(nil, 40, 80), 80)
    T.eq(F.PickLatency("world", "abc", 0 / 0), 0, "脏输入归零")
    T.eq(F.PickLatency("max", 1 / 0, 80), 80, "inf 归零后取另一个有效值")
    T.eq(F.PickLatency("avg", 1 / 0, 0 / 0), 0)
end)

------------------------------------------------------------------------------
--  ComputeTarget
------------------------------------------------------------------------------

T.test("ComputeTarget: 城市直接使用基础值，不吃延迟", function()
    local cfg = autoCfg()
    local target, role, base, latency = F.ComputeTarget(cfg, 63, "MAGE", 30, 200, "city")
    T.eq(target, 245)
    T.eq(role, "ranged")
    T.eq(base, 245)
    T.eq(latency, 200, "延迟仍然会被返回，只是不参与城市计算")
end)

T.test("ComputeTarget: 副本与野外都做延迟自适应", function()
    local cfg = autoCfg()
    -- 245 base vs 200 + 50 margin = 250
    T.eq(F.ComputeTarget(cfg, 63, "MAGE", 30, 200, "instance"), 250)
    T.eq(F.ComputeTarget(cfg, 63, "MAGE", 30, 200, "world"), 250)
    -- low latency: base wins
    T.eq(F.ComputeTarget(cfg, 63, "MAGE", 10, 20, "world"), 245)
    T.eq(F.ComputeTarget(cfg, 63, "MAGE", 10, 20, "instance"), 245)
    -- high latency: latency + margin wins
    T.eq(F.ComputeTarget(cfg, 259, "ROGUE", 0, 300, "world"), 350)
end)

T.test("ComputeTarget: adaptive=false 只用基础值", function()
    local cfg = autoCfg({ adaptive = false })
    T.eq(F.ComputeTarget(cfg, 259, "ROGUE", 0, 300, "world"), 140)
    T.eq(F.ComputeTarget(cfg, 259, "ROGUE", 0, 300, "instance"), 140)
    T.eq(F.ComputeTarget(cfg, 63, "MAGE", 0, 300, "world"), 245)
end)

T.test("ComputeTarget: 四种 latencySource 都生效", function()
    local home, world = 300, 50
    T.eq(F.ComputeTarget(autoCfg({ latencySource = "home" }), 63, "MAGE", home, world, "world"), 350)
    T.eq(F.ComputeTarget(autoCfg({ latencySource = "world" }), 63, "MAGE", home, world, "world"), 245)
    T.eq(F.ComputeTarget(autoCfg({ latencySource = "avg" }), 63, "MAGE", home, world, "world"), 245)
    T.eq(F.ComputeTarget(autoCfg({ latencySource = "max" }), 63, "MAGE", home, world, "world"), 350)
    T.eq(F.ComputeTarget(autoCfg({ latencySource = "avg" }), 63, "MAGE", 400, 400, "world"), 400)
end)

T.test("ComputeTarget: clamp 上下限", function()
    T.eq(F.ComputeTarget(autoCfg({ maxWindow = 400 }), 63, "MAGE", 0, 1000, "world"), 400, "上限 400")
    T.eq(F.ComputeTarget(autoCfg({ margin = 300 }), 63, "MAGE", 0, 1000, "world"), 400, "margin 推高后仍被夹")
    T.eq(F.ComputeTarget(autoCfg({ minWindow = 250, margin = 0 }), 63, "MAGE", 0, 0, "world"), 250, "下限 250")
    T.eq(F.ComputeTarget(autoCfg({ maxWindow = 100 }), 63, "MAGE", 0, 0, "world"), 100, "上限 100")
    T.eq(F.ComputeTarget(autoCfg({ minWindow = 400, maxWindow = 100 }), 63, "MAGE", 0, 0, "world"), 245,
        "上下限写反时按交换处理，不产生异常值")
end)

T.test("ComputeTarget: 脏输入（NaN/inf/负数/字符串）不产生越界或非有限值", function()
    local cases = {
        { home = 0 / 0, world = 1 / 0, margin = 50 },
        { home = -100, world = -50, margin = 50 },
        { home = "abc", world = nil, margin = "abc" },
        { home = 1 / 0, world = -1 / 0, margin = 1 / 0 },
        { home = nil, world = nil, margin = nil },
    }
    for index, extra in ipairs(cases) do
        local cfg = autoCfg(extra)
        for _, context in ipairs({ "city", "instance", "world" }) do
            for _, spec in ipairs({ 63, 259, 999999 }) do
                local target = F.ComputeTarget(cfg, spec, "MAGE", cfg.home, cfg.world, context)
                T.inRange(target, 50, 400,
                    ("case %d spec %d %s"):format(index, spec, context))
            end
        end
    end
end)

T.test("ComputeTarget: 迟滞不在公式层（公式是纯函数，每次给出同一个值）", function()
    local cfg = autoCfg()
    local a = F.ComputeTarget(cfg, 63, "MAGE", 10, 100, "world")
    local b = F.ComputeTarget(cfg, 63, "MAGE", 10, 100, "world")
    T.eq(a, b, "同样的输入必须给出同样的输出")
    T.eq(F.ComputeTarget(cfg, 63, "MAGE", 10, 100, "world"), 245)
end)

T.test("Describe 与 ComputeTarget 的说明一致", function()
    local cfg = autoCfg()
    local kind, base, latency, margin = F.Describe(cfg, 63, "MAGE", 30, 200, "city")
    T.eq(kind, "city")
    T.eq(base, 245)
    T.eq(latency, 200)
    T.eq(margin, 50)

    kind = F.Describe(cfg, 63, "MAGE", 30, 200, "world")
    T.eq(kind, "adaptive")

    kind = F.Describe(autoCfg({ adaptive = false }), 63, "MAGE", 30, 200, "world")
    T.eq(kind, "base")

    local _, _, _, dirtyMargin = F.Describe(autoCfg({ margin = "abc" }), 63, "MAGE", 0, 0, "city")
    T.eq(dirtyMargin, 0)
end)

------------------------------------------------------------------------------
--  Purity: Formula must not touch the game API
------------------------------------------------------------------------------

local function stripLuaComments(source)
    local text = source:gsub("%-%-%[=*%[.-%]=*%]", " ")
    text = text:gsub("%-%-[^\n]*", " ")
    return text
end

T.test("源码扫描：Formula 不含任何 WoW API / 全局副作用", function()
    local sources = _G.ASQ_TEST_SOURCES
    T.notNil(sources, "run-tests.mjs 应通过 ASQ_TEST_SOURCES 提供源码文本")
    local source = sources["AutoSpellQueue_Formula.lua"]
    T.notNil(source, "ASQ_TEST_SOURCES 里应有 AutoSpellQueue_Formula.lua")
    T.truthy(#source > 1000, "源码读入长度异常: " .. tostring(#source))

    local code = stripLuaComments(source)
    local forbidden = {
        { "C_%u%w*%s*%.", "C_* 命名空间" },
        { "GetCVar", "GetCVar" },
        { "SetCVar", "SetCVar" },
        { "GetNetStats", "GetNetStats" },
        { "CreateFrame", "CreateFrame" },
        { "UnitClass", "UnitClass" },
        { "IsInInstance", "IsInInstance" },
        { "InCombatLockdown", "InCombatLockdown" },
        { "GetLocale", "GetLocale" },
        { "GetTime", "GetTime" },
        { "GetSpecialization", "GetSpecialization" },
        { "DEFAULT_CHAT_FRAME", "DEFAULT_CHAT_FRAME" },
        { "UIParent", "UIParent" },
        { "_G%s*[%.:%[]", "_G 全局访问" },
        { "GetSpellInfo", "GetSpellInfo" },
        { "hooksecurefunc", "hooksecurefunc" },
    }
    for _, rule in ipairs(forbidden) do
        local _, count = code:gsub(rule[1], "")
        T.eq(count, 0, "AutoSpellQueue_Formula.lua 不应出现 " .. rule[2])
    end
end)

T.test("运行期：把所有 WoW API 换成陷阱后 Formula 仍能工作", function()
    local traps = {
        "CreateFrame", "UIParent", "C_CVar", "C_Map", "C_Timer", "C_SpecializationInfo",
        "GetNetStats", "UnitClass", "IsInInstance", "InCombatLockdown", "GetLocale",
        "GetTime", "time", "GetCVar", "SetCVar", "DEFAULT_CHAT_FRAME",
        "GetSpecialization", "GetSpecializationInfo", "GetSpellInfo", "hooksecurefunc",
    }
    local saved = {}
    for _, name in ipairs(traps) do
        saved[name] = _G[name]
        _G[name] = setmetatable({}, {
            __index = function() error("Formula 读取了 WoW API: " .. name) end,
            __newindex = function() error("Formula 写入了 WoW API: " .. name) end,
            __call = function() error("Formula 调用了 WoW API: " .. name) end,
        })
    end

    local okRun, err = pcall(function()
        local cfg = autoCfg()
        for _, row in ipairs(SPECS) do
            F.GetBase(cfg, row[1], row[2])
            F.Classify(row[1], row[2])
            F.IsKnownSpec(row[1])
            F.Describe(cfg, row[1], row[2], 30, 200, "world")
            F.ComputeTarget(cfg, row[1], row[2], 30, 200, "instance")
            F.ComputeTarget(cfg, row[1], row[2], 30, 200, "city")
        end
        F.Clamp(1, 2, 3)
        F.Round(1.5)
        F.SafeNumber("1")
        F.HasFlag(F.CITY_MAP_FLAG, F.CITY_MAP_FLAG)
        F.ClassifyContext(false, F.CITY_MAP_FLAG)
        F.PickLatency("avg", 1, 2)
    end)

    for _, name in ipairs(traps) do _G[name] = saved[name] end
    T.ok(okRun, "Formula 必须是纯函数模块，实际报错: " .. tostring(err))
end)
