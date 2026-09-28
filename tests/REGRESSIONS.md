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

此外，「旧代码把 `pcall` 没抛错当成写成功」这一类行为，由 `spec_cvar` / `spec_core` 的多条 `P1:` 用例永久锁定，
其中包含「API 谎报 true 但值没变」「客户端读不回 + API 返回 nil」等变体——**不要再用「API 没报错就算成功」的写法**。

> 根因提醒：这 5 个缺陷全是「代码与文档/注释说的不一致」而不是崩溃。写完一句承诺，就配一条用例。

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

`run-tests.mjs` 按 `.toc` 顺序把五个运行期文件加载进同一个 `ns`（Locale 最先、Options 最后）；
核心用例仍自己验证「没有 `ns.L` 也要能跑」（临时把 `ns.L` 置 nil），两件事不冲突。
UI 用例直接调用**真实的** `OnClick` / `OnUpdate` / `OnShow` / `OnDragStop`，没有重写面板逻辑。

| 不变量 | 锁定用例 |
|---|---|
| 面板只构建一次，之后只刷新、不重建 | `spec_options` `UI 只构建一次…` |
| 总开关 / 步进 / 循环控件真的写 Core 配置（并被 Core 夹紧） | `spec_options` `总开关…`、`高级开关…`、`步进控件…`、`循环控件…` |
| 高级折叠写 `showAdvanced` 并真的显示 / 隐藏 | `spec_options` `高级折叠…` |
| 重置按钮两段确认、4 秒后经 `C_Timer` 自动解除 | `spec_options` `重置按钮…` |
| 状态卡六种状态文案；失败优先于 disabled；错误提示带本地化原因 | `spec_options` 三条 `状态卡：…` |
| **写入失败不许显示数字**：状态条在 error/unavailable/disabled 只显示状态名；卡片显示客户端真实值或 `VALUE_UNAVAILABLE`，绝不用 target 冒充 | `spec_options` `状态条：error / unavailable / disabled…`、`P1 集成：真实写入被拒后…` |
| 状态条拖动落点写入 `statusBarPos`（`noRefresh`）并夹紧在屏幕内 | `spec_options` `状态条拖动…` |
| 解锁复位位置、必要时重新显示状态条 | `spec_options` 两条 `状态条位置：…` |
| 四条斜杠命令 + 未知参数给 6 行帮助 | `spec_options` 五条 `斜杠…` |
| 面板不可见时不刷新；重新显示立刻刷新 | `spec_options` `面板不可见时不刷新…` |
| 三套语言键集完全相同、未列语言回退 enUS、缺键才回退键名 | `spec_locale` 前五条 |
| UI/Core 用到的每个键（含 `STATE_*` 动态拼接与 `REASON_KEY` 的值）都有 enUS 文本 | `spec_locale` `UI/Core 源码里出现的每个本地化键…`、`动态拼接的键族…` |
| 需要 `:format()` 的键必须带占位符 | `spec_locale` `格式化键必须带 % 占位符…` |

### 没覆盖什么（诚实声明）

- **独立回退窗口**（客户端没有 `Settings` API 时的路径）没跑起来：初始化只发生一次，同一份 Lua state 只能选一条路径。
  测的是 12.x 主路径，另外验证了「无法打开面板时 `Options.Open()` 返回 false 且给出提示，不静默失败」。
- 假的 `Settings.RegisterCanvasLayoutCategory` 不会真的把面板挂到设置窗口下；用例自己用 `Show()/Hide()` 模拟可见性门控。
- 字体 / LibSharedMedia 只覆盖「没有 LibSharedMedia 时的四个内置字体」这条路径（stub 不提供 `LibStub`）。
- 所有 UI 用例跑在 `wow_stub.lua` 上：验证的是**逻辑**，不是真实客户端的渲染与锚点。屏幕固定 1920×1080。
- 两条会影响整份测试语义的建模前提（改动会波及所有用例）：**新建 frame 默认「已显示」**（Options 的 poller 依赖这个语义）；
  **`frame.name` 是普通字段**（Settings API 读它当标题），按名字查控件要用创建名 `__name`。

## 6. 已确认的外部契约（不用改代码，但别改错）

| 项 | 结论 | 来源 |
|---|---|---|
| `C_CVar.GetCVarInfo(name)` 返回顺序 | `value, defaultValue, isStoredServerAccount, isStoredServerCharacter, isLockedFromUser, isSecure, isReadOnly`——**七个返回值，与 `wow_stub.lua` 的建模一致**（`isSecure` = 战斗中 `SetCVar` 受限、可能触发 `ADDON_ACTION_BLOCKED`；`isReadOnly` = 不可改） | Warcraft Wiki `API:C_CVar.GetCVarInfo`，页面更新 2026-09-06，挂载 standard 12.1.5 (69848)，oldid=6863082 |
| `SpellQueueWindow` 是否仍存在 | 当前全量 CVar 清单仍列出（默认 400，Account scope）；12.0.0 / 12.0.1 / 12.1.0 的移除列表都不含它。旧专题页标「removed」且更新于 2022 年，与较新资料冲突，判为过期 | Warcraft Wiki `Console variables` / 各补丁 `API changes` 页 |
| TOC `Interface` | 多版本逗号列表受支持；`120100` 对应 12.1 standard | Warcraft Wiki `TOC format` |
