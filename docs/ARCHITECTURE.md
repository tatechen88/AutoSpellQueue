# AutoSpellQueue — 架构与模块契约

> 本文件是并行开发时的接口冻结文档（frozen contract）。改接口必须先改这里。
> 最后更新：2026-09-28

## 1. 项目是什么

魔兽世界正式服（12.x）插件。它只做一件事：把 `SpellQueueWindow`（施法队列窗口 / 延迟容限）
自动保持在适合当前职业专精与网络延迟的值，并在插件不工作时把玩家原本的值放回去。

**它不是**：自动施法、按键循环、宏助手、战斗自动化。任何会替玩家做战斗决策的功能都不属于本项目。

## 2. 文件与加载顺序

`.toc` 中的顺序即加载顺序，模块通过 `.toc` 传入的私有命名空间表 `ns` 互相访问，
不使用 `_G` 全局（唯一例外：`_G.AutoSpellQueue` 指向核心，方便 `/dump` 排查）。

| 顺序 | 文件 | 职责 | 允许调用 WoW API |
|---|---|---|---|
| 1 | `AutoSpellQueue_Locale.lua` | 全部显示字符串；设置 `ns.L(key) -> string` | 仅 `GetLocale()` |
| 2 | `AutoSpellQueue_Formula.lua` | 纯计算：职业专精、延迟、场景 → 目标值 | **禁止** |
| 3 | `AutoSpellQueue_CVar.lua` | 唯一读写 `SpellQueueWindow` 的地方；包一层可注入环境 | 通过 `env` 表 |
| 4 | `AutoSpellQueue.lua` | 配置校验/迁移、所有权状态机、事件、定时刷新 | 是 |
| 5 | `AutoSpellQueue_Options.lua` | 设置面板、状态条、斜杠命令 | 是 |

运行期文件只有上面 5 个 `.lua` + 1 个 `.toc`。`tests/`、`tools/`、`docs/` 不进发布包。

## 3. 状态机（核心不变量）

这是整个插件的正确性核心，任何改动都必须保持以下不变量：

1. **写入必须被验证。** `CVar:Write()` 只有在「API 未拒绝」且「读回值与目标一致」时才返回成功。
   失败的写入不得更新 `ownership.lastApplied`，也不得把状态显示成已应用。
2. **所有权显式记录。** 只要插件改过这个 CVar，`db.ownership` 就存在，记录
   `baseline`（接管前的玩家值）与 `lastApplied`（插件最后写入的值）。
3. **只在仍然是我们的值时才恢复。** 若 `current ~= lastApplied`（玩家或其他插件改过），
   只放弃所有权，**不写回** baseline，避免覆盖别人的修改。
4. **战斗中不写。** 战斗中只把状态标为 `pending`，**不缓存待重放目标**；
   `PLAYER_REGEN_ENABLED` 会重新读取实时状态再决策，避免应用过期快照。
5. **登出前归还。** `PLAYER_LOGOUT` 尝试恢复 baseline；若失败，持久化的 ownership
   记录让下次登录还能恢复。
6. **未来 schema 不降级。** `schemaVersion` 高于当前版本时，原样保留并标记
   `schemaFuture`，不强行改写用户数据。

### 决策函数

`Core.Decide(cfg, snap)` 是**纯函数**（无副作用、不调用游戏 API），返回：

| kind | 含义 |
|---|---|
| `none` | 无需动作（已达目标 / 未启用 / 差值在迟滞内） |
| `apply` | 写入 `action.target` |
| `restore` | 写回 `action.value`（baseline） |
| `wait` | 战斗中，仅标记 `pending` |
| `release` | 放弃所有权，不写入 |
| `unavailable` | 读不到 CVar，报错 |

### 状态值

`Core.STATE` = `idle` | `disabled` | `applied` | `pending` | `error` | `unavailable`

## 4. 对外接口（Options / 测试可以依赖）

### `ns.Formula`（纯函数）

```lua
Formula.CITY_MAP_FLAG                     -- 0x100000 (Enum.UIMapFlag.IsCityMap)
Formula.HasFlag(value, flag)              -- boolean，不依赖 bit 库
Formula.Clamp(v, lo, hi)
Formula.Round(v)
Formula.SafeNumber(v)                     -- tonumber + NaN/inf 归零
Formula.Classify(specID, classFile)       -- "melee" | "ranged"
Formula.IsKnownSpec(specID)               -- boolean
Formula.GetBase(cfg, specID, classFile)   -- number(ms)
Formula.ClassifyContext(isInInstance, mapFlags) -- "instance" | "city" | "world"
Formula.PickLatency(source, home, world)  -- number
Formula.ComputeTarget(cfg, specID, classFile, home, world, context)
                                          -- -> target, role, base, latency
Formula.Describe(cfg, specID, classFile, home, world, context)
                                          -- -> kind, base, latency, margin
```

### `ns.CVar`

```lua
CVar.NAME                                 -- "SpellQueueWindow"
CVar.MIN, CVar.MAX                        -- 0, 400
CVar.ERR_READONLY / ERR_COMBAT / ERR_UNAVAILABLE / ERR_REJECTED
CVar.ERR_VERIFY / ERR_NO_API / ERR_INVALID_VALUE
CVar:Info()      -- { known, value, defaultValue, isReadOnly, isSecure, isLocked,
                 --   isStoredAccount, isStoredCharacter }  (永不返回 nil)
CVar:Read()      -- value(number) | nil, reason(string)
CVar:IsAvailable()
CVar:IsWritable()-- boolean, reason
CVar:Write(v)    -- ok(boolean), reason(string|nil), applied(number|nil)
                 --   成功时 applied = 写入并被读回确认的值
                 --   因读回不一致而失败（ERR_VERIFY）时，applied = **读回的实际值**，
                 --   便于诊断"API 说成功但值没变"的情况
CVar.SameValue(a, b)
CVar.GetEnv() / CVar.SetEnv(env)          -- 测试注入点
```

`env` 需要提供：`getCVarInfo(name)`、`getCVar(name)`、`setCVar(name, str)`、`inCombat()`。

### `ns.Core`

```lua
Core.STATE.*                    -- 状态常量
Core.DEFAULTS                   -- 默认配置表（键名即白名单）
Core.REASON_KEY                 -- CVar 失败原因 -> Locale 键
Core.L(key)                     -- 本地化（无 Locale 文件时返回 key 本身）
Core.Output(text)               -- 聊天输出（带插件名前缀）
Core.Now()
Core.GetConfig()                -- 校验后的配置表（可直接读，改要用 SetConfig）
Core.SetConfig(key, value, opts)-- opts = { noRefresh = true }
Core.SetEnabled(bool)
Core.IsEnabled()
Core.ResetSettings()
Core.Refresh(reason)            -- 重新读状态并执行决策
Core.RestoreOwnership(reason)   -- 归还玩家原值；返回 ok, reason
Core.GetStatus()                -- 见下
Core.Snapshot()                 -- 最近一次读取的游戏状态
Core.Decide(cfg, snap)          -- 纯决策函数
Core.Init()                     -- 创建事件帧（文件加载时已自动调用）
```

`Core.GetStatus()` 返回：

```lua
{
  enabled, state, stateReason, stateReasonKey,
  current,           -- 上一次快照里读到的值
  live,              -- 刚刚从客户端读到的值（永不缓存；状态卡用它显示"当前"）
  target,            -- 上一次计算出的目标值
  snapshotAt,        -- 上一次计算的时间戳（time()），用于说明"这是采样值"
  baseline, lastApplied, owned,
  inCombat, inWorld,
  context, role, base, latency, home, world,
  specID, specName, classFile, cvarInfo,
  lastError, lastErrorAt, applyCount, repairs,
  externalChange,    -- 检测到别人改过 CVar（诊断用；插件不会覆盖它）
  schemaFuture, importedFrom,
  refreshSeconds, reason,
}
```

## 5. Locale 契约

`AutoSpellQueue_Locale.lua` 必须设置 `ns.L = function(key) ... end`，并提供
**enUS（英文，必备，面向 CurseForge 的国际用户）**、`zhCN`、`zhTW` 三套字符串。
三套表的键集必须完全一致；未列出的语言回退到 enUS；enUS 也缺失时才回退 key 本身。

> 历史教训：v2.0.0 曾把英文定义为「回退 key 本身」，结果英文客户端会把
> `STATE_APPLIED` 这种内部键直接显示给玩家。英文必须和其它语言一样是真实文案。

**核心直接使用的键（必须存在）：**

```
CHAT_CHANGED        -- 参数：target, previous     例如 "SpellQueueWindow: %d → %d ms"
CHAT_RESTORED       -- 参数：value
CHAT_ERROR          -- 参数：reason 文本
ERR_READONLY, ERR_COMBAT, ERR_UNAVAILABLE, ERR_REJECTED,
ERR_VERIFY_FAILED, ERR_NO_API, ERR_INVALID_VALUE
```

**界面使用（建议键名，可按需扩展，但不得删除已有键）：**

```
PANEL_TITLE, STATE_IDLE, STATE_DISABLED, STATE_APPLIED, STATE_PENDING,
STATE_ERROR, STATE_UNAVAILABLE,
LABEL_CURRENT, LABEL_TARGET, LABEL_BASELINE, LABEL_LATENCY, LABEL_SPEC,
LABEL_BASE, LABEL_ROLE, LABEL_ENABLED, LABEL_FORMULA, LABEL_STATUS,
LABEL_LAST_ERROR, LABEL_HOME, LABEL_WORLD,
CONTEXT_CITY, CONTEXT_INSTANCE, CONTEXT_WORLD,
ROLE_MELEE, ROLE_RANGED, ROLE_UNKNOWN,
SETTING_ENABLED, SETTING_SHOW_STATUS, SETTING_CHAT_FEEDBACK,
SETTING_BASE_MODE, BASE_MODE_AUTO, BASE_MODE_MANUAL, SETTING_MANUAL_BASE,
SETTING_ADAPTIVE, SETTING_MARGIN, SETTING_MIN, SETTING_MAX,
SETTING_HYSTERESIS, SETTING_LATENCY_SOURCE,
LATENCY_WORLD, LATENCY_HOME, LATENCY_AVG, LATENCY_MAX,
SETTING_STATUS_FONT, SETTING_STATUS_FONT_SIZE,
BUTTON_RESET_POSITION, BUTTON_RESET_SETTINGS, BUTTON_REFRESH,
ADVANCED_SHOW, ADVANCED_HIDE, TOOLTIP_STATUS_BAR, TOOLTIP_ADVANCED,
MSG_RESET_DONE, MSG_POSITION_RESET, MSG_REFRESHED,
VALUE_UNAVAILABLE, SLASH_HELP
```

## 6. 测试约定

- `tools/check-syntax.mjs`：用 `luaparse`（luaVersion 5.1）解析仓库内所有 `.lua`。
- `tests/wow_stub.lua`：在无客户端环境下伪造 `CreateFrame` / `C_Timer` / `GetNetStats` /
  `C_Map` / `InCombatLockdown` / `C_CVar` 等，让**核心**（不加载 Options）可以真实运行。
- `tools/run-tests.mjs`：用 `fengari`（Lua 5.3）执行 `tests/run.lua`。
  注意：代码必须同时兼容 5.1 与 5.3 —— 不使用 `goto`、整除 `//`、位运算符号、`table.unpack`
  （用 `unpack` 时需自行兜底或避免）。
- `tools/verify.ps1`：一条命令跑完语法 → 单测 → 结构/版本一致性检查 →（可选）打包。
- 任何声称「已完成」的交付，都要贴出实际命令与输出。

## 7. 发布包结构

```
AutoSpellQueue/
  AutoSpellQueue.toc
  AutoSpellQueue_Locale.lua
  AutoSpellQueue_Formula.lua
  AutoSpellQueue_CVar.lua
  AutoSpellQueue.lua
  AutoSpellQueue_Options.lua
```

zip 根目录必须正好是 `AutoSpellQueue/`（文件夹名 == `.toc` 文件名 == 插件名），
否则客户端不会加载。这一条由 `tools/package.ps1` 保证。
