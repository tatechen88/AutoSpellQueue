# 回归清单（tests/ 锁定的是什么）

> 这些用例存在的意义不是「覆盖率」，而是**把已经踩过的坑钉死**。
> 任何一条变红都说明核心不变量被破坏，不是测试写错了。
> 最后更新：2026-09-28

## 怎么跑

```powershell
node tools/check-syntax.mjs      # luaparse(5.1) + 5.1/5.3 双兼容 lint
node tools/run-tests.mjs         # fengari(5.3) 执行 tests/spec_*.lua
node tools/run-tests.mjs spec_core   # 只跑某个 spec（调试用）
pwsh tools/verify.ps1            # 上面两步 + 结构/版本一致性
pwsh tools/verify.ps1 -Package   # 再加 dist/AutoSpellQueue-<版本>.zip
```

测试环境：`tests/wow_stub.lua` 伪造客户端（CreateFrame / C_Timer / C_CVar /
C_Map / GetNetStats / InCombatLockdown / C_SpecializationInfo / GameTooltip /
SlashCmdList / Settings API …）。`tools/run-tests.mjs` 用 varargs 把
`(ADDON_NAME, ns)` 按 `.toc` 顺序传给全部五个运行期文件（Locale 最前、
Options 最后），所以 UI 用例跑在与客户端一致的命名空间里；核心用例自己做
「没有 ns.L 也要能跑」的验证。退出码 0 = 绿，1 = 有失败用例。

`wow_stub.lua` 的两个关键建模（改动它们会改变整份测试的语义）：

- **新建 frame 是「已显示」的**（客户端行为；这也是 Options 的刷新 poller 不调
  `Show()` 也能收到 OnUpdate 的原因），`Stub.FireUpdate(elapsed)` 只对
  「自己与所有祖先都 shown」的 frame 调用 OnUpdate，用来验证「面板不可见时
  不刷新」。
- `frame.name` 是普通字段（Settings API 会读它当面板标题），所以按名字查控件
  要用 `CreateFrame` 时的名字，`Stub.FindFrame` 查的是 `__name`。

发布产物的指纹怎么引：**用 zip 内每个条目的内容 sha256，不要只用 zip 自身的
哈希**。`package.ps1` 会打印这份逐条目清单，并在打包后把「zip 内条目」与
「工作区文件」逐字节比对（不一致就 FAIL）。zip 自身的哈希也已可复现——条目
墙钟被固定为 `2000-01-01T00:00:00`（`-Timestamp` 可覆盖），因为
`ZipArchive.CreateEntry()` 默认写入「打包那一刻」的时间，会让同样的内容每次
打包都得到不同的 zip 哈希（实测踩过：同一份内容先后出现过 5 个不同的 zip
哈希）。

`package.ps1` 现在有三道产物级校验，全部实测过失败路径：

| 校验 | 抓什么 | 失败路径实测 |
|---|---|---|
| 逐条墙钟 == 约定常量 | 时间戳退回「打包那一刻」，或常量被时区换算挪位 | 把赋值改回 `[DateTimeOffset]::Now` → 6 条 FAIL、exit 1、并删除产物 |
| 同内容再打一份、比较 zip 哈希 | 隐藏的非确定性（额外 extra field、条目顺序、压缩状态） | 只让第二次打包换一个墙钟 → FAIL「产物不可复现」、exit 1、并删除产物 |
| zip 条目内容 == 工作区文件 | 打包时读错文件 / 内容漂移 | 与上同理，属于同一条比对 |
| （输入校验）`-Timestamp` 必须是不带偏移的墙钟 | 有人以为偏移有意义 | 传 `…+00:00` 或 `not-a-date` → FAIL、exit 1 |

**校验没过就不留产物**：`dist/` 里出现一个「看起来像发布候选」的 zip 比没有
产物危险得多，所以失败时脚本会把刚生成的 zip 删掉（实测：探针跑完后
`dist/AutoSpellQueue-2.0.0.zip` 不存在）。

> **时区语义（ui-dev 复核时提出，实测澄清）**：zip 的 DOS 时间字段存的是
> **墙钟**，赋值时给的时区偏移会被**丢弃**。实测（`tools/package.ps1`
> 写 `2000-01-01T00:00:00+00:00` / `-05:00` / 本地 `DateTime` 三种输入）
> 读回来都是同一个墙钟 `2000-01-01 00:00:00`；直接读中央目录原始字节为
> `dosTime=0x0000`、`dosDate=0x2821`（= 2000-01-01），且所有条目的 extra field
> 长度为 0（既无 `0x5455` extended timestamp，也无 `0x000A` NTFS），
> 即这份产物里**不存在任何 UTC 时间戳**。
>
> ⚠️ 记录一个已排除的假象：曾有人把 `Kind=Unspecified` 的时间值拿去做
> `ToUniversalTime()`，在本机 UTC+8 下渲染成 `1999-12-31T16:00:00Z`，并据此
> 以为「只有同一时区才字节一致」——**那是渲染错误**，zip 内墙钟并无偏差。
> 结论与做法：
> 1. 这个常量是**墙钟**，不是某个 UTC 瞬间——文档/断言里都不要写成
>    `2000-01-01T00:00:00Z`；`package.ps1` 会直接**拒绝**带偏移的 `-Timestamp`。
> 2. 正因为存进去的是无时区的墙钟，同样的内容在任何时区的机器上写出的是**同样的
>    字节**（本机跨 6 秒连打两次一致、同一轮内自动双打一致；跨时区一致由「偏移
>    被丢弃」推得，没有第二台机器可实测）。
> 3. 边界：换成别的打包器可能引入 extra field（Info-ZIP / 7-Zip / BigWigs
>    packager 常写 `0x5455`），那时「字节一致」不再只取决于墙钟。所以
>    **跨机器、跨工具核对一律用逐条目内容 sha256**——它与时区、压缩等级、
>    打包工具都无关；zip 自身哈希只作同一脚本产出的快速校验。

## P1 不变量（每次改动都必须保持）

| # | 不变量 | 锁定用例 |
|---|---|---|
| 1 | `CVar:Write` 只有在「API 未拒绝」**且**「读回值一致」时才算成功；`pcall` 不抛错 ≠ 成功 | `spec_cvar`: 4 条 `P1: ...`；`spec_core`: `P1: API 返回 false ...`、`P1: API 谎报 true ...` |
| 2 | 写入失败不得记为已应用（`lastApplied` 不写、`stats.applied` 不加、状态是 `error`） | `spec_core`: 两条 `P1: ... 绝不记为已应用` |
| 3 | 战斗中绝不写 CVar；脱战 `PLAYER_REGEN_ENABLED` 必须**重新决策**，不重放旧目标 | `spec_core`: `P1: 战斗中不写；脱战后按实时状态重新决策...`、`P1: 战斗中禁用再启用...`、`P1: 启用中在战斗里禁用...` |
| 4 | 只归还仍然属于我们的值；外部改过就只释放所有权、不覆盖 | `spec_core`: `P1: 禁用时若值被外部改过...`、`P1: RestoreOwnership 遇到外部改动...` |
| 5 | 登出归还 baseline；归还失败则保留 ownership，下次登录仍能归还 | `spec_core`: `登出归还 baseline...`、`P1: 登出归还失败时保留所有权...` |
| 6 | 未来 `schemaVersion` 不降级、不丢字段 | `spec_core`: `Migrate: schemaVersion 更高时不降级...` |
| 7 | 配置 `Sanitize` 面对任何脏输入都不崩、不把坏值带进运行时 | `spec_core`: 4 条 `Sanitize: ...`、`GetConfig 加载脏存档时先 Sanitize` |
| 8 | `Tate_ASQDB` 老存档一次性导入并清空 | `spec_core`: `ImportLegacy: ...` |
| 9 | `AutoSpellQueue_Formula.lua` 是纯模块，不碰任何游戏 API | `spec_formula`: `源码扫描...`、`运行期：把所有 WoW API 换成陷阱...` |
| 10 | 除 `AutoSpellQueue_CVar.lua` 外没有文件直接读写 `SpellQueueWindow` / `C_CVar` | `spec_core`: `结构: 除 CVar.lua 外...` |

## 2026-09-28 修复并被用例钉死的缺陷

门禁建成当天，测试在核心文件里抓到 5 个真实缺陷（当时由 Lead 修复，本目录
对应用例已从 `T.xfail` 转成硬 `T.test`）：

| # | 缺陷 | 最小复现（修复前） | 现象 | 现在的用例 |
|---|---|---|---|---|
| 1 | `GetStatus()` 的 `role/base/latency` 恒为 nil：取值来源 `Core.lastSnapshot` 是原始游戏快照，不含这三个字段 | `Core.Refresh("x")` 后 `Core.GetStatus().role == nil` | 设置页「计算式」一栏（LABEL_ROLE/BASE/LATENCY）拿不到数据 | `spec_core`: `GetStatus 的 role/base/latency 必须来自最近一次决策` |
| 2 | `Sanitize()` 对「非表且非 nil」的 `ownership` 直接索引 `own.active` | `ns.Core.Sanitize({ ownership = 42 })` | `attempt to index a number value`，损坏存档会让插件在 `ADDON_LOADED` 报错；字符串因元表侥幸不报错 | `spec_core`: `Sanitize: ownership 是数字/布尔/字符串时必须丢弃而不是抛错` |
| 3 | `CVar:Info()` 的 `GetCVarInfo` 回退分支把字符串写进 `info.value`（主分支有 `tonumber`） | `getCVarInfo` 抛错、`getCVar` 返回 `"275"` 时 `type(CVar:Read()) == "string"` | 违反 `Read() -> number\|nil`；`("%d"):format(current)` 在 Lua 5.3 会报错 | `spec_cvar`: `Info()/Read() 的回退路径必须返回 number（文档契约）` |
| 4 | `Execute()` 只在 `kind == "none"` 时记 `externalChange`，重新夺回管理时诊断丢失 | 写 350 → 外部改 333 → `Refresh()` 后 `externalChange == false` | UI 无法如实告知玩家「值被别人改过」 | `spec_core`: `外部改值后重新夺回管理时 externalChange 诊断不应丢失` |
| 5 | `Formula.Clamp(NaN, lo, hi)` 返回 NaN，与函数注释「never returns NaN」矛盾 | `Formula.Clamp(0/0, 50, 400) == NaN` | Options 用 `Clamp` 夹用户输入时会得到 NaN | `spec_formula`: `Clamp(NaN) 的结果必须是有限数字...` |

另有一类"旧代码假报成功"的行为（`pcall` 成功但 `SetCVar` 返回 `false`/`nil`
时 UI 显示已应用）由 `spec_cvar` / `spec_core` 的多条 `P1:` 用例永久锁定；
`spec_cvar` 里还包含「API 谎报 true 但值没变」「客户端读不回 + API 返回 nil」
等变体，避免以后再用"API 没报错就算成功"的写法。

## 用法约定

- 断言辅助：`T.ok / T.eq / T.ne / T.near / T.isNil / T.notNil / T.contains /
  T.raises / T.deepeq / T.inRange`，每条都带 `file:line` 与期望/实得值。
- `T.beforeEach(fn)`：每个用例前的重置（spec_core 用它重建假客户端与存档）。
- `T.xfail(name, fn, note)`：**只**用于记录「已上报、尚未修复」的真实缺陷。
  它不阻塞门禁，但会在输出里以 `KNOWN` 高亮；一旦该缺陷被修复，用例会变成
  `XPASS` 并提示你把 `T.xfail` 改回 `T.test`——请立刻改，让修复被钉死。
- `tests/spec_*.lua` 由 `tools/run-tests.mjs` 自动发现；新增 spec 文件不需要
  注册。反之，`tools/verify.ps1` 会检查五个必备 spec 是否存在——删掉
  `spec_cvar.lua` 时 `run-tests.mjs` 仍会"通过"（只是少跑 136 条断言），
  结构检查就是为了堵住这种静默失效。

## 已确认的外部契约（不需要改代码，但别改错）

| 项 | 结论 | 来源 |
|---|---|---|
| `C_CVar.GetCVarInfo(name)` 返回顺序 | `value, defaultValue, isStoredServerAccount, isStoredServerCharacter, isLockedFromUser, isSecure, isReadOnly` —— **七个返回值，与 `tests/wow_stub.lua` 的建模一致**（`isSecure` = 战斗中 `SetCVar` 受限、可能触发 `ADDON_ACTION_BLOCKED`；`isReadOnly` = 不可改） | Warcraft Wiki `API:C_CVar.GetCVarInfo`，页面更新 2026-09-06，挂载 standard 12.1.5 (69848)，oldid=6863082 |

## UI / 本地化覆盖（tests/spec_locale.lua, tests/spec_options.lua）

`run-tests.mjs` 按 `.toc` 的顺序把五个文件都加载进同一个 `ns`（Locale 在最前、
Options 在最后），核心用例仍然自己做「没有 ns.L 也要能跑」的验证（把 `ns.L`
临时置 nil），所以两件事不冲突。UI 用例直接调用**真实的** OnClick / OnUpdate /
OnShow / OnDragStop 处理器，没有重写任何面板逻辑。

| 不变量 | 锁定用例 |
|---|---|
| 面板只构建一次，之后只刷新、不重建 | `spec_options`: `UI 只构建一次...` |
| 总开关/步进/循环控件真的写 Core 配置（并被 Core 夹紧） | `spec_options`: `总开关...`、`高级开关...`、`步进控件...`、`循环控件...` |
| 高级折叠写 `showAdvanced` 并真的显示/隐藏 | `spec_options`: `高级折叠...` |
| 重置按钮两段确认、4 秒后经 `C_Timer` 自动解除 | `spec_options`: `重置按钮...` |
| 状态卡六种状态文案；失败优先于 disabled；错误提示带本地化原因 | `spec_options`: 三条 `状态卡：...` |
| **写入失败不许显示数字**：状态条在 error/unavailable/disabled 只显示状态名；卡片显示客户端真实值或 `VALUE_UNAVAILABLE`，绝不用 target 冒充 | `spec_options`: `状态条：error / unavailable / disabled...`、`P1 集成：真实写入被拒后...` |
| 状态条拖动落点写入 `statusBarPos`（`noRefresh`）并夹紧在屏幕内 | `spec_options`: `状态条拖动...` |
| 解锁复位位置、必要时重新显示状态条 | `spec_options`: 两条 `状态条位置：...` |
| 四条斜杠命令 open/status/reset/unlock + 未知参数给 6 行帮助 | `spec_options`: 五条 `斜杠...` |
| 面板不可见时不刷新；重新显示立刻刷新 | `spec_options`: `面板不可见时不刷新...` |
| 三套语言键集完全相同、未列语言回退 enUS、缺键才回退键名 | `spec_locale`: 前五条 |
| UI/Core 用到的每个键（含 `STATE_*` 动态拼接与 `REASON_KEY` 的值）都有 enUS 文本 | `spec_locale`: `UI/Core 源码里出现的每个本地化键...`、`动态拼接的键族...` |
| 需要 `:format()` 的键必须带占位符 | `spec_locale`: `格式化键必须带 % 占位符...` |

### 这套 UI 用例没有覆盖什么（诚实声明）

- **独立回退窗口**（客户端没有 `Settings` API 时用的 `AutoSpellQueueOptionsFrame`
  + ScrollFrame）没有跑起来：初始化只发生一次，同一份 Lua state 里只能选一条
  路径。测的是 12.x 的主路径（`Settings.RegisterCanvasLayoutCategory` /
  `RegisterAddOnCategory` / `OpenToCategory`），并额外验证了「无法打开面板时
  `Options.Open()` 返回 false 且给出提示，不静默失败」。
- 假的 `Settings.RegisterCanvasLayoutCategory` **不会真的把面板重新挂到设置
  窗口下面**；用例自己用 `panel:Show()/Hide()` 模拟客户端对可见性的门控。
- 字体/LibSharedMedia 只覆盖到「没有 LibSharedMedia 时的四个内置字体」这条
  路径（stub 不提供 LibStub）。
- 所有 UI 用例跑在 `wow_stub.lua` 上：它验证的是**逻辑**，不是真实客户端的
  渲染与锚点结果。屏幕固定 1920×1080（`Stub.screenWidth/Height`）。
