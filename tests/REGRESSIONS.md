# REGRESSIONS —— 已修缺陷、必须保持的不变量、测试边界

> 这是本仓库的**防回归知识库**：改动核心逻辑前先读它。
> 用法与命令见 [`../AGENTS.md`](../AGENTS.md) 与 [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md)。
> 最后重写：2026-09-28。

## 1. 必须保持的不变量（改了就必须更新对应用例）

| # | 不变量 | 锁定用例 |
|---|---|---|
| 1 | `CVar:Write` 只有在「API 未拒绝」**且**「读回值一致」时才算成功；`pcall` 不抛错 ≠ 成功 | `spec_cvar` 4 条 `P1:`；`spec_core` `P1: API 返回 false…`、`P1: API 谎报 true…` |
| 2 | 写入失败不得记为已应用（不写 `lastApplied`、不加 `stats.applied`、状态是 `error`） | `spec_core` 两条 `P1: … 绝不记为已应用` |
| 3 | 战斗中绝不写 CVar；`PLAYER_REGEN_ENABLED` 必须**重新决策**，不重放旧目标 | `spec_core` `P1: 战斗中不写…`、`P1: 战斗中禁用再启用…`、`P1: 启用中在战斗里禁用…` |
| 4 | 只归还仍然属于我们的值；外部改过就只释放所有权、不覆盖 | `spec_core` `P1: 禁用时若值被外部改过…`、`P1: RestoreOwnership 遇到外部改动…` |
| 5 | 登出归还 baseline；归还失败则保留 ownership，下次登录仍能归还 | `spec_core` `登出归还 baseline…`、`P1: 登出归还失败时保留所有权…` |
| 6 | 未来 `schemaVersion` 不降级、不丢字段 | `spec_core` `Migrate: schemaVersion 更高时不降级…` |
| 7 | 配置 `Sanitize` 面对任何脏输入都不崩、不把坏值带进运行时 | `spec_core` 4 条 `Sanitize: …`、`GetConfig 加载脏存档时先 Sanitize` |
| 8 | `Tate_ASQDB` 老存档一次性导入并清空 | `spec_core` `ImportLegacy: …` |
| 9 | `AutoSpellQueue_Formula.lua` 是纯模块，不碰任何游戏 API | `spec_formula` `源码扫描…`、`运行期：把所有 WoW API 换成陷阱…` |
| 10 | 除 `AutoSpellQueue_CVar.lua` 外没有文件直接读写 `SpellQueueWindow` / `C_CVar` | `spec_core` `结构: 除 CVar.lua 外…` |

## 2. 门禁建成当天抓到并修掉的 5 个核心缺陷

当时由 Lead 修复，对应用例已从 `T.xfail` 转成硬 `T.test`：

| # | 缺陷 | 最小复现（修复前） | 现象 | 现在的用例 |
|---|---|---|---|---|
| 1 | `GetStatus()` 的 `role/base/latency` 恒为 nil：取值来源 `lastSnapshot` 是原始游戏快照，不含这三个字段 | `Core.Refresh("x")` 后 `Core.GetStatus().role == nil` | 设置页「计算式」拿不到数据 | `spec_core` `GetStatus 的 role/base/latency 必须来自最近一次决策` |
| 2 | `Sanitize()` 对「非表且非 nil」的 `ownership` 直接索引 `own.active` | `Core.Sanitize({ ownership = 42 })` | `attempt to index a number value`；损坏存档会让插件在 `ADDON_LOADED` 报错（字符串因元表侥幸不报错） | `spec_core` `Sanitize: ownership 是数字/布尔/字符串时必须丢弃而不是抛错` |
| 3 | `CVar:Info()` 的 `GetCVarInfo` 回退分支把**字符串**写进 `info.value`（主分支有 `tonumber`） | `getCVarInfo` 抛错、`getCVar` 返回 `"275"` 时 `type(CVar:Read()) == "string"` | 违反 `Read() -> number\|nil`；`("%d"):format(current)` 在 Lua 5.3 直接报错 | `spec_cvar` `Info()/Read() 的回退路径必须返回 number（文档契约）` |
| 4 | `Execute()` 只在 `kind == "none"` 时记 `externalChange`，重新夺回管理时诊断丢失 | 写 350 → 外部改 333 → `Refresh()` 后 `externalChange == false` | UI 无法如实告知「值被别人改过」 | `spec_core` `外部改值后重新夺回管理时 externalChange 诊断不应丢失` |
| 5 | `Formula.Clamp(NaN, lo, hi)` 返回 NaN，与注释「never returns NaN」矛盾 | `Formula.Clamp(0/0, 50, 400) == NaN` | Options 夹用户输入时得到 NaN | `spec_formula` `Clamp(NaN) 的结果必须是有限数字…` |
| 6 | **UI 把「战斗中禁用」显示成「已关闭」**：`ResolveState` 在 `enabled=false` 时把 `pending` 一并压成 `disabled`，而文档承诺「战斗中关插件会显示等待脱战」 | 状态条喂 `{enabled=false, state="pending", live=245}` → 显示「已关闭」而非数字 | 玩家以为值已被还回去；文档与 UI 矛盾 | `spec_options` `状态卡：六种状态…` 的 `disabled+pending (combat)` 夹具、`状态条：…` 的关闭中等待脱战断言 |
| 7 | **归还被推迟/失败后不再重试**：`SetEnabled(false)` 无条件停掉 15 秒 ticker，若归还被战斗推迟或写失败，重试只能等下一次 zone/spec/脱战事件——玩家原地不动就永远不还 | 战斗中禁用 → `Core.ticker == nil`；`reject-false` 让归还失败 → 无任何后续重试 | 「关掉插件就把值还给你」在真实场景下可能不兑现 | `spec_core` `修复: 归还被推迟或失败时，定时器必须继续跑…`（含失败后靠 ticker 最终归还） |
| 8 | **上限可低到把施法队列压没**：`maxWindow` 与 `minWindow` 都低于 50ms 时（`min≤max` 合法），公式把一切目标 clamp 成 ≤49ms | `{minWindow=10, maxWindow=30}` → 目标 30 | 凭手感改设置会把预输入时间压到几乎没有，界面一声不吭 | `spec_options` `修复: 上限低于 50ms 时必须给出警告…`（同时钉住 `Sanitize` 对 `min>max` 的复位保护） |
| 9 | **NaN 几何能写进存档甚至抛错**：`Options.Clamp` 缺 NaN 防护，`math.floor(NaN+0.5)` 在 Lua 5.3 直接报错 | 拖动结束时 `GetLeft/GetTop` 返回 NaN → 保存位置抛错 | 脚本处理器里抛错（客户端表现为报错刷屏），坐标也可能写成 NaN | `spec_options` `修复: 状态条几何返回 NaN 时不得写出 NaN 坐标，更不得抛错` |
| 10 | **`CVar.SameValue` 对非数字抛错**：`tonumber` 得 nil 后直接 `math.floor(nil)` | `CVar.SameValue("abc", 200)` → error | 潜在脆弱：任何脏值流到这里都会炸掉刷新链 | `spec_cvar` `SameValue…` 的非数字/NaN/inf 断言 |
| 11 | **诊断输出的「当前值」用的是快照**：面板用 `live`，`/asq status` 用 `status.current`，报 bug 时会误导 | 快照 150 / 实际 300 时 `/asq status` 打印 150 | 玩家按诊断报 bug，拿到的是过期数字 | `spec_options` `修复: 诊断里的「当前值」必须是实时读，且标注采样时间` |
| 12 | `Core.timers = {}` 死字段 | 从未被读写 | 无害噪音 | 无（删除即可；`grep -n "Core.timers" 应为空`） |
| 13 | **进游戏后界面完全没有任何显示**（真机实测暴露）：状态条字体串用 `CreateFontString(nil,"OVERLAY")` 创建（无字体）后调 `SetText` → 客户端抛 `FontString:SetText(): Font not set` → 该错误位于 `Setup()` 内 → **状态条中断、设置面板的注册代码根本没执行** | 客户端日志 `General.log`：`Lua Error: FontString:SetText(): Font not set — AutoSpellQueue_Options.lua:700 ← :681 ← :1497 ← :1517` | 玩家看不到任何界面，且没有任何提示（最糟的失败形态） | `spec_options` `修复: 状态条字体串必须自带字体…`；**并把测试桩加严**（见下） |

| 14 | **展开高级设置后「乱版」**（玩家截图暴露）：①带提示的开关行里，标签在 46px 高的行内**垂直居中**、提示固定放在 -16 → 两行字重叠，提示开头被标签盖住（看起来像中英文混排）；②内容比设置画布高时**画布不会替你滚动**，`SetContentHeight` 还把宿主一起撑大 → 下半部分画到窗口外，盖住暴雪自己的「关闭」按钮 | 真机截图：`启用自动调整pellQueueWindow 还原成你原本的值。`（标签压住提示「关闭后会把 **S**pellQueueWindow…」）；展开高级后「悬浮状态条 / 其它 / 立即重新计算」等行落在窗口外 | 设置页基本不可用 | `spec_options` `修复: 带提示的行，标签必须顶对齐…`、`修复: 内容变高时必须靠滚动…`（断言几何：标签锚点必须 TOPLEFT 且提示 y 至少低 18px；内容变高时宿主高度不得变） |
| 15 | **设置页整页空白**（玩家报告 → 用 Cua Driver 在真机上复现并直接从客户端内部取几何数据定位）：`BuildUI` 把内容放进 `ScrollFrame` 后**只设了高度、没设宽度**；客户端不会从锚点推导滚动子框的宽度，而所有控件都以「左+右」双锚点挂在子框上 → 宽度 0 → 全部渲染成空 | 客户端内执行 `/run` 实测输出：`PANEL 665 604 2 true` / `SCROLL 639 602` / **`CHILD 0 440`**；表现为「点进选项里面完全空白」 | 设置页完全不可用，且**没有任何报错**（最坏的失败形态） | `spec_options` `修复: 滚动子框必须显式设宽…`（断言子框宽度 > 0，并要求 `OnSizeChanged` 后仍为正） |
| 16 | **中文长句被截断成「…」+ 卡片内两行文字重叠**：①`SetWordWrap(true)` 只按空格断行，中文没有空格 → 客户端把字体串**截断加省略号**，必须同时开 `SetNonSpaceWrap`；②靠左右双锚点取宽的字体串同样不回流（与第 15 条同源）；③在**设宽之前**读 `GetStringHeight()` → 量到的是一行高度 → 行距算少 → 下一行压上来 | 真机截图：副标题结尾 `——**不…`（还暴露出语言表里误写的 Markdown 星号）、脚注 `…/asq status…`；卡片 `sampledLine(-128)` 与 `hintLine(-146)` 叠字 | 主要说明文字读不全、文字重叠 | `spec_options` `修复: 会换行的字体串必须有显式宽度…`、`修复: 卡片里的多行文字必须留有整行间距`（第十四/十六条相关用例随后随「极简面板」改版移除，规则本身留在桩与本文档里） |
| 17 | **极简改版时把悬停提示挂在了字体串上**：`FontString` 在客户端**收不到鼠标事件**（没有 `HookScript`），调用直接抛错 → `BuildUI` 中断 → 面板只建到状态行为止（开关行、按钮全没了） | 桩如实报出 `attempt to call a nil value (method 'HookScript')`；真机上会被 `EnsureBuilt` 守卫报成「界面组件 panel-content 初始化失败」 | 面板残缺（只剩标题与状态行），且此前没有任何守卫能报出来 | `spec_options` `Boot…` 断言 `_G.ASQ_BUILD_ERROR == nil`；提示改为挂在鼠标可交互的帧上 |

> 第 13 条的教训（测试无法证明客户端行为）：`wow_stub.CreateFontString` 之前**不校验字体前提**，
> 所以「创建字体串 → SetText」这条客户端硬约束在测试里畅通无阻。桩现在按客户端建模：
> `CreateFontString` 的 `inherits` 必须是已知字体对象（否则报 `Unknown font object`），
> 而**没有字体就调 `SetText` 会抛与客户端完全相同的那句话**。
> 实测：把那一行还原 → 10 条用例 FAIL；恢复 → 全绿。
>
> 同时给 `Setup()` 加了隔离：每个部件在 `pcall` 里初始化、失败会**在聊天框报出部件名与原因**，
> 且**先注册设置面板再建状态条**——一个部件挂掉不再可能导致「什么都没有」。
> （诚实声明：`TryStep` 的隔离逻辑本身没有注入式失败用例，属防御性代码。）

> 第 14 条的教训（第二类盲区：**几何**）：桩能记录 `SetPoint` 锚点、能查 `IsShown`，
> 但**不会自己发现"两个控件画在同一处"**——「是否重叠」「是否溢出」必须由断言显式表达。
> 补的两条用例正是如此，实测：还原成截图那一版 → 恰好这 2 条 FAIL。

> 第 15/16 条的教训（第三类盲区：**尺寸来源**）：客户端里「宽度来自锚点」和「宽度来自 SetWidth」
> 是两回事——`ScrollFrame` 的子框只认后者，而字体串在双锚点下也不会回流。这两点桩都不会自动发现。
> 因此桩现在按客户端建模：`GetNumPoints()` 记录锚点数量（用于断言"不许靠双锚点取宽"）、
> `SetWordWrap/SetNonSpaceWrap` 记录换行标志、**`GetStringHeight()`/`GetHeight()` 按当前宽度计算折行后的真实行数**
> （这条最关键：它让「先测量、后设宽」这种时序错误第一次变得可测）。
> 实测：分别还原三处 → 对应用例各自 FAIL；恢复 → 全绿。
>
> 定位手段也值得记下来：整页空白时**不要猜**。用 Cua Driver 在真机上复现，然后在游戏聊天里执行
> `/run print(...)` 直接打印 `GetWidth()/GetHeight()/IsShown()`，一次就拿到了 `CHILD 0 440` 这个决定性数字。
> 事后这套流程也被写进了验证清单（见 `HANDOFF.md`）。

> 根因提醒：这些缺陷几乎全是「代码与文档/注释说的不一致」而不是崩溃。写完一句承诺，就配一条用例。
>
> 另有一类「旧代码把 `pcall` 没抛错当成写成功」的行为，由 `spec_cvar` / `spec_core` 的多条 `P1:` 用例永久锁定
> （含「API 谎报 true 但值没变」「客户端读不回 + API 返回 nil」等变体）——**不要再用「API 没报错就算成功」的写法**。

### 覆盖盲区的教训

第 6 条的成因值得单独记住：`spec_options` 的状态用例喂的是**已解析好的**状态表
（每行自带 `state = "…"`），于是 `ResolveState` 的**组合逻辑**（`enabled × state`）从未被覆盖。

> 对「把一种状态映射成另一种状态」的函数，测试必须喂**原始组合**，不能喂别人替它算好的结果。

### 怎么证明这些用例真的能抓虫

**做法**：把 4 个源文件 `git checkout` 回退到修复前、只保留新测试，跑一次；再恢复。

```
回退后：FAIL SameValue 按四舍五入比较… / FAIL 修复: 归还被推迟或失败时… /
        FAIL 暖机… / FAIL 修复: 状态条几何返回 NaN… / FAIL 修复: 上限低于 50ms… /
        FAIL 修复: 诊断里的「当前值」…        断言 1223 条；通过 126，失败 6
恢复后：断言 1243 条；通过 132，失败 0，结果: PASS
```

## 2a. 深度审查（2026-09-28）结论：全部已修，无遗留

两轮审查共确认 12 个缺陷，**现已全部修复并由用例钉住**。审查中确认**站得住**、
改动时不要破坏的部分：

- `CVar:Write` 对真实客户端各种返回形状（`false` / `nil` / 谎报 `true`）都稳；
- 所有权生命周期：接管 → 外部改值 → 关闭（只释放不覆盖）；接管 → 写失败 → 关闭
  （`lastApplied=nil` 走 release，此刻值本就等于 baseline，不写才是对的）；
- 登出归还失败 → 所有权持久化 → 下次登录仍持有正确 baseline；
- 脏输入（NaN/inf/字符串/颠倒上下限/坏 ownership）在 `Sanitize` 与 `Formula` 每个入口都有防护；
- 纯 Lua 位运算的城市标记判定（`HasFlag` 的整除取模）在 `0x100000` / `0x200000` / 组合值上算得正确。

## 3. 打包可复现性（踩过的坑）

发布产物的指纹规则：**用 zip 内每个条目的内容 sha256**，不要只用 zip 自身的哈希。
`tools/package.ps1` 会打印逐条目清单，并做三道产物级校验：

| 校验 | 抓什么 |
|---|---|
| 逐条墙钟 == 约定常量（`2000-01-01 00:00:00`） | 时间戳退回「打包那一刻」，或常量被时区换算挪位 |
| 脚本内二次打包、比较 zip 哈希 | 隐藏的非确定性（额外 extra field、条目顺序、压缩状态） |
| zip 条目内容 == 工作区文件 | 打包时读错文件 / 内容漂移 |

失败时**删除产物**并 exit 1（`dist/` 里躺着一个像发布候选的坏包比没有产物危险）。

**坑的记录**：`ZipArchive.CreateEntry()` 默认写入「打包那一刻」的时间，导致同一份内容先后出现过
**5 个不同的 zip 哈希**。修法是固定条目时间戳；`-Timestamp` 现在必须是不带偏移的墙钟，传 `+00:00` 直接 FAIL。

**时区语义**：DOS 时间字段存的是**墙钟**，赋值时给的时区偏移会被**丢弃**（三种不同 offset 的输入读回一致）。
原始字节为 `dosTime=0x0000`、`dosDate=0x2821`（= 2000-01-01），所有条目 extra field 长度为 0
（无 `0x5455` extended timestamp、无 `0x000A` NTFS）——**产物里不存在任何 UTC 时间戳**。

> 曾有个假象被当成结论：把 `Kind=Unspecified` 的时间值拿去做 `ToUniversalTime()`，在本机 UTC+8 下
> 渲染成 `1999-12-31T16:00:00Z`，于是以为「只有同一时区才字节一致」。**那是渲染错误**，zip 内墙钟没有偏差。
> 结论：常量是墙钟，文档/断言不要写成 `…Z`；换打包器可能引入 extra field
> （Info-ZIP / 7-Zip / BigWigs packager 常写 `0x5455`），所以**跨机器、跨工具核对一律用逐条目内容 sha256**。

## 4. 测试写法约定

- 断言辅助：`T.ok / T.eq / T.ne / T.near / T.isNil / T.notNil / T.contains / T.raises / T.deepeq / T.inRange`，
  每条都带 `file:line` 与期望/实得值。
- `T.beforeEach(fn)`：每个用例前的重置（`spec_core` 用它重建假客户端与存档）。
- `T.xfail(name, fn, note)`：**只**用于记录「已上报、尚未修复」的真实缺陷。不阻塞门禁，
  但会以 `KNOWN` 高亮；缺陷修好后用例会变 `XPASS` 并提示改回 `T.test`——**请立刻改**，让修复被钉死。
- `tests/spec_*.lua` 由 `tools/run-tests.mjs` 自动发现，新增无需注册；
  反之 `tools/verify.ps1` 会检查必备 spec 是否存在——删掉 `spec_cvar.lua` 时
  `run-tests.mjs` 仍会「通过」（只是少跑一大截断言），结构检查就是为了堵住这种静默失效。

## 5. UI / 本地化覆盖

`run-tests.mjs` 按 `.toc` 顺序把六个运行期文件加载进同一个 `ns`（Locale 最先、Options 最后）；
核心用例仍自己验证「没有 `ns.L` 也要能跑」（临时把 `ns.L` 置 nil），两件事不冲突。
UI 用例直接调用**真实的** `OnClick` / `OnUpdate` / `OnShow` / `OnDragStop`，没有重写面板逻辑。

| 不变量 | 锁定用例 |
|---|---|
| 面板只构建一次，之后只刷新、不重建 | `spec_options` `UI 只构建一次…` |
| **面板极简**：两个开关 + 一行状态 + 一个动作按钮；任何一行可见文字 ≤ 60 字节、可见文字 ≤ 6 行；副标题/脚注不得出现在页面上 | `spec_options` `面板必须极简…`（守门用例） |
| 长解释移到悬停提示后**内容不得丢失**（说明、算式、诊断入口都还在提示里） | `spec_options` `状态行：失败原因与算式都在悬停提示里…` |
| 提示必须挂在**帧**上：字体串在客户端收不到鼠标事件（真机上抛过 `HookScript` nil，整页构建被打断） | `spec_options` `Boot…`（断言 `_G.ASQ_BUILD_ERROR == nil`）+ `状态行：…悬停提示…` |
| 状态行几何：单行高度、落在标题行下方、显示开关落在它下方 | `spec_options` `极简面板的布局…` |
| **玩家可见设置恰好两个**（enabled / showStatus），面板里只有两个开关，v1 旋钮一个不剩 | `spec_options` `面板必须极简…`（守门用例）、`开关：只有 enabled 与 showStatus…` |
| v1 的旋钮不会靠任何代码路径复活（SetConfig 拒绝退休键，旧存档被 Sanitize 清掉） | `spec_core` `SetConfig…`、`Sanitize: 错类型与越界…`；`spec_options` `面板不再暴露任何可调参数…` |
| 配置白名单：新增任何配置键都必须经过审阅 | `spec_core` `结构: 配置白名单…` |
| 状态卡六种状态文案；失败优先于 disabled；错误提示带本地化原因 | `spec_options` 三条 `状态卡：…` |
| **写入失败不许显示数字**：状态条在 error/unavailable/disabled 只显示状态名；卡片显示客户端真实值或 `VALUE_UNAVAILABLE`，绝不用 target 冒充 | `spec_options` `状态条：error / unavailable / disabled…`、`P1 集成：真实写入被拒后…` |
| 状态条拖动落点写入 `statusBarPos`（`noRefresh`）并夹紧在屏幕内 | `spec_options` `状态条拖动…` |
| 解锁复位位置、必要时重新显示状态条 | `spec_options` 两条 `状态条位置：…` |
| 五条斜杠命令（含 `/asq base` 逃生口）+ 未知参数给帮助 | `spec_options` 六条 `斜杠…` |
| 面板不可见时不刷新；重新显示立刻刷新 | `spec_options` `面板不可见时不刷新…` |
| 三套语言键集完全相同、未列语言回退 enUS、缺键才回退键名 | `spec_locale` 前五条 |
| UI/Core 用到的每个键（含 `STATE_*` 动态拼接与 `REASON_KEY` 的值）都有 enUS 文本 | `spec_locale` `UI/Core 源码里出现的每个本地化键…`、`动态拼接的键族…` |
| 需要 `:format()` 的键必须带占位符 | `spec_locale` `格式化键必须带 % 占位符…` |

### 算法（取代了原来的五个设置项）| 不变量 | 锁定用例 |
|---|---|
| 无样本时余量/迟滞落在安全下限，不返回 NaN | `spec_latency` 第 1 条 |
| 未知延迟（0）不进窗口，不会把均值拉低 | `spec_latency` 第 2 条 |
| 平滑不对称：变差立刻响应、变好慢慢放手 | `spec_latency` 第 3 条 |
| 抖动↑ → 余量与写入阈值↑（原「安全余量」「迟滞」两个设置的功能） | `spec_latency` 第 4 条 |
| 单个 600ms 尖刺不得把余量顶满（用平均绝对偏差，不是极差） | `spec_latency` 第 5 条 |
| 余量/阈值永远在钳制区间内 | `spec_latency` 第 6 条 |
| 采样窗口有上限；Reset 清空累计与平滑值 | `spec_latency` 第 7 条 |
| 运行时确实把快照延迟喂给算法，并用算法给出的余量决策 | `spec_core` `采样策略…`、`P1: 战斗中不写…`（断言写入值 == 实时目标） |

### 采样策略（不再固定节奏轮询）

| 不变量 | 锁定用例 |
|---|---|
| 学习期用密集间隔（15s），读数稳定后**结束学习期**并换成心跳（300s） | `spec_core` `采样策略: 学习期密集采样，稳定后停止轮询…` |
| 心跳发现"没漂移"时**不写、不重新决策** | 同上（`Core.heartbeatSteady`、写入数 0） |
| 漂移超过死区（25ms）→ 重新进入学习期并跟着改值 | 同上 |
| 进副本 / 团本（`PLAYER_ENTERING_WORLD`）与换区（`ZONE_CHANGED_NEW_AREA`）都重新采样一次 | `spec_core` `采样策略: 进入副本 / 团本会重新采样一次` |
| 重新学习必须**真的重新攒样本**（不能靠旧收敛状态一秒结束） | `spec_latency` `Restart 保留估计值…`；`spec_core` 副本用例断言 `settling` 持续到 `Advance(41)` 之后 |
| 登录时先用**记住的延迟**给出正确值，不等 `GetNetStats()` | `spec_core` `采样策略: 登录时先用记住的延迟…` |
| 记忆值与实测差得多时**直接采用实测**，不慢慢滑几分钟；接近时仍平滑 | `spec_latency` `记忆值与实测差太远时立刻改用实测…` |
| 写失败走退避（60s×3 → 心跳），不是永远 15 秒 | `spec_core` `修复: 归还被推迟或失败时…`；`Core.DesiredInterval()` |
| 有待办（战斗中推迟的写入/归还）时保持 15 秒重试 | 同上；`spec_core` `P1: 启用中在战斗里禁用…` |
| 完全无事可做（关闭且已归还）时**定时器不存在** | `spec_core` 多条用例断言 `Core.ticker == nil` |

### 没覆盖什么（诚实声明）

- **独立回退窗口**（客户端没有 `Settings` API 时的路径）没跑起来：初始化只发生一次，同一份 Lua state 只能选一条路径。
  测的是 12.x 主路径，另外验证了「无法打开面板时 `Options.Open()` 返回 false 且给出提示，不静默失败」。
- 假的 `Settings.RegisterCanvasLayoutCategory` 不会真的把面板挂到设置窗口下；用例自己用 `Show()/Hide()` 模拟可见性门控。
- **算法在真实网络下的表现**没测：`spec_latency` 验的是数学与边界，真机抖动分布只能靠实际游玩观察（`/asq status` 会打印当前余量与抖动）。
- 所有 UI 用例跑在 `wow_stub.lua` 上：验证的是**逻辑**，不是真实客户端的渲染与锚点。屏幕固定 1920×1080。
- 两条会影响整份测试语义的建模前提（改动会波及所有用例）：**新建 frame 默认「已显示」**（Options 的 poller 依赖这个语义）；
  **`frame.name` 是普通字段**（Settings API 读它当标题），按名字查控件要用创建名 `__name`。

## 6. 已确认的外部契约（不用改代码，但别改错）

| 项 | 结论 | 来源 |
|---|---|---|
| `C_CVar.GetCVarInfo(name)` 返回顺序 | `value, defaultValue, isStoredServerAccount, isStoredServerCharacter, isLockedFromUser, isSecure, isReadOnly`——**七个返回值，与 `wow_stub.lua` 的建模一致**（`isSecure` = 战斗中 `SetCVar` 受限、可能触发 `ADDON_ACTION_BLOCKED`；`isReadOnly` = 不可改） | Warcraft Wiki `API:C_CVar.GetCVarInfo`，页面更新 2026-09-06，挂载 standard 12.1.5 (69848)，oldid=6863082 |
| `SpellQueueWindow` 是否仍存在 | 当前全量 CVar 清单仍列出（默认 400，Account scope）；12.0.0 / 12.0.1 / 12.1.0 的移除列表都不含它。旧专题页标「removed」且更新于 2022 年，与较新资料冲突，判为过期 | Warcraft Wiki `Console variables` / 各补丁 `API changes` 页 |
| TOC `Interface` | 多版本逗号列表受支持；`120100` 对应 12.1 standard | Warcraft Wiki `TOC format` |
