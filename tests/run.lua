------------------------------------------------------------------------------
--  tests/run.lua
--
--  Assertion helpers + test runner. Executed by tools/run-tests.mjs from inside
--  a fengari (Lua 5.3) state, after tests/wow_stub.lua and the three core
--  addon files have been loaded with the shared namespace table.
--
--  Globals provided by the runner (tools/run-tests.mjs):
--    ASQ_TEST_ROOT   repository root, forward slashes
--    ASQ_TEST_NS     the addon namespace table (ns.Formula / ns.CVar / ns.Core)
--    ASQ_TEST_SPECS  array of spec files to load, relative to the root
--    ASQ_TEST_FILTER optional substring filter on spec names
--
--  Exit code is reported through the global ASQ_TEST_EXIT_CODE (0 = green,
--  1 = at least one failed assertion). Hard failures fail the gate; cases
--  registered with T.xfail() are known, already-reported issues and are listed
--  separately so the gate still reflects *new* regressions.
------------------------------------------------------------------------------

local Stub = _G.AutoSpellQueueStub
if type(Stub) ~= "table" then
    error("tests/run.lua: tests/wow_stub.lua was not loaded first")
end
local printLine = Stub.realPrint or print

local ns = _G.ASQ_TEST_NS
if type(ns) ~= "table" then
    error("tests/run.lua: ASQ_TEST_NS missing - run this through tools/run-tests.mjs")
end

local T = {
    ns = ns,
    stub = Stub,
    specs = {},
    passed = 0,
    failed = 0,
    knownIssues = 0,
    xpass = 0,
    assertions = 0,
    failures = {},
    known = {},
}
_G.ASQ_TEST = T

------------------------------------------------------------------------------
--  Value formatting
------------------------------------------------------------------------------

local function fmt(value)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" then
        if value ~= value then return "NaN" end
        if value == math.huge then return "inf" end
        if value == -math.huge then return "-inf" end
        if value == math.floor(value) then return string.format("%d", value) end
        return string.format("%.6f", value)
    end
    if kind == "table" then
        local parts = {}
        for key, item in pairs(value) do
            parts[#parts + 1] = tostring(key) .. "=" .. fmt(item)
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(value)
end
T.fmt = fmt

local function fail(message)
    error(message, 3)
end

local function context(message)
    if message == nil then return "" end
    return " :: " .. tostring(message)
end

------------------------------------------------------------------------------
--  Assertions
------------------------------------------------------------------------------

function T.ok(condition, message)
    T.assertions = T.assertions + 1
    if not condition then
        fail("ok() 失败，条件为假" .. context(message))
    end
    return condition
end

function T.truthy(value, message)
    T.assertions = T.assertions + 1
    if not value then
        fail("truthy() 失败，实得 " .. fmt(value) .. context(message))
    end
    return value
end

function T.falsy(value, message)
    T.assertions = T.assertions + 1
    if value then
        fail("falsy() 失败，实得 " .. fmt(value) .. context(message))
    end
    return value
end

function T.eq(actual, expected, message)
    T.assertions = T.assertions + 1
    local same = (actual == expected)
    if not same and type(actual) == "number" and type(expected) == "number" then
        -- NaN == NaN is false but "both are NaN" is what the test means.
        same = (actual ~= actual) and (expected ~= expected)
    end
    if not same then
        fail("eq() 失败，期望 " .. fmt(expected) .. "，实得 " .. fmt(actual) .. context(message))
    end
    return actual
end

function T.ne(actual, unexpected, message)
    T.assertions = T.assertions + 1
    if actual == unexpected then
        fail("ne() 失败，两者都是 " .. fmt(actual) .. context(message))
    end
    return actual
end

function T.near(actual, expected, epsilon, message)
    T.assertions = T.assertions + 1
    epsilon = epsilon or 0.0001
    local a, e = tonumber(actual), tonumber(expected)
    if a == nil or e == nil or a ~= a or e ~= e or math.abs(a - e) > epsilon then
        fail("near() 失败，期望 " .. fmt(expected) .. "±" .. fmt(epsilon) ..
            "，实得 " .. fmt(actual) .. context(message))
    end
    return actual
end

function T.isNil(value, message)
    T.assertions = T.assertions + 1
    if value ~= nil then
        fail("isNil() 失败，实得 " .. fmt(value) .. context(message))
    end
end

function T.notNil(value, message)
    T.assertions = T.assertions + 1
    if value == nil then
        fail("notNil() 失败，实得 nil" .. context(message))
    end
    return value
end

function T.contains(haystack, needle, message)
    T.assertions = T.assertions + 1
    if type(haystack) ~= "string" or string.find(haystack, needle, 1, true) == nil then
        fail("contains() 失败，未在 " .. fmt(haystack) .. " 中找到 " .. fmt(needle) .. context(message))
    end
end

--- Raised expectation: fn() must throw. Returns the error message.
function T.raises(fn, message)
    T.assertions = T.assertions + 1
    local okRun, err = pcall(fn)
    if okRun then
        fail("raises() 失败，期望抛错但正常返回" .. context(message))
    end
    return tostring(err)
end

--- Compares two plain-valued tables field by field (one level deep).
function T.deepeq(actual, expected, message)
    T.assertions = T.assertions + 1
    if type(actual) ~= "table" or type(expected) ~= "table" then
        fail("deepeq() 失败，需要两个表，实得 " .. type(actual) .. "/" .. type(expected) .. context(message))
    end
    for key, value in pairs(expected) do
        if actual[key] ~= value then
            fail("deepeq() 失败，字段 " .. tostring(key) .. " 期望 " .. fmt(value) ..
                "，实得 " .. fmt(actual[key]) .. context(message))
        end
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            fail("deepeq() 失败，多出字段 " .. tostring(key) .. "=" .. fmt(actual[key]) .. context(message))
        end
    end
end

--- Passes when `fn` returns a value inside [lo, hi] and finite.
function T.inRange(value, lo, hi, message)
    T.assertions = T.assertions + 1
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge
        or value < lo or value > hi then
        fail("inRange() 失败，期望数字落在 [" .. fmt(lo) .. ", " .. fmt(hi) .. "]，实得 " ..
            fmt(value) .. context(message))
    end
    return value
end

------------------------------------------------------------------------------
--  Registration
------------------------------------------------------------------------------

local currentSpec
local beforeEachFn

function T.spec(name)
    currentSpec = { name = name, tests = {} }
    T.specs[#T.specs + 1] = currentSpec
    beforeEachFn = nil
    return currentSpec
end

function T.beforeEach(fn)
    beforeEachFn = fn
end

local function register(kind, name, fn, note)
    if not currentSpec then
        error("T." .. kind .. "('" .. tostring(name) .. "') 必须在 T.spec() 之后调用")
    end
    currentSpec.tests[#currentSpec.tests + 1] = {
        kind = kind,
        name = name,
        fn = fn,
        note = note,
        before = beforeEachFn,
        spec = currentSpec.name,
    }
end

function T.test(name, fn) register("test", name, fn) end

--- A case that documents a real, already-reported defect. It must currently
--- fail; if it starts passing it is reported as XPASS (remove the marker).
function T.xfail(name, fn, note) register("xfail", name, fn, note) end

------------------------------------------------------------------------------
--  Execution
------------------------------------------------------------------------------

local function firstLines(text, count)
    local lines = {}
    for line in tostring(text):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
        if #lines >= count then break end
    end
    return lines
end

local function invoke(case)
    if case.before then case.before() end
    case.fn()
end

local function runCase(case)
    local okRun, err = xpcall(function() invoke(case) end, function(message)
        return tostring(message) .. "\n" .. tostring(debug.traceback("", 2))
    end)

    if case.kind == "xfail" then
        if okRun then
            T.xpass = T.xpass + 1
            printLine("  XPASS " .. case.name .. "   (已知问题看起来已修复，请移除 T.xfail)")
            T.known[#T.known + 1] = { spec = case.spec, name = case.name, state = "xpass", note = case.note }
        else
            T.knownIssues = T.knownIssues + 1
            printLine("  KNOWN " .. case.name .. "   (已知问题，不计入失败)")
            if case.note then printLine("        note: " .. case.note) end
            for _, line in ipairs(firstLines(err, 2)) do printLine("        " .. line) end
            T.known[#T.known + 1] = { spec = case.spec, name = case.name, state = "known", message = tostring(err) }
        end
        return
    end

    if okRun then
        T.passed = T.passed + 1
        printLine("  ok    " .. case.name)
        return
    end

    T.failed = T.failed + 1
    printLine("  FAIL  " .. case.name)
    local shown = firstLines(err, 6)
    for _, line in ipairs(shown) do printLine("        " .. line) end
    T.failures[#T.failures + 1] = {
        spec = case.spec,
        name = case.name,
        message = table.concat(shown, "\n"),
    }
end

local function loadSpec(path)
    local chunk, err = loadfile(path)
    if not chunk then
        error("无法加载测试文件 " .. path .. ": " .. tostring(err))
    end
    chunk(T, ns, Stub)
end

function T.run()
    local root = _G.ASQ_TEST_ROOT or "."
    local specFiles = _G.ASQ_TEST_SPECS
    if type(specFiles) ~= "table" or #specFiles == 0 then
        error("ASQ_TEST_SPECS 为空：run-tests.mjs 没有找到任何 tests/spec_*.lua")
    end

    for _, file in ipairs(specFiles) do
        loadSpec(root .. "/" .. file)
    end

    local filter = _G.ASQ_TEST_FILTER
    local totalCases, caseCount = 0, 0
    for _, spec in ipairs(T.specs) do
        if not filter or string.find(spec.name, filter, 1, true) then
            caseCount = caseCount + 1
            totalCases = totalCases + #spec.tests
        end
    end

    printLine("================================================================")
    printLine(" AutoSpellQueue 测试 (fengari " .. tostring(_VERSION) .. " / " .. tostring(jit and jit.version or "PUC") .. ")")
    printLine(" 根目录: " .. root)
    printLine((" 用例: %d 个 spec 文件, %d 个用例"):format(caseCount, totalCases))
    if filter then printLine(" 过滤: " .. filter) end
    printLine("================================================================")

    for _, spec in ipairs(T.specs) do
        if not filter or string.find(spec.name, filter, 1, true) then
            printLine("")
            printLine("-- " .. spec.name .. " " .. string.rep("-", math.max(3, 58 - #spec.name)))
            for _, case in ipairs(spec.tests) do
                runCase(case)
            end
        end
    end

    printLine("")
    printLine("================================================================")
    printLine((" 断言 %d 条；通过 %d，失败 %d，已知问题 %d，意外通过 %d")
        :format(T.assertions, T.passed, T.failed, T.knownIssues, T.xpass))

    if T.failed > 0 then
        printLine("")
        printLine(" 失败用例：")
        for index, failure in ipairs(T.failures) do
            local first = firstLines(failure.message, 1)[1] or ""
            printLine(("  %d) [%s] %s"):format(index, failure.spec, failure.name))
            printLine("     " .. first)
        end
    end

    if T.knownIssues > 0 then
        printLine("")
        printLine(" 已知问题（已上报 lead，不阻塞门禁）：")
        for _, item in ipairs(T.known) do
            if item.state == "known" then
                printLine("  - [" .. item.spec .. "] " .. item.name)
            end
        end
    end

    printLine("================================================================")
    if T.failed == 0 then
        printLine(" 结果: PASS")
    else
        printLine(" 结果: FAIL (" .. T.failed .. " 个用例失败)")
    end

    _G.ASQ_TEST_EXIT_CODE = (T.failed > 0) and 1 or 0
    return T.failed == 0
end

T.run()
