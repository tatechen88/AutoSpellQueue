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
| 1 | `AutoSpellQueue_Locale.lua` | enUS/zhCN/zhTW 三语键表，设置 `ns.L(key)`（键数不写死：`spec_locale` 保证三语键集一致，取数用 `node tools/run-tests.mjs`） | 仅 `GetLocale()` |
| 2 | `AutoSpellQueue_Formula.lua` | 纯计算：专精 / 延迟 / 场景 → 目标值 | **禁止** |
| 3 | `AutoSpellQueue_Latency.lua` | 纯算法：延迟平滑、抖动估计 → 自适应余量与写入阈值 | **禁止** |
| 4 | `AutoSpellQueue_CVar.lua` | 唯一读写 `SpellQueueWindow` 的地方，环境可注入 | 通过 `env` 表 |
| 5 | `AutoSpellQueue.lua` | 配置校验与迁移、所有权状态机、事件、定时刷新 | 是 |
| 6 | `AutoSpellQueue_Options.lua` | 设置面板（极简）、悬浮状态条、斜杠命令 | 是 |

运行期只有这 6 个 `.lua` + 1 个 `.toc`。`tests/`、`tools/`、`docs/` **不进发布包**。

## 3. 设计原则：算法 > 设置

**玩家只需要决定两件事**：插件开不开（`enabled`）、要不要看悬浮读数（`showStatus`）。
其余一切——安全余量、写入阈值（迟滞）、延迟来源、窗口上下限、状态条字体、**多久检测一次**——**都由插件自己决定**：

- 能量化的（延迟、抖动）→ `Latency` 模块按实测算；
- 不能量化但可以定死的（上下限 50–400、心跳 300 秒）→ 内部常量；
- 玩家可能确有异议的（某专精的基础值）→ **只留命令级逃生口** `/asq base <ms>`，不进面板。

**新增任何配置键之前必须回答**：玩家凭什么比插件更懂这个数？回答不了就应该写成算法常量，
并由 `tests/spec_core.lua` 的「配置白名单」用例拦住（多一个键就会 FAIL）。

### 采样策略：只在"该学"的时候学

固定节奏轮询是没必要的开销，也是数值抖动的来源。延迟在几分钟内不会跳变，而真正会改变答案的事件
（登录、换区、**进副本 / 团本**、切专精、别的插件改值）客户端都会主动通知我们。所以：

| 状态 | 何时进入 | 行为 |
|---|---|---|
| **settling**（学习期） | 登录 / 换区 / 进副本团本（`PLAYER_ENTERING_WORLD`、`ZONE_CHANGED_NEW_AREA`）、心跳发现漂移 | 每 `SETTLE_INTERVAL`(15s) 采样一次；平滑值不再移动（`IsConverged`）或达到 `MAX_SETTLE_SAMPLES`(8) 后结束 |
| **pending**（有活没干完） | 战斗中待写入 / 待归还 | 每 `PENDING_INTERVAL`(15s) 重试（短暂状态） |
| **error**（写失败） | 写入或归还失败 | 前 `RETRY_ATTEMPTS`(3) 次每 `RETRY_INTERVAL`(60s) 重试，之后退避到心跳 |
| **fixed**（已固定） | 学习结束后 | 每 `HEARTBEAT_SECONDS`(300s) 只做一次**廉价漂移检查**：读数与平滑值之差超过 `DRIFT_DEADBAND`(25ms) 才重新学习；否则不决策、不写入 |

心跳**不喂样本**（否则单个漂移样本会把 EMA 拽动半程并造成无谓写入）；它只负责判断"要不要重新学"。

跨会话记忆：学习结束时把学到的延迟与抖动写入 `latencyCache`，下次登录**先用它**算出正确值，
不等 `GetNetStats()`；第一笔实测与记忆值相差超过死区时**直接采用实测**（不慢慢滑几分钟）。

### 设置面板：StockTake 风格（同一作者、同一客户端）

面板刻意与姊妹插件 **StockTake**（`D:\AI\Workspaces\WOW\StockTake-dev`；已安装副本的
`Options.lua` 是参照实现）保持同一套做法与观感，玩家只需要学一次布局：

| 元素 | 做法 |
|---|---|
| 标题 | `GameFontNormalLarge` 直接锚在面板 `TOPLEFT (16, -16)`（与 StockTake 完全相同） |
| 一行状态 | `GameFontHighlightSmall`，标题下方；**按状态着色**（失败醒目）。StockTake 的同一位置是「命令：…」提示行 |
| 控件 | **暴雪原生控件，零自绘**：`SettingsCheckboxTemplate`（回退 `InterfaceOptionsCheckButtonTemplate`）、`UIPanelButtonTemplate` |
| 布局 | 控件直接锚在面板上，x=16，纵向 32–36px 节奏；**没有滚动框**（StockTake 也没有，那类坑随之消失） |
| 提示 | `AttachTooltip` 用 `SetScript` 接管 `OnEnter/OnLeave`（覆盖模板的 DefaultTooltipMixin），并隐藏模板的 `HoverBackground` |

**两条来自 StockTake 源码的实测坑（必须遵守，`tests/wow_stub.lua` 已按此建模）**：

1. `SettingsCheckboxTemplate` **没有文本元素**，对它 `Button:SetText` 会造一个**无锚点**字体串——
   API 读回正常但屏幕上看不见。所以复选框标签一律**自建 + 带锚点**。
2. `$parentText` 形式的文本元素**只有控件有全局名时才会被创建**：无名按钮 `SetText` 同样落到
   看不见的字体串上。所以模板按钮**必须命名**（本插件用 `AutoSpellQueueResetButton`）。

页面上不写长句：任何一行可见文字 ≤ 60 字节、可见行 ≤ 6 行（用例守门）。长解释（做什么、算式、
采样策略、诊断与 `/asq base` 入口）都在悬停提示里。

> 实现注意：提示必须挂在**帧**上。`FontString` 在客户端收不到鼠标事件，且**没有 `HookScript`**
> （只有 `SetScript`）——挂错会抛错并打断整页构建（2026-09-28 真机复现）。

### 数字的颜色 = 连接好不好（不是状态好不好）

玩家看得见的那个数字（悬浮状态条，以及面板状态行）按**延迟品质**着色，**状态条的 1px 边框与数字同色**
（`Options.RecolorBorder`，透明度 0.8 略低于文字，保证数字先被读到）：

| 判据 | 颜色 |
|---|---|
| 延迟正常（≈ 本机平时水平） | **白色**——正常状态不需要吸引注意 |
| 延迟明显偏高 | **红色** |
| 客户端还没报出延迟（未知） | 白色（不猜） |
| `error` / `unavailable` / `disabled` / `pending` | 保持各自的**状态色**（失败红、等待橙、关闭灰）——那些不是延迟问题 |

偏高的判据是**相对本机平时**的，不是固定阈值（固定阈值会让平时就 200ms 的玩家永远看到红色）：

```
threshold = clamp(本机平时延迟 + 60ms, 120ms, 250ms)
```

`本机平时` = 上一节跨会话记住的 `latencyCache.value`；没学到时用下限 120ms。
实现在 `Latency.HighThreshold` / `Latency.Quality`（纯函数，`good` / `high` / `unknown`），
`Core.GetStatus()` 暴露 `latencyQuality` / `latencyNormal` / `latencyHighAt`；
颜色映射在 `Options.ValueColor`。偏高时悬停提示会写明「当前 X ms，平时约 Y ms」，
否则红色只是个谜（`HINT_LATENCY_HIGH` / `HINT_LATENCY_HIGH_NO_BASE`）。

> 真机验证：正常延迟 → 白字白框、聊天前缀白色；用临时阈值探针（`HIGH_FLOOR = 10`）让真实读数
> 触发 → 红字红框。两者都截图确认。

### 插件名：显示名随语言，内部名恒定

| 用途 | 取值 | 说明 |
|---|---|---|
| 界面显示名（面板标题、提示标题、聊天前缀） | `ns.L("ADDON_TITLE")` | zhCN/zhTW = `施法容限`，enUS = `Auto Spell Queue` |
| `.toc` 插件列表名 | `## Title` / `## Title-zhCN` / `## Title-zhTW` | 必须与 `ADDON_TITLE` 三语取值逐字一致（`spec_locale` 断言） |
| 设置分类内部名 / ID（`panel.name`、`RegisterCanvasLayoutCategory` 第三个参数） | 常量 `AutoSpellQueue`（= 文件夹名，来自 `...` 的第一个参数） | **不得随语言变化**：客户端用它把页面挂到本插件下并重新打开，也是 `OpenToCategory` 的 ID |
| 存档变量 | `AutoSpellQueueDB`（+ 兼容读取 `Tate_ASQDB`） | 同上，恒定 |

> 实测踩坑：语言表的值顺序是 `{ zhCN, zhTW, enUS }`（见文件头注释）。第一次加 `ADDON_TITLE` 时
> 按 `{ enUS, zhCN, zhTW }` 写了，中文客户端会显示成英文名——新加的「插件显示名」用例当场抓到。

### 状态条悬停提示的摆位（必须让开鼠标，且四个边角都不能出屏）

光标就停在读数条上，所以**提示框压到读数条 = 压住鼠标**，这是最不能接受的一条；另外读数条可以被拖到
屏幕任何位置，所以"能不能放得下"必须**每次都按真实几何算**，不能靠客户端的夹紧兜底——夹紧会把框顶回
读数条和光标上（玩家反馈的"读数条放屏幕下方时鼠标完全看不到"就是这么来的）。

实现：`Options.PickTooltipAnchor(screen, owner, tip, gap)` —— **纯函数**，对任意屏幕 / 读数条 / 提示框
尺寸求位置，返回 4 个候选里第一个满足「**完整落在屏幕内** 且 **不与读数条相交**」的方案：

| 优先级 | 候选 | 说明 |
|---|---|---|
| 1 | 下方 + 左对齐（`TOPLEFT ← BOTTOMLEFT`，−8px） | 读数条通常在屏幕上方，往下摆离光标最远 |
| 2 | 下方 + 右对齐（`TOPRIGHT ← BOTTOMRIGHT`） | 读数条贴右边缘时用，避免右侧出屏 |
| 3 | 上方 + 左对齐（`BOTTOMLEFT ← TOPLEFT`，+8px） | 读数条在屏幕下方时用 |
| 4 | 上方 + 右对齐（`BOTTOMRIGHT ← TOPRIGHT`） | 右下角 |

四个都放不下（屏幕极小或提示框比屏幕还高）时，退回「上下空间更大」的一侧——仍然不与读数条重叠
（选对上下方向即满足），并保留 `SetClampedToScreen` 作为最后保险。

**顺序很重要：先 `Show()` 再摆位。** 客户端要显示之后才知道提示框的真实宽高
（Show 之前是 0），早期版本用"Show 前的高度"判断放不放得下，于是永远判定"放得下"→ 底部场景翻车。
因为摆位发生在同一帧内，玩家看不到中间状态。摆位后再用真几何复查一次（是否完整落屏、是否压到读数条），
不合格就换另一侧。

其它：玩家按住拖动时 `OnMouseDown` 立刻 `GameTooltip:Hide()`。

用例（`spec_options`）：`提示框摆位（纯函数）：屏幕四角 + 中央…`、`提示框摆位：屏幕左右边缘时自动换对齐方向…`、
`提示框摆位：极小屏幕…`、`状态条提示框：真机路径下四个角…`、`拖动状态条时提示框必须立刻消失…`。
真机抽查（2026-09-28 截图）：默认位（顶部）→ 挂下方；左下角 → 挂上方；右下角 → 挂上方 + 右对齐。
真机验证技巧：短命令 `AutoSpellQueueStatusBar:ClearAllPoints()` + `:SetPoint(...)` 可以把读数条钉到
任意边角，再用 `/run local b=AutoSpellQueueStatusBar b:GetScript("OnEnter")(b)` 显示提示框后截图。

### 只有一套配色：`Options.SignalColor()`

### 只有一套配色：`Options.SignalColor()`

插件的**每一个**着色表面都从同一个函数取色，不允许任何地方自带颜色（原来的品牌绿已全部移除）：

| 表面 | 取色方式 |
|---|---|
| 悬浮状态条：数字 + 1px 边框 | `StatusBarVisual` → `ValueColor`（边框透明度 0.8，比文字略淡） |
| 面板状态行 | 同上 |
| 状态条悬停提示的标题行 | `SignalColor()` |
| 独立回退窗口：边框 + 标题（`AddUpdater` 实时更新） | `SignalColor()` |
| **聊天前缀**（`Core.Output`） | `ns.AccentColor`（由 Options 发布，Core 自己不拥有任何颜色） |
| `.toc` 的插件名（插件列表里） | **无颜色码**，用客户端默认色（静态元数据无法随延迟变化，所以不做彩色标识） |

`SignalColor()` 返回**三个通道值**（不是颜色表）：早期版本返回表，而调用处按 `r,g,b` 解包 →
真机上 `GameTooltip:AddLine(标题, table, nil, nil)` 会出错、颜色失效。这条由新增的「统一配色」
用例当场抓到（断言提示标题在偏高时必须为红，实得白）。

## 4. 取值公式（唯一出处）

```
margin     = clamp(40 + 1.5 × jitter, 30, 150)         -- 见 §5，玩家不可调
hysteresis = clamp(5 + 1.0 × jitter, 5, 25)            -- 同上

城市（安全区）     : target = base
副本 / 野外       : target = max(base, latency + margin)
最终              : clamp(round(target), 50, 400)
```

- `base` 来自 `Formula`：先按 specID 查表（140–245ms），未知专精回退到职业值，再回退到定位兜底值，**永不返回 nil**；
  若 `baseOverride` 存在（仅 `/asq base` 能写入）则用它，且**仍然叠加延迟自适应**。
- `latency` 是 `Latency` 的**平滑值**（上升快、下降慢的 EMA），`world` 为 0 时回退 `home`，全为 0 时该次采样被忽略。
- `jitter` 是最近 20 个采样的**平均绝对偏差**（不是极差：一次 600ms 尖刺不该把余量顶满）。
- 场景判定：`IsInInstance()` → 副本；否则沿 `parentMapID` 上溯最多 4 层找 `Enum.UIMapFlag.IsCityMap`（`0x100000`）→ 城市；其余野外。
- 客户端范围 0–400ms 由 `CVar.MIN` / `CVar.MAX` 与内部常量共同约束。

### 配置（schema v2）

| 键 | 默认 | 区间 | 来源 |
|---|---|---|---|
| `enabled` | `true` | bool | 玩家（面板开关） |
| `showStatus` | `true` | bool | 玩家（面板开关） |
| `statusBarPos` | `nil` | `{x, y}` 有限数字 | 插件账本（拖动状态条产生） |
| `baseOverride` | `nil` | 50–400 | 逃生口，**只能**由 `/asq base` 写入 |
| `latencyCache` | `nil` | `{value 1–999, jitter, samples, at}` | 插件账本：上次学到的延迟，登录时先用它 |
| `ownership` / `stats` | `nil` | 见 §6 | 插件账本（运行时） |

内部常量（不在配置里）：`Core.WARMUP_DELAYS = {2,5,10,20,40}`、
`Core.SETTLE_INTERVAL = 15`、`Core.PENDING_INTERVAL = 15`、`Core.RETRY_INTERVAL = 60`、
`Core.RETRY_ATTEMPTS = 3`、`Core.HEARTBEAT_SECONDS = 300`、`Core.MAX_SETTLE_SAMPLES = 8`、
`Core.WINDOW_MIN = 50`、`Core.WINDOW_MAX = 400`、`Core.SCHEMA_VERSION = 2`，
以及 `Latency.BASE_HEADROOM / JITTER_FACTOR / MARGIN_MIN / MARGIN_MAX / HYSTERESIS_* /
SMOOTH_UP / SMOOTH_DOWN / WINDOW / MIN_SAMPLES / STABLE_EPSILON / DRIFT_DEADBAND`。

**v1 → v2 迁移**：v1 的 12 个旋钮（`baseMode`/`manualBase`/`adaptive`/`latencySource`/`margin`/
`minWindow`/`maxWindow`/`hysteresis`/`statusFont`/`statusFontSize`/`chatFeedback`/`showAdvanced`）
由 `Sanitize` 从存档中清除；其中玩家唯一可能刻意设置过的 `manualBase`（且 `baseMode == "manual"`）
迁移为 `baseOverride`，不丢数据。

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

`cfg` 这里是 `Core.EffectiveOptions()` 产出的**扁平选项表**（玩家设置 + 算法实测值 + 内部常量），
不是存档表本身；`Decide` 与 `Formula` 都只认这张表。

### `ns.Latency`（纯算法，禁止调用 WoW API）

```lua
Latency.New(maxSamples)              -- 跟踪器（默认保留 WINDOW=20 个采样）
Latency.Push(tracker, world, home)   -- 采样；world<=0 回退 home；两者都<=0 则忽略（不污染均值）
Latency.Reset(tracker)               -- 进入世界/换图时清空（换了连接上下文）
Latency.Count / Value / Jitter       -- 累计采样数 / 平滑延迟 / 平均绝对偏差
Latency.Margin(tracker)              -- 自适应余量：clamp(40 + 1.5×jitter, 30, 150)
Latency.Hysteresis(tracker)          -- 写入阈值：clamp(5 + 1.0×jitter, 5, 25)
Latency.Describe(tracker)            -- -> value, margin, hysteresis
Latency.IsStable(tracker)            -- 采样≥3 且 jitter ≤ 3
```

平滑是**不对称**的：`SMOOTH_UP = 0.5`（延迟变差时立刻跟上，绝不欠缓冲）、`SMOOTH_DOWN = 0.15`
（变好时慢慢放手，避免来回抖动导致反复写值）。

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
Core.STATE.* / Core.DEFAULTS / Core.REASON_KEY / Core.SCHEMA_VERSION
Core.WINDOW_MIN / Core.WINDOW_MAX        -- 内部安全边界（50 / 400），不是设置
Core.SETTLE_INTERVAL / Core.PENDING_INTERVAL / Core.RETRY_INTERVAL /
Core.RETRY_ATTEMPTS / Core.HEARTBEAT_SECONDS / Core.MAX_SETTLE_SAMPLES
Core.L(key) / Core.Output(text) / Core.Now()
Core.GetConfig()                  -- 校验后的配置表；改值请走 SetConfig
Core.SetConfig(key, value, opts)  -- opts = { noRefresh = true }；未知键与 v1 退休键都返回 false
Core.EffectiveOptions()           -- 配置 + 算法实测值 + 内部常量 → Decide/Formula 吃的扁平表
Core.TrackLatency(snap)           -- 把快照里的延迟喂给 Latency（每次 Refresh 调用）
Core.latency                      -- 跟踪器实例（测试可直接检查/清空）
Core.SetBaseOverride(v|nil)       -- 逃生口：数字=固定基础值，"auto"/nil=跟随专精表
Core.BeginSettle(reason)          -- 进入学习期（登录/换区/进副本/漂移）
Core.SeedLatency() / Core.RememberLatency()   -- 跨会话记住并复用学到的延迟
Core.DesiredInterval()            -- 当前状态该用多长的间隔；nil = 完全不用唤醒
Core.SetEnabled(bool) / Core.IsEnabled()
Core.ResetSettings()              -- 恢复默认，保留所有权与统计
Core.Refresh(reason)              -- 重读状态、喂采样、执行决策，然后 SyncTicker；未进世界时什么都不做
Core.SyncTicker()                 -- 定时器跟随状态：学习 / 有待办 / 已固定（心跳）
Core.RestoreOwnership(reason)     -- 归还玩家原值；返回 ok, reason
Core.GetLiveValue()               -- 实时读 CVar（不缓存）
Core.Snapshot()                   -- 最近一次读取的游戏状态
Core.Decide(options, snap)        -- 纯决策（options 见 Core.EffectiveOptions）
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
  schemaFuture, importedFrom, reason,
  baseOverride,   -- 逃生口当前值（nil = 跟随专精表）
  margin, hysteresis, jitter, smoothed, samples, stable,   -- 算法自述
  cadence,        -- "settling" | "pending" | "fixed"（采样策略，供 /asq status）
  settleReason, settleSamples, intervalSeconds, heartbeatSeconds, converged,
  cachedLatency, cachedLatencyAt }   -- 跨会话记住的延迟

### 事件

`ADDON_LOADED`（只认自己）· `PLAYER_LOGIN` · `PLAYER_ENTERING_WORLD`（重置采样并重新决策）·
`PLAYER_SPECIALIZATION_CHANGED`（**只处理 `player`**）·
`ZONE_CHANGED_NEW_AREA` · `ZONE_CHANGED` · `PLAYER_REGEN_ENABLED`（重新决策）· `CVAR_UPDATE`（0.5 秒防抖）· `PLAYER_LOGOUT`（归还）。

> 事件注册逐个 `pcall`：一个坏事件名不得中断其余注册，也不得中断文件后续代码。

### 斜杠命令（由 `Options` 提供）

`/asq` 打开设置 · `/asq status` 诊断 · `/asq reset` 重置设置 · `/asq unlock` 复位状态条位置并重新显示 ·
`/asq base <50-400>` 固定基础值 · `/asq base auto` 恢复跟随专精表。别名 `/autospellqueue`。

## 6. Locale 契约

`ns.L = function(key) ... end`，提供 **enUS（必备）**、`zhCN`、`zhTW` 三套字符串，**键集必须完全一致**。
未列出的语言回退 enUS；enUS 也缺才回退 key 本身。

核心直接使用的键：`CHAT_ERROR`（参数为失败原因），以及 §6 的 7 个 `ERR_*`。
改值不再有聊天提示——插件在工作时保持安静，只有错误会说话（`Core.NotifyError` 限流 120 秒）。

> 历史教训：v2.0.0 开发中曾把「英文 = 回退 key 本身」当作设计，结果英文客户端会直接显示
> `STATE_APPLIED` 这类内部键名。英文必须和其它语言一样是真实文案。

## 7. 测试与打包约定

- **双版本兼容**：代码必须同时能在客户端（Lua 5.1）与测试运行器（fengari，Lua 5.3）下工作。
  禁止 `goto`、整除 `//`、位运算符、`table.unpack`、`setfenv`、`loadstring`、`math.mod`、`newproxy`。
  `tools/check-syntax.mjs` 的第二阶段会 lint 这些。
- **`tests/wow_stub.lua`**：伪造 `CreateFrame` / `C_Timer` / `C_CVar` / `C_Map` / `GetNetStats` / `InCombatLockdown` /
  `Settings` / `SlashCmdList` 等，让**全部 6 个运行期文件**能在 Node 里真实跑起来。
  三条会影响测试语义的建模前提（改动会波及整份测试）：新建 frame 默认「已显示」；`frame.name` 会被 Settings API 当作标题；
  **FontString 没有字体时 `SetText` 会抛错**（与客户端一致，见 `tests/REGRESSIONS.md` 第 13 条）。
- **`tools/run-tests.mjs`**：按 `.toc` 顺序加载 6 个运行期文件（共享同一个 `ns`）后执行 `tests/run.lua`。
- **`tools/verify.ps1`**：① 语法 + 双兼容 lint ② 单测 ③ 结构与版本一致性 ④（`-Package`）打包。
  任何一步失败都 exit 1；结构与版本检查包含 `.toc` 的版本号 / Interface / SavedVariables / 加载顺序（6 个 .lua）、
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
  AutoSpellQueue_Latency.lua
  AutoSpellQueue_CVar.lua
  AutoSpellQueue.lua
  AutoSpellQueue_Options.lua
```

zip 根目录必须**正好**是 `AutoSpellQueue/`（文件夹名 == `.toc` 文件名 == 插件名），否则客户端不会加载。
发布引用指纹时用**逐条目内容 sha256**（与打包器、时区、压缩等级无关）；zip 自身哈希只作同一脚本产出的快速校验。
