------------------------------------------------------------------------------
--  tests/spec_locale.lua -- ns.L / ns.LOCALES
--
--  The locale contract (AutoSpellQueue_Locale.lua header):
--    * enUS, zhCN and zhTW carry the SAME, COMPLETE key set;
--    * any other client locale falls back to enUS;
--    * only if enUS is missing the key does ns.L return the key itself;
--    * the three tables come from one source of truth, so a missing or drifting
--      translation is impossible by construction.
--
--  This file locks that down, plus one thing the contract does not cover by
--  itself: every key the UI and the core actually ask for must exist, otherwise
--  players see raw "SETTING_MARGIN" text.
------------------------------------------------------------------------------
local T, ns, Stub = ...
local Core = ns.Core
local ROOT = _G.ASQ_TEST_ROOT or "."
local LOCALE_FILE = ROOT .. "/AutoSpellQueue_Locale.lua"

T.spec("spec_locale")

local function SortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    return keys
end

local function CompareKeySets(actual, expected, label)
    T.eq(#actual, #expected, label .. " 键数必须与 enUS 相同")
    local mismatch
    for index = 1, math.max(#actual, #expected) do
        if actual[index] ~= expected[index] then
            mismatch = tostring(actual[index]) .. " vs " .. tostring(expected[index])
            break
        end
    end
    T.isNil(mismatch, label .. " 键集必须与 enUS 完全一致，首个不一致: " .. tostring(mismatch))
end

--- Loads AutoSpellQueue_Locale.lua again with a given client locale, into a
--- fresh namespace, so locale selection can be tested without reloading the
--- whole state.
local function LoadLocale(clientLocale)
    local savedLocale = Stub.locale
    local fresh = {}
    local chunk, err = loadfile(LOCALE_FILE)
    if not chunk then
        Stub.locale = savedLocale
        T.truthy(false, "无法加载 " .. LOCALE_FILE .. ": " .. tostring(err))
        return fresh
    end
    Stub.locale = clientLocale -- the file picks its table from GetLocale() at load time
    local ok, runError = pcall(chunk, "AutoSpellQueue", fresh)
    Stub.locale = savedLocale
    if not ok then error(runError, 0) end
    return fresh
end

local locales = ns.LOCALES
local fallbackKeys = {}

T.test("ns.L 是函数，ns.LOCALES 三套表都存在", function()
    T.eq(type(ns.L), "function", "Locale 必须设置 ns.L")
    T.eq(type(locales), "table", "Locale 必须导出 ns.LOCALES")
    for _, name in ipairs({ "enUS", "zhCN", "zhTW" }) do
        T.eq(type(locales[name]), "table", "ns.LOCALES." .. name .. " 必须是表")
    end
    fallbackKeys = SortedKeys(locales.enUS)
    T.truthy(#fallbackKeys > 100, "enUS 应包含全部键（实得 " .. #fallbackKeys .. " 个）")
end)

T.test("enUS / zhCN / zhTW 键集完全相同（契约第一条）", function()
    local en = SortedKeys(locales.enUS)
    CompareKeySets(SortedKeys(locales.zhCN), en, "zhCN")
    CompareKeySets(SortedKeys(locales.zhTW), en, "zhTW")
end)

T.test("三套表的每个值都是非空字符串", function()
    local bad = {}
    for _, name in ipairs({ "enUS", "zhCN", "zhTW" }) do
        for key, value in pairs(locales[name]) do
            if type(value) ~= "string" or value == "" then
                bad[#bad + 1] = name .. ":" .. tostring(key)
            end
        end
    end
    T.eq(#bad, 0, "存在空值或非字符串: " .. table.concat(bad, ", "))
end)

T.test("ns.L 对每个 enUS 键都返回非空字符串；未知键回退键名", function()
    local missing = {}
    for _, key in ipairs(fallbackKeys) do
        local value = ns.L(key)
        if type(value) ~= "string" or value == "" then
            missing[#missing + 1] = key
        end
    end
    T.eq(#missing, 0, "这些键没有可用文本: " .. table.concat(missing, ", "))

    T.eq(ns.L("__NO_SUCH_KEY__"), "__NO_SUCH_KEY__", "未知键必须回退成键名")
    T.eq(ns.L(nil), nil, "非字符串参数原样返回")
    T.eq(ns.L(42), 42)
end)

T.test("未列出的客户端语言回退 enUS（契约第二条）", function()
    local deDE = LoadLocale("deDE")
    T.eq(type(deDE.L), "function")
    for _, key in ipairs({ "PANEL_TITLE", "SETTING_ENABLED", "STATE_ERROR", "MSG_RESET_DONE" }) do
        T.eq(deDE.L(key), locales.enUS[key], "deDE 应回退 enUS: " .. key)
    end
    T.eq(deDE.L("__NO_SUCH_KEY__"), "__NO_SUCH_KEY__")
end)

T.test("zhCN / zhTW 使用各自的表，缺键时才回退 enUS（契约第三、四条）", function()
    for _, name in ipairs({ "zhCN", "zhTW" }) do
        local loaded = LoadLocale(name)
        T.eq(loaded.LOCALE, name, "客户端语言为 " .. name .. " 时应选中该表")
        for _, key in ipairs({ "PANEL_TITLE", "SETTING_ENABLED", "SLASH_CMD_STATUS" }) do
            T.eq(loaded.L(key), locales[name][key], name .. " 应返回自己的文本: " .. key)
        end

        -- 人为挖掉一个键：必须回退 enUS，而不是泄漏键名
        local probe = "PANEL_TITLE"
        local saved = loaded.LOCALES[name][probe]
        loaded.LOCALES[name][probe] = nil
        T.eq(loaded.L(probe), locales.enUS[probe], name .. " 缺键时必须回退 enUS")
        T.eq(loaded.L("__NO_SUCH_KEY__"), "__NO_SUCH_KEY__")
        loaded.LOCALES[name][probe] = saved
    end
end)

T.test("UI/Core 源码里出现的每个本地化键都必须在 enUS 里", function()
    local sources = _G.ASQ_TEST_SOURCES
    T.notNil(sources, "run-tests.mjs 应提供 ASQ_TEST_SOURCES")

    local files = {
        "AutoSpellQueue.lua", "AutoSpellQueue_Options.lua",
        "AutoSpellQueue_Formula.lua", "AutoSpellQueue_CVar.lua",
    }

    -- 事件名与键名长得很像（CVAR_UPDATE 撞上 CVAR_ 前缀），必须排除。
    -- 下面的正则只看得到 `RegisterEvent("X")` 字面量形式；代码改成「事件名列表
    -- + pcall 注册」之后就扫不到了，所以这里把本插件注册的事件名补全。
    local notKeys = {
        ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_ENTERING_WORLD = true,
        PLAYER_SPECIALIZATION_CHANGED = true, ZONE_CHANGED_NEW_AREA = true,
        ZONE_CHANGED = true, PLAYER_REGEN_ENABLED = true, PLAYER_REGEN_DISABLED = true,
        CVAR_UPDATE = true, PLAYER_LOGOUT = true,
    }
    for _, file in ipairs(files) do
        local source = sources[file] or ""
        for event in source:gmatch('RegisterEvent%("([A-Z0-9_]+)"') do
            notKeys[event] = true
        end
    end

    -- 键名的前缀白名单：源码里带这些前缀的大写字符串一定是显示文本键。
    local prefixes = {
        "STATE_", "HINT_", "VALUE_", "CVAR_", "ROLE_", "CONTEXT_", "FORMULA_",
        "MSG_", "ERR_", "SLASH_", "UNIT_", "TAG_", "SETTING_", "SECTION_",
        "BUTTON_", "TOOLTIP_", "ADVANCED_", "BASE_MODE_", "LATENCY_", "FONT_",
        "PANEL_", "CHAT_", "LABEL_", "TAB_",
    }
    local function HasLocalePrefix(token)
        for _, prefix in ipairs(prefixes) do
            if string.sub(token, 1, #prefix) == prefix then return true end
        end
        return false
    end

    local checked, missing = 0, {}
    for _, file in ipairs(files) do
        local source = sources[file]
        T.notNil(source, "缺少源码文本: " .. file)
        for token in source:gmatch('"([A-Z][A-Z0-9_]*)"') do
            -- "STATE_" 这种前缀本身（拼键名用）和事件名不是键
            if HasLocalePrefix(token) and not notKeys[token]
                and string.sub(token, -1) ~= "_" then
                checked = checked + 1
                if locales.enUS[token] == nil then
                    missing[#missing + 1] = file .. ":" .. token
                end
            end
        end
    end
    T.truthy(checked >= 100, "应扫到足够多的键（实得 " .. checked .. " 个）")
    T.eq(#missing, 0, "这些键没有 enUS 文本: " .. table.concat(missing, ", "))
end)

T.test("动态拼接的键族也必须在 enUS 里", function()
    -- StateLabel 用 "STATE_" .. upper(state) 拼键名，REASON_KEY 的值是核心
    -- 传给 ReasonText 的键名，两者都不在字符串字面量里。
    local missing = {}
    for _, state in pairs(Core.STATE) do
        local key = "STATE_" .. string.upper(state)
        if locales.enUS[key] == nil then missing[#missing + 1] = key end
    end
    for _, key in pairs(Core.REASON_KEY) do
        if locales.enUS[key] == nil then missing[#missing + 1] = key end
    end
    T.eq(#missing, 0, "动态键缺少 enUS 文本: " .. table.concat(missing, ", "))

    -- 六种状态常量都要有标签
    for _, state in pairs(Core.STATE) do
        T.truthy(locales.enUS["STATE_" .. string.upper(state)] ~= nil, "缺少 STATE_" .. string.upper(state))
    end
end)

T.test("格式化键必须带 % 占位符（否则参数会被静默丢掉）", function()
    -- Core/Options 用 :format() 传参的键：占位符数量不足会让数字消失。
    local formatKeys = {
        CHAT_ERROR = 1, CHAT_BASE_CURRENT = 1, CHAT_BASE_SET = 1,
        HINT_DISABLED_OWNED = 1, HINT_ERROR = 1, HINT_UNAVAILABLE = 1,
        HINT_ERROR_AGE = 1, HINT_SAMPLED = 1, HINT_SNAPSHOT_AGE = 1,
        FORMULA_ADAPTIVE = 4, FORMULA_BASE = 2, FORMULA_CITY = 2,
        UNIT_MS = 1, UNIT_SECONDS = 1, DIAG_FLAGS = 4, MSG_UI_STEP_FAILED = 2,
    }
    local bad = {}
    for key, expected in pairs(formatKeys) do
        local value = locales.enUS[key]
        if type(value) ~= "string" then
            bad[#bad + 1] = key .. "(缺失)"
        else
            local _, count = value:gsub("%%%a", "")
            if count < expected then
                bad[#bad + 1] = key .. "(" .. count .. "<" .. expected .. ")"
            end
        end
    end
    T.eq(#bad, 0, "格式化键占位符不足: " .. table.concat(bad, ", "))
end)
