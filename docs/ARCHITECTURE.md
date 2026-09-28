# AutoSpellQueue — 架构与模块契约

> 面向开发者。**改接口先改这份，再改代码。** 最后重写：2026-09-28（v2.0.0）。
> 玩家向说明在 [`DESCRIPTION.md`](DESCRIPTION.md)；文档归谁管见 [`README.md`](README.md)。

## 1. 它做什么

只做一件事：把 `SpellQueueWindow`（施法队列窗口，0–400ms，客户端默认 400）保持在适合当前专精与网络延迟的值，
并在插件不管理它时，把玩家原本的值放回去。

**不做**：自动施法、按键循环、战斗自动化、读战斗日志、联网、遥测。任何「替玩家做战斗决策」的功能都属于越界。

## 2. 文件与加载顺序

`.toc` 的顺序即加载顺序。模块通过 `.toc` 传入的私有命名空间表 `ns` 互相访问，**不使用 `_G` 全局**
（唯一例外：`_G.AutoSpellQueue` 指向核心，方便 `/dump` 排查）。

| # | 文件 | 职责 | 可否调用 WoW API |
|---|---|---|---|
| 1 | `AutoSpellQueue_Locale.lua` | 136 个键 × enUS/zhCN/zhTW，设置 `ns.L(key)` | 仅 `GetLocale()` |
| 2 | `AutoSpellQueue_Formula.lua` | 纯计算：专精 / 延迟 / 场景 → 目标值 | **禁止** |
| 3 | `AutoSpellQueue_CVar.lua` | 唯一读写 `SpellQueueWindow` 的地方，环境可注入 | 通过 `env` 表 |
| 4 | `AutoSpellQueue.lua` | 配置校验与迁移、所有权状态机、事件、定时刷新 | 是 |
| 5 | `AutoSpellQueue_Options.lua` | 设置面板、悬浮状态条、斜杠命令 | 是 |

运行期只有这 5 个 `.lua` + 1 个 `.toc`。`tests/`、`tools/`、`docs/` **不进发布包**。

## 3. 取值公式（唯一出处）

```
城市（安全区）     : target = base
副本 / 野外       : target = max(base, latency + margin)      （adaptive = false 时退化为 base）
最终              : clamp(round(target), minWindow, maxWindow)
```

- `base` 来自 `Formula`：先按 specID 查表（140–245ms），未知专精回退到职业值，再回退到定位兜底值，**永不返回 nil**。
- `latency` 由 `PickLatency(latencySource, home, world)` 选出：默认 `world`，`world == 0` 时回退 `home`；可选 `home` / `avg` / `max`。
- 场景判定：`IsInInstance()` → 副本；否则沿 `parentMapID` 上溯最多 4 层找 `Enum.UIMapFlag.IsCityMap`（`0x100000`）→ 城市；其余野外。
- 客户端范围 0–400ms 由 `CVar.MIN` / `CVar.MAX` 与配置上下限共同约束。

### 默认配置与合法区间

| 键 | 默认 | 区间 / 取值 | 说明 |
|---|---|---|---|
| `enabled` | `true` | bool | 总开关 |
| `baseMode` | `"auto"` | `auto` / `manual` | `manual` 时用 `manualBase` |
| `manualBase` | `200` | 50–400 | 仅手动模式 |
| `adaptive` | `true` | bool | 关掉后只用 base |
| `latencySource` | `"world"` | `world`/`home`/`avg`/`max` | |
| `margin` | `50` | 0–300 | 加在延迟上 |
| `minWindow` / `maxWindow` | `50` / `400` | 0–400，且 min ≤ max | 越界与 `min>max` 由 `Sanitize` 修正；**UI 的上限步进下限是 50**，`maxWindow < 50` 时状态卡给出警告（不改写配置） |
| `hysteresis` | `10` | 0–100 | 已接管后差值小于它就不写 |
| `showStatus` | `true` | bool | 悬浮状态条 |
| `statusFont` / `statusFontSize` | `Fonts\FRIZQT__.TTF` / `12` | 非空字符串 / 8–32 | 可改用 LibSharedMedia 字体名 |
| `statusBarPos` | `nil` | `{x, y}` 数字 | 相对 UIParent 左上角 |
| `chatFeedback` | `false` | bool | 每次改值都在聊天框报告 |
| `showAdvanced` | `false` | bool | 设置面板折叠状态 |
| `ownership` / `stats` | `nil` | 见 §4 | 运行时写入 |

内部常量（不在配置里）：`Core.REFRESH_SECONDS = 15`、`Core.WARMUP_DELAYS = {2,5,10,20,40}`、`Core.SCHEMA_VERSION = 1`。

## 4. 状态机不变量（改动必须保持）

1. **写入必须被验证。** `CVar:Write()` 只有在「API 未拒绝」**且**「读回值与目标一致」时才返回成功。
   失败既不更新 `ownership.lastApplied`，也不把状态显示成已应用。
2. **所有权显式记录。** 只要插件写过这个 CVar，`db.ownership` 就存在，记录 `baseline`（接管前的玩家值）、
   `lastApplied`（插件最后写入并被验证的值）、`startedAt`、`schema`。
3. **只在仍然是自己的值时才恢复。** `current ~= lastApplied`（玩家或其他插件改过）时**只放弃所有权，不写回 baseline**。
4. **战斗中不写。** 战斗中只把状态标为 `pending`，**不缓存待重放目标**；`PLAYER_REGEN_ENABLED` 重新读取实时状态再决策。
   这条对「应用」和「归还」一视同仁。
5. **登出前归还。** `PLAYER_LOGOUT` 尝试写回 baseline；失败则保留所有权记录，下次登录仍可归还。
   **刷新定时器跟随「启用 **或** 仍持有所有权」**（`Core.SyncTicker`）：归还被战斗推迟或写失败时，
   15 秒定时器继续重试，不依赖下一次换图事件。
6. **未来 schema 不降级。** `schemaVersion` 高于当前值时原样保留并标 `schemaFuture`，不强行改写用户数据。
7. **外部改值只记录，不覆盖。** 检测到 `current ~= lastApplied` 时记 `stats.externalChangeAt` 并继续按目标管理
   （启用状态下），但 **baseline 不重设**——「归还玩家接管前的值」这句承诺保持不变。

### 决策函数与状态

`Core.Decide(cfg, snap)` 是**纯函数**（无副作用、不调用游戏 API），返回 `kind`：

| kind | 含义 |
|---|---|
| `none` | 无需动作（已达目标 / 未启用 / 差值在迟滞内） |
| `apply` | 写入 `action.target` |
| `restore` | 写回 `action.value`（baseline） |
| `wait` | 战斗中，仅标记 `pending`（应用与归还都可能走这里） |
| `release` | 放弃所有权，不写入 |
| `unavailable` | 读不到 CVar，报错 |

状态值 `Core.STATE`：`idle`（未进入世界）· `disabled` · `applied` · `pending` · `error` · `unavailable`。

### 失败原因（`CVar.ERR_*` → `Core.REASON_KEY` → Locale 键）

| 常量 | Locale 键 | 触发条件 |
|---|---|---|
| `ERR_READONLY` | `ERR_READONLY` | `GetCVarInfo` 报 `isReadOnly` |
| `ERR_COMBAT` | `ERR_COMBAT` | `InCombatLockdown()` 为真 |
| `ERR_UNAVAILABLE` | `ERR_UNAVAILABLE` | 读不到该 CVar（不得伪造默认 400） |
| `ERR_REJECTED` | `ERR_REJECTED` | `SetCVar` 明确返回 `false` |
| `ERR_VERIFY` | `ERR_VERIFY_FAILED` | 读回值 ≠ 目标（返回值第三个为**读到的实际值**） |
| `ERR_NO_API` | `ERR_NO_API` | API 缺失或调用抛错 |
| `ERR_INVALID_VALUE` | `ERR_INVALID_VALUE` | 传入值非有限数字 |

### SavedVariables 与迁移前提

- `AutoSpellQueueDB` 为主，`.toc` 同时声明 `Tate_ASQDB` 供一次性导入。
- **关键前提**：客户端只加载 `WTF\...\SavedVariables\<插件文件夹名>.lua`。旧设置写在 `Tate_ASQ.lua` 里，
  删掉旧插件后该文件不会被加载，所以导入**不会自动发生**——玩家需把该文件复制为 `AutoSpellQueue.lua`
  （见 `README.md` 升级步骤）。`Core.ImportLegacy()` 拿不到数据就静默返回，不报错、不提示。

## 5. 对外接口

### `ns.Formula`（纯函数，禁止调用 WoW API）

```lua
Formula.CITY_MAP_FLAG                    -- 0x100000 (Enum.UIMapFlag.IsCityMap)
Formula.HasFlag(value, flag)             -- 不依赖 bit 库的位测试
Formula.Clamp(v, lo, hi)                 -- 交换边界容忍；NaN 永不逸出
Formula.Round(v)                         -- NaN/inf 安全
Formula.SafeNumber(v)                    -- tonumber + NaN/inf 归零
Formula.Classify(specID, classFile)      -- "melee" | "ranged"
Formula.IsKnownSpec(specID)
Formula.GetBase(cfg, specID, classFile)
Formula.ClassifyContext(isInInstance, mapFlags)  -- "instance" | "city" | "world"
Formula.PickLatency(source, home, world)
Formula.ComputeTarget(cfg, specID, classFile, home, world, context)  -- -> target, role, base, latency
Formula.Describe(cfg, specID, classFile, home, world, context)       -- -> kind, base, latency, margin
```

### `ns.CVar`

```lua
CVar.NAME            -- "SpellQueueWindow"；CVar.MIN = 0；CVar.MAX = 400
CVar.ERR_*           -- 见上表
CVar:Info()          -- { known, value, defaultValue, isReadOnly, isSecure, isLocked,
                     --   isStoredAccount, isStoredCharacter }   永不返回 nil
CVar:Read()          -- value(number) | nil, reason
CVar:RawRead()       -- 原始字符串 | nil
CVar:IsAvailable() / CVar:IsWritable()   -- boolean, reason
CVar:Write(v)        -- ok, reason, applied
                     --   成功：applied = 写入并被读回确认的值
                     --   ERR_VERIFY 失败：applied = 读回的实际值（便于诊断「API 说成功但值没变」）
CVar.SameValue(a, b)
CVar.GetEnv() / CVar.SetEnv(env)         -- 测试注入点
```

`env` 需提供：`getCVarInfo(name)`、`getCVar(name)`、`setCVar(name, str)`、`inCombat()`。
`C_CVar.GetCVarInfo` 的返回顺序按官方文档建模：
`value, defaultValue, isStoredServerAccount, isStoredServerCharacter, isLockedFromUser, isSecure, isReadOnly`。

### `ns.Core`

```lua
Core.STATE.* / Core.DEFAULTS / Core.REASON_KEY / Core.SCHEMA_VERSION / Core.REFRESH_SECONDS
Core.L(key) / Core.Output(text) / Core.Now()
Core.GetConfig()                  -- 校验后的配置表；改值请走 SetConfig
Core.SetConfig(key, value, opts)  -- opts = { noRefresh = true }；未知键返回 false
Core.SetEnabled(bool) / Core.IsEnabled()
Core.ResetSettings()              -- 恢复默认，保留所有权与统计
Core.Refresh(reason)              -- 重读状态并执行决策，然后 SyncTicker；未进世界时什么都不做
Core.SyncTicker()                 -- 定时器跟随「启用 或 仍持有所有权」（归还推迟/失败时不至于停摆）
Core.RestoreOwnership(reason)     -- 归还玩家原值；返回 ok, reason
Core.GetLiveValue()               -- 实时读 CVar（不缓存）
Core.Snapshot()                   -- 最近一次读取的游戏状态
Core.Decide(cfg, snap)            -- 纯决策
Core.GetStatus()                  -- 见下
Core.Init()                       -- 创建事件帧（加载时已自动调用）
```

`Core.GetStatus()` 字段：

```lua
{ enabled, state, stateReason, stateReasonKey,
  current,        -- 上一次快照读到的值
  live,           -- 刚刚从客户端读到的值（状态卡的「当前值」用它）
  target,         -- 上一次计算出的目标值
  snapshotAt,     -- 上一次计算的时间戳，UI 用它说明「这是采样值」
  baseline, lastApplied, owned,
  inCombat, inWorld, context, role, base, latency, home, world,
  specID, specName, classFile, cvarInfo,
  lastError, lastErrorAt, applyCount, repairs, externalChange,
  schemaFuture, importedFrom, refreshSeconds, reason }
```

### 事件

`ADDON_LOADED`（只认自己）· `PLAYER_LOGIN` · `PLAYER_ENTERING_WORLD` · `PLAYER_SPECIALIZATION_CHANGED`（**只处理 `player`**）·
`ZONE_CHANGED_NEW_AREA` · `ZONE_CHANGED` · `PLAYER_REGEN_ENABLED`（重新决策）· `CVAR_UPDATE`（0.5 秒防抖）· `PLAYER_LOGOUT`（归还）。

### 斜杠命令（由 `Options` 提供）

`/asq` 打开设置 · `/asq status` 诊断 · `/asq reset` 重置设置 · `/asq unlock` 复位状态条位置并重新显示。
别名 `/autospellqueue`。

## 6. Locale 契约

`ns.L = function(key) ... end`，提供 **enUS（必备）**、`zhCN`、`zhTW` 三套字符串，**键集必须完全一致**。
未列出的语言回退 enUS；enUS 也缺才回退 key 本身。

核心直接使用的键：`CHAT_CHANGED`（参数 target, previous）、`CHAT_RESTORED`、`CHAT_ERROR`，以及 §4 的 7 个 `ERR_*`。

> 历史教训：v2.0.0 开发中曾把「英文 = 回退 key 本身」当作设计，结果英文客户端会直接显示
> `STATE_APPLIED` 这类内部键名。英文必须和其它语言一样是真实文案。

## 7. 测试与打包约定

- **双版本兼容**：代码必须同时能在客户端（Lua 5.1）与测试运行器（fengari，Lua 5.3）下工作。
  禁止 `goto`、整除 `//`、位运算符、`table.unpack`、`setfenv`、`loadstring`、`math.mod`、`newproxy`。
  `tools/check-syntax.mjs` 的第二阶段会 lint 这些。
- **`tests/wow_stub.lua`**：伪造 `CreateFrame` / `C_Timer` / `C_CVar` / `C_Map` / `GetNetStats` / `InCombatLockdown` /
  `Settings` / `SlashCmdList` 等，让**全部 5 个运行期文件**能在 Node 里真实跑起来。
  两条會影响测试语义的建模前提（改动会波及整份测试）：新建 frame 默认「已显示」；`frame.name` 会被 Settings API 当作标题。
- **`tools/run-tests.mjs`**：按 `.toc` 顺序加载 5 个运行期文件（共享同一个 `ns`）后执行 `tests/run.lua`。
- **`tools/verify.ps1`**：① 语法 + 双兼容 lint ② 单测 ③ 结构与版本一致性 ④（`-Package`）打包。
  任何一步失败都 exit 1；结构与版本检查包含 `.toc` 的版本号 / Interface / SavedVariables / 加载顺序、
  `CHANGELOG` 最新条目 == `.toc`、`README` 提到该版本、无残留 `Tate_ASQ*` 文件名。
- **`tools/package.ps1`**：产出 `dist/AutoSpellQueue-<version>.zip`。硬性约束见 §8；打包后会**逐条比对
  zip 内容与工作区文件**、断言每个条目的墙钟 == 固定常量、并**自检「同内容再打一份哈希是否一致」**（可复现性）；
  任一校验失败会删掉产物并 exit 1。

## 8. 发布包结构

```
AutoSpellQueue/
  AutoSpellQueue.toc
  AutoSpellQueue_Locale.lua
  AutoSpellQueue_Formula.lua
  AutoSpellQueue_CVar.lua
  AutoSpellQueue.lua
  AutoSpellQueue_Options.lua
```

zip 根目录必须**正好**是 `AutoSpellQueue/`（文件夹名 == `.toc` 文件名 == 插件名），否则客户端不会加载。
发布引用指纹时用**逐条目内容 sha256**（与打包器、时区、压缩等级无关）；zip 自身哈希只作同一脚本产出的快速校验。
