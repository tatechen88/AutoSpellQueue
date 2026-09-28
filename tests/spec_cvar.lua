------------------------------------------------------------------------------
--  tests/spec_cvar.lua -- ns.CVar
--
--  The P1 fix this file locks down: a write only counts as applied when the API
--  did not reject it *and* the value can be read back as the value we asked for.
--  The old implementation trusted pcall() alone, so a CVar write that returned
--  false (or nil) while raising no Lua error was reported to the user as
--  "applied". Every case below runs against an injected environment
--  (CVar.SetEnv), so no game client is needed.
------------------------------------------------------------------------------
local T, ns, Stub = ...
local CVar = ns.CVar

T.spec("spec_cvar")

--- Always start each case from the real (stub-backed) environment.
T.beforeEach(function()
    CVar.SetEnv(nil)
end)

--- Builds an injectable environment for CVar.
--  opts.initial     stored value (default "150")
--  opts.combat      inCombat() result
--  opts.readOnly    isReadOnly flag from getCVarInfo
--  opts.readable    when false, getCVarInfo/getCVar return nil (no read-back)
--  opts.returnFalse setCVar returns false (rejected, no Lua error)
--  opts.returnNil   setCVar returns nil (unknown, no Lua error)
--  opts.silentNoop  setCVar returns true but does not change the value
--  opts.throwSet    setCVar raises a Lua error
--  opts.throwInfo   getCVarInfo raises a Lua error
--  opts.noSetCVar   environment has no setCVar at all
--  opts.corruptReadback  setCVar "succeeds" but leaves a non-numeric value
local function makeEnv(opts)
    opts = opts or {}
    local env = {
        writes = {},
        store = { value = tostring(opts.initial or "150") },
        readable = opts.readable ~= false,
    }
    env.inCombat = function() return opts.combat and true or false end
    env.getCVarInfo = function()
        if opts.throwInfo then error("getCVarInfo exploded") end
        if not env.readable then return nil end
        return env.store.value, "400", false, false, false, false, opts.readOnly and true or false
    end
    env.getCVar = function()
        if not env.readable then return nil end
        return env.store.value
    end
    env.setCVar = function(name, value)
        env.writes[#env.writes + 1] = { name = name, value = value }
        if opts.throwSet then error("setCVar exploded") end
        if opts.returnFalse then return false end
        if opts.returnNil then return nil end
        if opts.silentNoop then return true end
        if opts.corruptReadback then
            env.store.value = "not-a-number"
            return true
        end
        env.store.value = tostring(value)
        return true
    end
    if opts.noSetCVar then env.setCVar = nil end
    return env
end

local function install(opts)
    local env = makeEnv(opts)
    CVar.SetEnv(env)
    return env
end

------------------------------------------------------------------------------
--  Constants and metadata
------------------------------------------------------------------------------

T.test("常量: 名称与客户端文档范围", function()
    T.eq(CVar.NAME, "SpellQueueWindow")
    T.eq(CVar.MIN, 0)
    T.eq(CVar.MAX, 400)
    T.eq(CVar.ERR_READONLY, "readonly")
    T.eq(CVar.ERR_COMBAT, "combat")
    T.eq(CVar.ERR_UNAVAILABLE, "unavailable")
    T.eq(CVar.ERR_REJECTED, "rejected")
    T.eq(CVar.ERR_VERIFY, "verify-failed")
    T.eq(CVar.ERR_NO_API, "no-api")
    T.eq(CVar.ERR_INVALID_VALUE, "invalid-value")
end)

T.test("Info() 永不返回 nil，且字段顺序与 C_CVar.GetCVarInfo 一致", function()
    local env = makeEnv()
    env.getCVarInfo = function()
        return "123", "400", true, false, true, true, true
    end
    CVar.SetEnv(env)

    local info = CVar:Info()
    T.eq(type(info), "table")
    T.truthy(info.known)
    T.eq(info.value, 123)
    T.eq(info.defaultValue, 400)
    T.eq(info.isStoredAccount, true)
    T.eq(info.isStoredCharacter, false)
    T.eq(info.isLocked, true)
    T.eq(info.isSecure, true)
    T.eq(info.isReadOnly, true)
end)

T.test("Info(): getCVarInfo 抛错时不崩溃，回退到 RawRead", function()
    install({ throwInfo = true, initial = "275" })
    local info = CVar:Info()
    T.eq(type(info), "table")
    T.truthy(info.known)
    T.eq(tonumber(info.value), 275, "回退路径也必须给出可用的数值")
    T.eq(info.isReadOnly, false)
    T.eq(CVar:RawRead(), "275")
    T.eq(tonumber(CVar:Read()), 275)
end)

-- 回归锁定（2026-09-28 已修复）：Info() 的 GetCVarInfo 回退分支曾经把
-- RawRead() 的字符串直接写进 info.value（主分支有 tonumber），于是
-- CVar:Read() 在回退路径返回 string，违反 ARCHITECTURE §4
-- 「Read() -> value(number)|nil」，并会让 ("%d"):format(current) 在 Lua 5.3 报错。
-- 最小复现（当时）：getCVarInfo 抛错、getCVar 返回 "275" 时
--                   type(CVar:Read()) == "string"。
T.test("Info()/Read() 的回退路径必须返回 number（文档契约）", function()
    install({ throwInfo = true, initial = "275" })
    T.eq(type(CVar:Info().value), "number")
    T.eq(CVar:Info().value, 275)
    T.eq(type(CVar:Read()), "number")
    T.eq(CVar:Read(), 275)
    T.eq(CVar:Read() + 25, 300, "必须能直接参与算术")
end)

T.test("客户端完全不可读时 Read() 返回 nil + unavailable（不得伪造 400 默认值）", function()
    install({ readable = false })
    local value, reason = CVar:Read()
    T.isNil(value, "不可读时不允许回退到 defaultValue")
    T.eq(reason, CVar.ERR_UNAVAILABLE)
    T.falsy(CVar:IsAvailable())
end)

T.test("空字符串按未知 CVar 处理", function()
    local env = install()
    env.store.value = ""
    local value, reason = CVar:Read()
    T.isNil(value)
    T.eq(reason, CVar.ERR_UNAVAILABLE)
    T.isNil(CVar:RawRead())
end)

T.test("RawRead 返回字符串", function()
    install({ initial = 150 })
    T.eq(CVar:RawRead(), "150")
    T.eq(CVar:Read(), 150)
end)

T.test("SameValue 按四舍五入比较，nil 永不相等", function()
    T.truthy(CVar.SameValue(200, 200.4))
    T.truthy(CVar.SameValue(200.4, 200))
    T.falsy(CVar.SameValue(200, 201))
    T.falsy(CVar.SameValue(199.4, 200))
    T.falsy(CVar.SameValue(nil, 200))
    T.falsy(CVar.SameValue(200, nil))
    T.falsy(CVar.SameValue(nil, nil))
    -- 非数字输入一律按「不相等」处理，绝不抛错：false 是安全方向（值不算我们的）
    T.falsy(CVar.SameValue("abc", 200), "非数字字符串不得抛错")
    T.falsy(CVar.SameValue(200, "abc"))
    T.falsy(CVar.SameValue("", 0))
    T.falsy(CVar.SameValue(0 / 0, 0 / 0), "NaN 按不相等处理")
    T.falsy(CVar.SameValue(math.huge, math.huge), "inf 按不相等处理")
    T.truthy(CVar.SameValue("200", 200), "数字字符串仍按数值比较")
end)

------------------------------------------------------------------------------
--  Writable checks
------------------------------------------------------------------------------

T.test("IsWritable: 正常 / 只读 / 战斗中 / 读不到", function()
    install()
    local writable, reason = CVar:IsWritable()
    T.truthy(writable)
    T.isNil(reason)

    install({ readOnly = true })
    writable, reason = CVar:IsWritable()
    T.falsy(writable)
    T.eq(reason, CVar.ERR_READONLY)

    install({ combat = true })
    writable, reason = CVar:IsWritable()
    T.falsy(writable)
    T.eq(reason, CVar.ERR_COMBAT)

    install({ readable = false })
    writable, reason = CVar:IsWritable()
    T.falsy(writable)
    T.eq(reason, CVar.ERR_UNAVAILABLE)
end)

------------------------------------------------------------------------------
--  Write: the P1 verification rules
------------------------------------------------------------------------------

T.test("P1: pcall 没抛错但 API 返回 false -> 必须判定失败 (rejected)", function()
    local env = install({ returnFalse = true })
    local ok, reason, applied = CVar:Write(200)
    T.falsy(ok, "API 返回 false 就是失败，旧代码在这里假报成功")
    T.eq(reason, CVar.ERR_REJECTED)
    T.isNil(applied)
    T.eq(#env.writes, 1, "应该确实调用了一次 API")
    T.eq(env.store.value, "150", "值没有被改动")
    T.eq(CVar:Read(), 150, "读回仍是旧值")
end)

T.test("P1: pcall 没抛错但 API 返回 nil 且值未变 -> 必须判定失败 (verify-failed)", function()
    local env = install({ returnNil = true })
    local ok, reason, applied = CVar:Write(200)
    T.falsy(ok, "nil 只代表未知，不等于成功")
    T.eq(reason, CVar.ERR_VERIFY)
    T.eq(applied, 150, "第三个返回值报告实际读到的值，供 UI 讲清楚为什么失败")
    T.eq(#env.writes, 1)
    T.eq(env.store.value, "150")
end)

T.test("P1: API 谎报 true 但读回不一致 -> 必须判定失败并回报读到的值", function()
    local env = install({ silentNoop = true })
    local ok, reason, applied = CVar:Write(200)
    T.falsy(ok, "读回 150 != 目标 200，不能算成功")
    T.eq(reason, CVar.ERR_VERIFY)
    T.eq(applied, 150, "第三个返回值应给出实际读回的值，供 UI 显示")
    T.eq(env.store.value, "150")
end)

T.test("P1: 客户端不可读回 + API 返回 nil -> 失败 (verify-failed)", function()
    install({ readable = false, returnNil = true })
    local ok, reason = CVar:Write(200)
    T.falsy(ok)
    T.eq(reason, CVar.ERR_VERIFY)
end)

T.test("客户端不可读回 + API 明确返回 true -> 接受（文档化行为）", function()
    install({ readable = false })
    local ok, reason, applied = CVar:Write(200)
    T.truthy(ok, "无法读回的客户端上，API 的 true 是唯一证据")
    T.isNil(reason)
    T.eq(applied, 200)
end)

T.test("读回值不是数字 -> 失败 (verify-failed)", function()
    local env = install({ corruptReadback = true })
    local ok, reason, applied = CVar:Write(200)
    T.falsy(ok)
    T.eq(reason, CVar.ERR_VERIFY)
    T.isNil(applied)
    T.eq(#env.writes, 1)
    T.eq(env.store.value, "not-a-number")
end)

T.test("只读 CVar: 直接拒绝且不调用 API", function()
    local env = install({ readOnly = true })
    local ok, reason = CVar:Write(200)
    T.falsy(ok)
    T.eq(reason, CVar.ERR_READONLY)
    T.eq(#env.writes, 0, "只读时连 API 都不该调用")
end)

T.test("战斗中: 直接拒绝且不调用 API", function()
    local env = install({ combat = true })
    local ok, reason = CVar:Write(200)
    T.falsy(ok)
    T.eq(reason, CVar.ERR_COMBAT)
    T.eq(#env.writes, 0, "战斗中绝不能触发写入")
end)

T.test("setCVar 内部抛错 -> no-api（不把异常当成成功）", function()
    local env = install({ throwSet = true })
    local ok, reason = CVar:Write(200)
    T.falsy(ok)
    T.eq(reason, CVar.ERR_NO_API)
    T.eq(#env.writes, 1)
    T.eq(env.store.value, "150")
end)

T.test("环境里没有 setCVar -> no-api", function()
    local env = install({ noSetCVar = true })
    local ok, reason = CVar:Write(200)
    T.falsy(ok)
    T.eq(reason, CVar.ERR_NO_API)
    T.eq(#env.writes, 0)
end)

T.test("非法值: nil/字符串/NaN/inf -> invalid-value，不触碰 API", function()
    local env = install()
    local bad = { nil, "abc", 0 / 0, 1 / 0, -1 / 0 }
    for index = 1, 5 do
        local ok, reason, applied = CVar:Write(bad[index])
        T.falsy(ok, "非法值 #" .. index .. " 不能成功")
        T.eq(reason, CVar.ERR_INVALID_VALUE, "非法值 #" .. index)
        T.isNil(applied)
    end
    T.eq(#env.writes, 0)
end)

T.test("正常写入成功: 返回 ok + applied，并写入了 %d 文本", function()
    local env = install()
    local ok, reason, applied = CVar:Write(200)
    T.truthy(ok)
    T.isNil(reason)
    T.eq(applied, 200)
    T.eq(env.store.value, "200")
    T.eq(#env.writes, 1)
    T.eq(env.writes[1].name, "SpellQueueWindow")
    T.eq(env.writes[1].value, "200", "写进去的必须是整数字符串")
    T.eq(CVar:Read(), 200)
end)

T.test("写入前取整并夹紧到 0..400", function()
    local env = install()
    local ok, _, applied = CVar:Write(199.6)
    T.truthy(ok)
    T.eq(applied, 200)
    T.eq(env.writes[#env.writes].value, "200")

    ok, _, applied = CVar:Write(-5)
    T.truthy(ok)
    T.eq(applied, 0)
    T.eq(env.writes[#env.writes].value, "0")

    ok, _, applied = CVar:Write(9999)
    T.truthy(ok)
    T.eq(applied, 400)
    T.eq(env.writes[#env.writes].value, "400")

    ok, _, applied = CVar:Write("150")
    T.truthy(ok)
    T.eq(applied, 150)
end)

T.test("写入失败不会改动环境，也不会留下“已应用”痕迹", function()
    local env = install({ returnFalse = true })
    for _ = 1, 3 do
        local ok = CVar:Write(300)
        T.falsy(ok)
    end
    T.eq(#env.writes, 3, "每次尝试都要真的调用 API（供上层重试）")
    T.eq(env.store.value, "150")
    T.eq(CVar:Read(), 150)
end)

T.test("Injected env 被替换后 GetEnv 返回新的环境，SetEnv(nil) 恢复真实环境", function()
    local env = install()
    T.eq(CVar.GetEnv(), env)
    CVar.SetEnv(nil)
    local real = CVar.GetEnv()
    T.notNil(real)
    T.ne(real, env, "SetEnv(nil) 之后必须重建真实环境")
    T.notNil(real.getCVar, "真实环境走 C_CVar / GetCVar")
end)
