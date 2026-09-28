-------------------------------------------------------------------------------
--  AutoSpellQueue_Locale.lua
--
--  All user visible strings. Sets ns.L(key) -> string.
--
--  Contract (docs/ARCHITECTURE.md section 5):
--    * ns.L(key) always exists and never errors.
--    * enUS, zhCN and zhTW carry the SAME, COMPLETE key set.
--    * Any other client locale (deDE, frFR, ruRU, ...) falls back to enUS.
--    * Only if enUS is missing the key does ns.L return the key itself.
--
--  English is a real translation here, not a debug fallback: the addon ships to
--  CurseForge, where English is the primary language.
--
--  Every key is declared once with all three translations on the same line, so
--  a missing or drifting translation is impossible: the three locale tables are
--  built from this single table and therefore always have the same keys.
--
--  Only GetLocale() is used here: this file must stay API free.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local LOCALES = {
    enUS = {},
    zhCN = {},
    zhTW = {},
}

-- [key] = { zhCN, zhTW, enUS }
local STRINGS = {

    ---------------------------------------------------------------------------
    --  Chat output (used by the core; the formats must stay %d / %s safe)
    ---------------------------------------------------------------------------
    ["CHAT_ERROR"] = {
        "写入失败：%s",
        "寫入失敗：%s",
        "Write failed: %s",
    },
    ["CHAT_BASE_CURRENT"] = {
        "当前手动基础值：%d ms（/asq base auto 恢复自动）。",
        "目前手動基礎值：%d ms（/asq base auto 恢復自動）。",
        "Manual base value is %d ms (/asq base auto to go back).",
    },
    ["CHAT_BASE_AUTO"] = {
        "已恢复按职业 / 专精自动取值。",
        "已恢復依職業 / 專精自動取值。",
        "Back to the automatic per-spec base value.",
    },
    ["CHAT_BASE_SET"] = {
        "已把基础值固定为 %d ms（只影响基础值，延迟余量仍由插件自动计算）。",
        "已把基礎值固定為 %d ms（只影響基礎值，延遲餘量仍由插件自動計算）。",
        "Base value pinned to %d ms (headroom is still computed automatically).",
    },
    ["CHAT_BASE_INVALID"] = {
        "用法：/asq base 180（50–400），或 /asq base auto 恢复自动。",
        "用法：/asq base 180（50–400），或 /asq base auto 恢復自動。",
        "Usage: /asq base 180 (50-400), or /asq base auto to go back.",
    },

    ---------------------------------------------------------------------------
    --  CVar failure reasons (Core.REASON_KEY maps onto these)
    ---------------------------------------------------------------------------
    ["ERR_READONLY"] = {
        "客户端把 SpellQueueWindow 标为只读，无法写入。",
        "客戶端把 SpellQueueWindow 標為唯讀，無法寫入。",
        "The client reports SpellQueueWindow as read-only, so it cannot be written.",
    },
    ["ERR_COMBAT"] = {
        "战斗中不能修改，脱战后会自动重试。",
        "戰鬥中不能修改，脫戰後會自動重試。",
        "It cannot be changed in combat; the addon retries after combat.",
    },
    ["ERR_UNAVAILABLE"] = {
        "读不到 SpellQueueWindow 的当前值。",
        "讀不到 SpellQueueWindow 的目前數值。",
        "The current SpellQueueWindow value cannot be read.",
    },
    ["ERR_REJECTED"] = {
        "客户端拒绝了这次写入。",
        "客戶端拒絕了這次寫入。",
        "The client rejected this write.",
    },
    ["ERR_VERIFY_FAILED"] = {
        "写入后读回的值与目标不一致，已判定为失败。",
        "寫入後讀回的值與目標不一致，已判定為失敗。",
        "The value read back after writing does not match the target, so it counts as failed.",
    },
    ["ERR_NO_API"] = {
        "当前客户端没有可用的 CVar 写入接口。",
        "目前客戶端沒有可用的 CVar 寫入介面。",
        "This client has no usable CVar write API.",
    },
    ["ERR_INVALID_VALUE"] = {
        "目标值不是有效数字，已跳过。",
        "目標值不是有效數字，已略過。",
        "The target was not a valid number, so it was skipped.",
    },

    -- Reasons that are not in Core.REASON_KEY but can still reach the UI
    -- through Core.GetStatus().stateReasonKey / lastError.
    ["handler-error"] = {
        "插件内部事件处理出错。",
        "插件內部事件處理出錯。",
        "An internal event handler failed.",
    },
    ["external-change"] = {
        "其它来源改动了这个值。",
        "其他來源改動了這個值。",
        "Another source changed this value.",
    },
    ["unknown-key"] = {
        "未知的设置项。",
        "未知的設定項。",
        "Unknown setting.",
    },
    ["not-owned"] = {
        "当前没有接管这个值。",
        "目前沒有接管這個值。",
        "This value is not managed right now.",
    },

    ---------------------------------------------------------------------------
    --  Panel
    ---------------------------------------------------------------------------
    -- The panel name must match the addon name so players can find it in the
    -- addon list; the "never casts for you" disclaimer lives in the subtitle,
    -- because "auto spell queue" on its own reads like an autocast addon.
    ["PANEL_TITLE"] = {
        "AutoSpellQueue",
        "AutoSpellQueue",
        "AutoSpellQueue",
    },
    ["PANEL_SUBTITLE"] = {
        "按职业 / 专精、网络延迟与抖动自动维护 SpellQueueWindow（施法队列窗口）——不需要任何设置。它只改这一个客户端设置，不会替你施放技能。",
        "依職業 / 專精、網路延遲與抖動自動維護 SpellQueueWindow（施法佇列視窗）——不需要任何設定。它只改這一個用戶端設定，不會替你施放技能。",
        "Keeps SpellQueueWindow (the spell queue window) tuned to your class, spec, latency and jitter - there is nothing to configure. It only changes this one client setting and never casts for you.",
    },
    ["PANEL_FOOTER"] = {
        "余量与写入阈值由插件按实测抖动自动决定，所以这里没有可调项。诊断：/asq status　·　给某个专精手动指定基础值：/asq base 180（恢复自动：/asq base auto）。",
        "餘量與寫入門檻由插件依實測抖動自動決定，所以這裡沒有可調項。診斷：/asq status　·　給某個專精手動指定基礎值：/asq base 180（恢復自動：/asq base auto）。",
        "Headroom and the write threshold are derived from your measured jitter, so there is nothing to tune here. Diagnostics: /asq status  ·  override the base value for a spec: /asq base 180 (back to auto: /asq base auto).",
    },

    ---------------------------------------------------------------------------
    --  States (short labels for the badge and the status bar)
    ---------------------------------------------------------------------------
    ["STATE_IDLE"] = { "等待中", "等待中", "Idle" },
    ["STATE_DISABLED"] = { "已关闭", "已關閉", "Off" },
    ["STATE_APPLIED"] = { "已应用", "已套用", "Applied" },
    ["STATE_PENDING"] = { "等待脱战", "等待脫戰", "Waiting" },
    ["STATE_ERROR"] = { "写入失败", "寫入失敗", "Write failed" },
    ["STATE_UNAVAILABLE"] = { "不可用", "無法取得", "Unavailable" },

    ---------------------------------------------------------------------------
    --  State explanations (status card)
    ---------------------------------------------------------------------------
    ["HINT_IDLE"] = {
        "还没进入世界；进入后会自动接管这个设置。",
        "還沒進入世界；進入後會自動接管這個設定。",
        "Not in the world yet; the addon takes this setting over as soon as you are.",
    },
    ["HINT_DISABLED"] = {
        "插件已关闭，不会再修改这个值。",
        "插件已關閉，不會再修改這個值。",
        "The addon is off and will not change this value.",
    },
    ["HINT_DISABLED_OWNED"] = {
        "插件已关闭，但仍记着你原本的值（%d ms）；下次刷新会还回去。",
        "插件已關閉，但仍記著你原本的值（%d ms）；下次重新整理會還回去。",
        "The addon is off but still remembers your value (%d ms); it will be put back on the next refresh.",
    },
    ["HINT_APPLIED"] = {
        "正在按当前职业 / 专精与延迟维护这个值。",
        "正在依目前職業 / 專精與延遲維護這個值。",
        "Maintaining this value for your current class / spec and latency.",
    },
    ["HINT_PENDING"] = {
        "战斗中不写入。脱战后会重新读取实时状态再决定，不会套用过期的目标值。",
        "戰鬥中不寫入。脫戰後會重新讀取即時狀態再決定，不會套用過期的目標值。",
        "Nothing is written in combat. After combat the live state is read again and decided from scratch, so a stale target is never replayed.",
    },
    ["HINT_ERROR"] = {
        "上一次写入没有成功：%s。插件会在下次刷新时重试，不会假装已应用。",
        "上一次寫入沒有成功：%s。插件會在下次重新整理時重試，不會假裝已套用。",
        "The last write did not succeed: %s. It is retried on the next refresh instead of pretending it worked.",
    },
    ["HINT_UNAVAILABLE"] = {
        "读不到这个设置：%s。插件不会用默认值冒充它。",
        "讀不到這個設定：%s。插件不會用預設值冒充它。",
        "This setting cannot be read: %s. No default value is invented for it.",
    },
    ["HINT_EXTERNAL_CHANGE"] = {
        "检测到其它来源改动过这个值；插件不会覆盖它。",
        "偵測到其他來源改動過這個值；插件不會覆蓋它。",
        "Another source changed this value; the addon will not overwrite it.",
    },
    ["HINT_SCHEMA_FUTURE"] = {
        "检测到来自更新版本的设置数据，已原样保留，没有改写。",
        "偵測到來自更新版本的設定資料，已原樣保留，沒有改寫。",
        "Settings written by a newer version were found and are kept exactly as they are.",
    },
    ["HINT_SAMPLED"] = {
        "目标值 / 延迟 / 余量 / 场景 / 专精 = 上一次计算的采样（每 %d 秒刷新一次）；当前值是实时读取。余量按实测抖动自动决定，分数越高插件越保守。",
        "目標值 / 延遲 / 餘量 / 場景 / 專精 = 上一次計算的取樣（每 %d 秒重新整理一次）；目前值是即時讀取。餘量依實測抖動自動決定，分數越高插件越保守。",
        "Target / latency / headroom / context / spec are the sample of the last computation (every %d s); the current value is read live. Headroom is derived from measured jitter - the more jitter, the more conservative the addon gets.",
    },
    ["HINT_SNAPSHOT_AGE"] = {
        "上次计算在 %d 秒前。",
        "上次計算在 %d 秒前。",
        "Last computed %d s ago.",
    },
    ["HINT_NO_LATENCY"] = {
        "客户端还没报告延迟，暂按基础值。",
        "客戶端還沒回報延遲，暫按基礎值。",
        "The client has not reported latency yet, so the base value is used for now.",
    },
    ["HINT_IMPORTED"] = {
        "已从旧版 Tate_ASQ 导入设置。",
        "已從舊版 Tate_ASQ 匯入設定。",
        "Settings were imported from the old Tate_ASQ.",
    },
    ["HINT_ERROR_AGE"] = { "%d 秒前", "%d 秒前", "%d s ago" },
    ["TAG_SAMPLED"] = { "上次计算", "上次計算", "last computed" },

    ---------------------------------------------------------------------------
    --  Labels
    ---------------------------------------------------------------------------
    ["LABEL_CURRENT"] = { "当前值", "目前值", "Current" },
    ["LABEL_TARGET"] = { "目标值", "目標值", "Target" },
    ["LABEL_BASELINE"] = { "你原本的值", "你原本的值", "Your original value" },
    ["LABEL_LATENCY"] = { "延迟", "延遲", "Latency" },
    ["LABEL_SPEC"] = { "专精", "專精", "Spec" },
    ["LABEL_BASE"] = { "基础值", "基礎值", "Base" },
    ["LABEL_ROLE"] = { "定位", "定位", "Role" },
    ["LABEL_ENABLED"] = { "总开关", "總開關", "Enabled" },
    ["LABEL_FORMULA"] = { "计算式", "計算式", "Formula" },
    ["LABEL_STATUS"] = { "状态", "狀態", "Status" },
    ["LABEL_LAST_ERROR"] = { "最近错误", "最近錯誤", "Last error" },
    ["LABEL_HOME"] = { "本地", "本地", "Home" },
    ["LABEL_WORLD"] = { "世界", "世界", "World" },
    ["LABEL_OWNED"] = { "接管中", "接管中", "Managed" },
    ["LABEL_LAST_APPLIED"] = { "最近写入", "最近寫入", "Last write" },
    ["LABEL_APPLY_COUNT"] = { "写入次数", "寫入次數", "Writes" },
    ["LABEL_REPAIRS"] = { "修复次数", "修復次數", "Repairs" },
    ["LABEL_REFRESH"] = { "刷新间隔", "重新整理間隔", "Refresh interval" },
    ["LABEL_CVAR"] = { "CVar 状态", "CVar 狀態", "CVar status" },
    ["LABEL_CONTEXT"] = { "场景", "場景", "Context" },
    ["LABEL_MARGIN"] = { "自适应余量", "自適應餘量", "Adaptive headroom" },
    ["LABEL_JITTER"] = { "延迟抖动", "延遲抖動", "Latency jitter" },

    ---------------------------------------------------------------------------
    --  Gameplay context / role
    ---------------------------------------------------------------------------
    ["CONTEXT_CITY"] = { "城市", "城市", "City" },
    ["CONTEXT_INSTANCE"] = { "副本 / 战场", "副本 / 戰場", "Instance / battleground" },
    ["CONTEXT_WORLD"] = { "野外", "野外", "Open world" },
    ["ROLE_MELEE"] = { "近战", "近戰", "Melee" },
    ["ROLE_RANGED"] = { "远程", "遠程", "Ranged" },
    ["ROLE_UNKNOWN"] = { "未知", "未知", "Unknown" },

    ---------------------------------------------------------------------------
    --  Settings
    ---------------------------------------------------------------------------
    ["SETTING_ENABLED"] = { "启用自动调整", "啟用自動調整", "Enable auto tuning" },
    ["SETTING_ENABLED_HINT"] = {
        "关闭后会把 SpellQueueWindow 还原成你原本的值。",
        "關閉後會把 SpellQueueWindow 還原成你原本的值。",
        "Turning this off puts the SpellQueueWindow you had before back.",
    },
    ["SETTING_SHOW_STATUS"] = { "显示悬浮状态条", "顯示浮動狀態列", "Show floating status bar" },

    ---------------------------------------------------------------------------
    --  Sections / buttons
    ---------------------------------------------------------------------------
    ["BUTTON_RESET_POSITION"] = { "重置位置", "重設位置", "Reset position" },
    ["BUTTON_CLOSE"] = { "X", "X", "X" },

    ---------------------------------------------------------------------------
    --  Tooltips
    ---------------------------------------------------------------------------
    ["TOOLTIP_STATUS_BAR"] = {
        "左键打开设置；按住拖动可移动，位置会被记住。",
        "左鍵開啟設定；按住拖曳可移動，位置會被記住。",
        "Left click: settings — drag to move; the position is remembered.",
    },
    ["TOOLTIP_RESET_POSITION"] = {
        "把状态条放回屏幕上方居中，并重新显示。",
        "把狀態列放回畫面上方置中，並重新顯示。",
        "Puts the status bar back at the top of the screen and shows it again.",
    },

    ---------------------------------------------------------------------------
    --  Messages
    ---------------------------------------------------------------------------
    ["MSG_RESET_DONE"] = {
        "所有设置已恢复默认。",
        "所有設定已回復預設。",
        "All settings are back to their defaults.",
    },
    ["MSG_POSITION_RESET"] = { "状态条位置已复位。", "狀態列位置已重設。", "Status bar position reset." },
    ["MSG_STATUS_BAR_SHOWN"] = {
        "悬浮状态条已重新显示。",
        "浮動狀態列已重新顯示。",
        "The floating status bar is visible again.",
    },
    ["MSG_OPEN_FAILED"] = {
        "打不开设置面板；可以先用 /asq status 查看诊断。",
        "打不開設定面板；可以先用 /asq status 查看診斷。",
        "The settings panel could not be opened; try /asq status for diagnostics.",
    },
    ["MSG_UI_STEP_FAILED"] = {
        "界面组件「%s」初始化失败：%s。其余功能仍可用，请把这条报给作者。",
        "介面元件「%s」初始化失敗：%s。其餘功能仍可用，請把這條回報給作者。",
        "UI part \"%s\" failed to initialise: %s. Everything else still works - please report this line.",
    },

    ---------------------------------------------------------------------------
    --  Values / units
    ---------------------------------------------------------------------------
    ["VALUE_UNAVAILABLE"] = { "不可用", "無法取得", "Unavailable" },
    ["VALUE_ON"] = { "开", "開", "On" },
    ["VALUE_OFF"] = { "关", "關", "Off" },
    ["VALUE_YES"] = { "是", "是", "Yes" },
    ["VALUE_NO"] = { "否", "否", "No" },
    ["VALUE_NONE"] = { "无", "無", "None" },
    ["VALUE_PLACEHOLDER"] = { "--", "--", "--" },
    ["UNIT_MS"] = { "%d ms", "%d ms", "%d ms" },
    ["UNIT_SECONDS"] = { "%d 秒", "%d 秒", "%d s" },

    ---------------------------------------------------------------------------
    --  Formula descriptions (must keep their %d placeholders)
    ---------------------------------------------------------------------------
    ["FORMULA_ADAPTIVE"] = {
        "%d ms = max(基础 %d, 延迟 %d + 余量 %d)",
        "%d ms = max(基礎 %d, 延遲 %d + 餘量 %d)",
        "%d ms = max(base %d, latency %d + margin %d)",
    },
    ["FORMULA_BASE"] = {
        "%d ms = 基础 %d（该专精被手动指定了基础值）",
        "%d ms = 基礎 %d（該專精被手動指定了基礎值）",
        "%d ms = base %d (base value overridden for this spec)",
    },
    ["FORMULA_CITY"] = {
        "%d ms = 基础 %d（城市中不按延迟调整）",
        "%d ms = 基礎 %d（城市中不依延遲調整）",
        "%d ms = base %d (city: no latency adaptation)",
    },
    ["FORMULA_UNKNOWN"] = { "—", "—", "-" },

    ---------------------------------------------------------------------------
    --  CVar diagnostics
    ---------------------------------------------------------------------------
    ["CVAR_MISSING"] = {
        "客户端不认识这个 CVar",
        "客戶端不認得這個 CVar",
        "The client does not know this CVar",
    },
    ["CVAR_NORMAL"] = { "正常", "正常", "Normal" },
    ["CVAR_READONLY"] = { "只读", "唯讀", "Read-only" },
    ["CVAR_LOCKED"] = { "已锁定", "已鎖定", "Locked" },
    ["CVAR_SECURE"] = { "受保护", "受保護", "Protected" },
    ["CVAR_ACCOUNT"] = { "账号级", "帳號層級", "Account-wide" },
    ["CVAR_CHARACTER"] = { "角色级", "角色層級", "Per character" },
    ["DIAG_FLAGS"] = {
        "inWorld=%s inCombat=%s externalChange=%s schemaFuture=%s",
        "inWorld=%s inCombat=%s externalChange=%s schemaFuture=%s",
        "inWorld=%s inCombat=%s externalChange=%s schemaFuture=%s",
    },

    ---------------------------------------------------------------------------
    --  Slash commands (unlock also mentions that it shows the bar again)
    ---------------------------------------------------------------------------
    ["SLASH_HELP"] = {
        "输入 /asq 打开设置；/asq status 查看诊断；/asq reset 恢复默认；/asq unlock 复位状态条位置（并重新显示状态条）；/asq base 180 手动指定基础值（/asq base auto 恢复自动）。",
        "輸入 /asq 開啟設定；/asq status 查看診斷；/asq reset 回復預設；/asq unlock 重設狀態列位置（並重新顯示狀態列）；/asq base 180 手動指定基礎值（/asq base auto 恢復自動）。",
        "Type /asq for settings, /asq status for diagnostics, /asq reset to restore the defaults, /asq unlock to reset the status bar position (which shows the bar again), /asq base 180 to override the base value (/asq base auto to go back).",
    },
    ["SLASH_HELP_TITLE"] = { "可用命令：", "可用指令：", "Commands:" },
    ["SLASH_CMD_OPEN"] = {
        "/asq — 打开设置面板",
        "/asq — 開啟設定面板",
        "/asq — open the settings panel",
    },
    ["SLASH_CMD_STATUS"] = {
        "/asq status — 打印诊断信息",
        "/asq status — 列印診斷資訊",
        "/asq status — print diagnostics",
    },
    ["SLASH_CMD_RESET"] = {
        "/asq reset — 恢复全部默认设置",
        "/asq reset — 回復全部預設設定",
        "/asq reset — restore all default settings",
    },
    ["SLASH_CMD_UNLOCK"] = {
        "/asq unlock — 复位状态条位置并重新显示它",
        "/asq unlock — 重設狀態列位置並重新顯示它",
        "/asq unlock — reset the status bar position and show the bar again",
    },
}

-------------------------------------------------------------------------------
--  Build the per-locale tables from the single source above.
--  All three tables end up with exactly the same keys.
-------------------------------------------------------------------------------
for key, entry in pairs(STRINGS) do
    LOCALES.zhCN[key] = entry[1]
    LOCALES.zhTW[key] = entry[2]
    LOCALES.enUS[key] = entry[3]
end

-------------------------------------------------------------------------------
--  Select the locale: zhCN / zhTW when the client asks for them, enUS for
--  everything else. A key missing from the selected table falls back to enUS,
--  and only then to the key itself.
-------------------------------------------------------------------------------
local locale = "enUS"
if type(GetLocale) == "function" then
    local ok, value = pcall(GetLocale)
    if ok and type(value) == "string" and value ~= "" then
        locale = value
    end
end

local active = LOCALES[locale] or LOCALES.enUS

ns.L = function(key)
    if type(key) ~= "string" then return key end
    local value = active[key]
    if value ~= nil then return value end
    value = LOCALES.enUS[key]
    if value ~= nil then return value end
    return key
end

ns.LOCALE = locale
ns.LOCALES = LOCALES
