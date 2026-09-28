# HANDOFF

> 交接说明：给接手本仓库的下一个 agent 或新 session。最后更新 **2026-09-28**。

## 这是什么

**AutoSpellQueue** —— 魔兽世界正式服（12.x）插件，版本 **2.0.0**（原名 `Tate_ASQ` / Tate's AutoSpellQueue，v2.0.0 起更名）。
五个 `.lua` 加一个 `.toc`，属于游戏内加载的插件包，不是可独立运行的程序。

它只做一件事：把 `SpellQueueWindow`（0–400 ms）自动保持在适合当前专精与网络延迟的值，并在插件不工作时归还玩家原值。
不做自动施法、不做战斗自动化、无网络请求、无遥测。

## 当前状态

| 项 | 值 |
|---|---|
| 插件名 / 版本 | `AutoSpellQueue` / `2.0.0`（与 `.toc` 的 `## Version` 一致） |
| SavedVariables | `AutoSpellQueueDB`（`.toc` 同时声明 `Tate_ASQDB`；**注意**：旧存档只有在玩家把 `SavedVariables\Tate_ASQ.lua` 复制为 `AutoSpellQueue.lua` 后才会被客户端加载，详见下条） |
| Interface | 120000, 120001, 120005, 120007, 120100, 120105（12.0.0–12.1.5） |
| 本机 lua 解释器 | **无**。验证走 Node 工具链（`luaparse` = Lua 5.1 语法，`fengari` = Lua 5.3 运行） |
| 本地化 | **enUS / zhCN / zhTW 三套完整文案**（134 个键 × 3，由同一张源表生成，键集必然一致；其他客户端语言回退 enUS）；设置面板标题三语统一为 `AutoSpellQueue` |
| 发布状态 | **未发布**。CurseForge 项目尚未创建，规划见 [`docs/CURSEFORGE.md`](docs/CURSEFORGE.md) |
| 交付状态 | 6 个运行期文件（`.toc` + 5 个 `.lua`，含 Locale / Options）与 `tests/`、`tools/`（含 `verify.ps1` / `package.ps1`）均已落盘 |
| 门禁现状 | **通过**（2026-09-28 实测，见下「实测记录」） |

## 快速上手

| 事项 | 做法 |
|---|---|
| 本地安装 | 把 `AutoSpellQueue` 文件夹放进 `World of Warcraft\_retail_\Interface\AddOns\`，重启客户端。旧版升级**必须先删掉 `Tate_ASQ` 文件夹** |
| 验证 | 见下「如何验证」，必须贴出**实际输出** |
| 版本记录 | `CHANGELOG.md`（顶部 = 当前版本） |
| 接口契约 | `docs/ARCHITECTURE.md`——改接口必须先改它 |
| issues / specs | `docs/agents/issue-tracker.md`（本地 markdown tracker，放 `.scratch/<feature>/`） |

## 如何验证

```powershell
npm --prefix tools install     # 一次性：安装 luaparse / fengari
node tools/check-syntax.mjs    # luaparse(5.1) 解析仓库内全部 .lua
node tools/run-tests.mjs       # fengari(5.3) 执行 tests/run.lua
pwsh tools/verify.ps1          # 语法 → 单测 → 结构与版本一致性
pwsh tools/verify.ps1 -Package # 追加打包：dist/AutoSpellQueue-<version>.zip
```

门禁覆盖内容（详见 `docs/ARCHITECTURE.md` 第 6 节）：

- `tools/check-syntax.mjs`：仓库根目录与 `tests/` 下全部 `.lua`，失败打印文件名 + 行号，非 0 退出；
- `tools/run-tests.mjs`：以 `varargs` 方式加载 `AutoSpellQueue_Formula.lua` / `AutoSpellQueue_CVar.lua` / `AutoSpellQueue.lua`（不加载 Options / Locale），再执行 `tests/run.lua`；用例覆盖公式回退与 clamp、CVar 写入校验（**pcall 不抛错但 API 返回 false/nil 必须判失败**、读回不一致必须失败、只读/战斗拒绝）、核心决策全分支、战斗结束重新决策、登出归还、外部改值只释放、配置校验、未来 schema 不降级、旧存档导入；
- `tools/verify.ps1`：附加结构与版本一致性检查（`.toc` 版本 vs `CHANGELOG.md` / `README.md`、必要文件是否存在、是否残留旧文件名、发布包应含文件清单）；
- `tools/package.ps1`：zip 根目录恰好是 `AutoSpellQueue/`，只含 6 个运行期文件。

`pwsh tools/verify.ps1` 的全绿输出应当贴进本次改动的说明里——**断言不算证据**（见 `AGENTS.md`）。

### 实测记录（2026-09-28）

> ⚠️ 门禁脚本与测试用例在 2026-09-28 当天仍在并行改动，下面的数字是某个时刻的快照；**发布前必须以当次 `pwsh tools/verify.ps1` 的实际输出为准**，并把它贴进发布说明。若出现失败用例，先看 `tests/spec_*.lua` 的断言与核心契约是否一致，再判断是核心 bug 还是测试用例需要修正。

`pwsh tools/verify.ps1` 输出摘要（原样抄录关键行）：

```
结果: 10 个文件全部通过（语法 0 错，双兼容 lint 0 错）
  ok   check-syntax.mjs 通过
 断言 958 条；通过 95，失败 0，已知问题 0，意外通过 0
 结果: PASS
  ok   run-tests.mjs 通过
  ok   CHANGELOG.md 最新条目 (2.0.0) == .toc (2.0.0)
  ok   README.md 提到版本 2.0.0
  ok   没有残留 Tate_ASQ* 旧文件名
 结果: PASS  （语法 + 单测 + 结构/版本 全部通过）
```

zip 结构（`pwsh tools/verify.ps1 -Package` 产物，用 §4.2 的校验命令解压列出，正好 6 行）：

```
\AutoSpellQueue\AutoSpellQueue.toc
\AutoSpellQueue\AutoSpellQueue_Locale.lua
\AutoSpellQueue\AutoSpellQueue_Formula.lua
\AutoSpellQueue\AutoSpellQueue_CVar.lua
\AutoSpellQueue\AutoSpellQueue.lua
\AutoSpellQueue\AutoSpellQueue_Options.lua
```

### 门禁不可用时的替代检查

若门禁脚本暂时不可用（例如换了没有 Node / PowerShell 7 的机器），至少人工确认：

1. `.toc` 的 `## Version` == `CHANGELOG.md` 顶部版本 == `README.md` 中标注的版本；
2. `.toc` 列出的 5 个 `.lua` 文件都存在，且发布目录里没有旧文件名（`Tate_ASQ*`）；
3. 全部 `.lua` 无语法错误（在没有 `lua` 的机器上只能靠 `luaparse`，即门禁本身）。

## 关键文件

| 文件 | 职责 |
|---|---|
| `AutoSpellQueue.toc` | 插件清单：版本、SavedVariables、Interface、加载顺序 |
| `AutoSpellQueue_Locale.lua` | 全部显示字符串（enUS / zhCN / zhTW 三套同源生成，键集必然一致；其他客户端语言回退 enUS） |
| `AutoSpellQueue_Formula.lua` | 纯计算：专精/延迟/场景 → 目标值。**禁止**调用任何游戏 API |
| `AutoSpellQueue_CVar.lua` | 唯一读写 `SpellQueueWindow` 的地方，写入 + 读回双重验证，环境可注入（测试用） |
| `AutoSpellQueue.lua` | 配置校验与迁移、所有权状态机、事件、15 秒定时评估、登出归还 |
| `AutoSpellQueue_Options.lua` | 设置面板、悬浮状态条、斜杠命令 `/asq` |
| `tests/`、`tools/`、`docs/` | 开发用，**不进发布包** |
| `CHANGELOG.md` / `README.md` | 版本记录 / 中英双语说明 |
| `docs/ARCHITECTURE.md` | 接口冻结文档，改动前先读 |
| `docs/CURSEFORGE.md` | 发布规划（命名检查、素材、打包、合规、checklist） |
| `.pkgmeta` | BigWigs packager 配置（ignore 非运行期文件） |

## 核心不变量（改代码前务必保持）

1. 写入只有「API 未拒绝 **且** 读回一致」才算成功；失败不得更新 `lastApplied`，不得显示成已应用。
2. 只要改过 CVar，存档里就有 `ownership`（`baseline` + `lastApplied`）；只在「当前值仍等于 `lastApplied`」时才写回 baseline。
3. 别人改过值 → 只释放所有权，**不覆盖**，不重设 baseline。
4. 战斗中不写（只标 `pending`），脱战重新读取实时状态再决策，不重放旧目标。
5. `PLAYER_LOGOUT` 归还 baseline；失败则靠持久化的 `ownership` 在下次登录归还。
6. 存档 `schemaVersion` 高于当前版本时不降级，原样保留并标记 `schemaFuture`。

## 已知风险与待游戏内验证项

以下都是**代码里已按文档实现、但尚未在 12.x 客户端实测**的点。发布前应逐条确认（打勾后即可从本表移除）：

- [ ] **`C_CVar.GetCVarInfo` 的返回值顺序**：`AutoSpellQueue_CVar.lua` 按 `value, defaultValue, isStoredAccount, isStoredCharacter, isLocked, isSecure, isReadOnly` 解析（第 3–8 个返回值）。若客户端顺序不同，只读判断会失效 → 需要实测确认；同时确认 `SpellQueueWindow` 的 `isSecure` / `isReadOnly` / `isLocked` 实际取值。
- [ ] **`GetNetStats()` 的实际刷新频率**：代码注释与文档写「约 30 秒」，这是需要实测的经验值；同时确认 `home` / `world` 在副本、战场、主城下的取值差异，以及 `world == 0` 时回退 Home 是否够用。
- [ ] **客户端默认值**：文档写「`SpellQueueWindow` 客户端默认 400 ms」；确认 `C_CVar.GetCVarInfo` 报告的 `defaultValue` 确实是 400（不同客户端/版本可能不同，插件本身不依赖这个数值）。
- [ ] **城市地图边界**：`Formula.CITY_MAP_FLAG = 0x100000`（`Enum.UIMapFlag.IsCityMap`，文档标注 11.0.0 起）是否覆盖全部主城与中立城；运行时最多沿 `parentMapID` 上溯 4 层，特殊子地图（新主城、相位地图）可能超出。
- [ ] **Options 面板在游戏内的显示**：滚动框是否溢出、高级折叠、状态卡、状态条随字号缩放、`LibSharedMedia-3.0` 不存在时的字体回退（`.toc` 里是 `OptionalDeps`）。
- [ ] **Locale 三语齐全性**：`enUS` / `zhCN` / `zhTW` 三套文案由同一张源表生成（当前 134 个键 × 3 套，离线核查每项都是 3 段字符串），但**仍需在游戏内逐屏确认**没有回退到键名（尤其错误原因文案与状态徽标）；其他客户端语言会回退 enUS。
- [x] **旧存档导入的前提（2026-09-28 实测纠正）**：客户端**只加载与插件文件夹同名的存档文件**（实测本机 `WTF\Account\671932030#1\SavedVariables\Tate_ASQ.lua` 内含 `Tate_ASQDB = {...}`，文件名等于旧插件文件夹名）。因此「删掉旧插件后旧设置会自动导入」**是错的**——那个文件之后再也不会被读取。已在 README / CHANGELOG 写明：想保留旧设置需把该文件复制为同目录下的 `AutoSpellQueue.lua`；`.toc` 声明 `Tate_ASQDB` 是让改名后的文件能到达 `Core.ImportLegacy()` 的必要条件。本机安装时已代为完成该复制（原文件另存为 `Tate_ASQ.lua.pre-v2.bak`）。
- [ ] **旧 `SavedVariables` 置 nil 后客户端的行为**：导入旧存档后代码把 `_G.Tate_ASQDB` 置为 `nil`，但 `.toc` 仍声明了它——客户端是否仍会写回一张空表，需实测（若会，可在后续版本从 `.toc` 移除该声明，但要保证升级路径仍能导入）。
- [ ] **`## X-Curse-Project-ID` 尚未添加**：`.toc` 里当前没有任何 X-Curse 指令（只有 `## X-Website`）——相关占位/说明行已按「`.toc` 没有注释语法」的结论**整行删除**。CurseForge 项目创建后需**新增一行** `## X-Curse-Project-ID: <真实数字>` 才能用 packager 上传（详见 `docs/CURSEFORGE.md` §4.3）。
- [x] **`## X-Website` 已同步**：GitHub 仓库已于 2026-09-28 由 `tatechen88/Tate_ASQ` 改名为 `tatechen88/AutoSpellQueue`（改名前需先解归档），`.toc` 与 README 的 Releases 链接、`git remote` 均已指向新地址；旧链接由 GitHub 301 重定向。
- [ ] **斜杠命令已注册**：`/asq`、`/asq status`、`/asq reset`、`/asq unlock` 由 `AutoSpellQueue_Options.lua` 提供，需在游戏内确认命令与设置面板入口都可用。
- [ ] **基础值表是调参默认值，不是实测数据**：`AutoSpellQueue_Formula.lua` 的专精基础值可按玩家体感调整（不是 bug），如有真实数据再收敛。

## 下一步

1. 跑通 `pwsh tools/verify.ps1` 并贴出输出；确认 `.toc` 与 `CHANGELOG.md` / `README.md` 版本一致。
2. 游戏内回归（人工）：登录 → 切专精 → 进副本 → 回主城 → 进战斗确认不写入（状态 `pending`）→ 脱战确认写入 → `/reload` → 正常登出后重登确认数值已归还 → 关闭插件确认归还 → 删除旧 `Tate_ASQ` 文件夹后确认旧设置被导入一次。
3. 按 `docs/CURSEFORGE.md` 完成命名占用检查、素材准备与打包演练（**本次不发布**）。
4. 决定是否把 GitHub 仓库从 `Tate_ASQ` 改名为 `AutoSpellQueue`（**需用户确认**，因为会改变对外 URL），并同步 `.toc` 的 `X-Website`、README 的 Releases 链接与 badge；步骤见 `docs/CURSEFORGE.md` §1.4。
5. 首次发布后再补 README 的下载链接与商店页链接。

## 接手时先读

1. `docs/ARCHITECTURE.md`（接口契约与不变量，一切以它为准）
2. `AutoSpellQueue.lua` + `AutoSpellQueue_CVar.lua`（核心行为与写入校验）
3. `CHANGELOG.md`（v2.0.0 按审查结论修复了哪些问题）
4. `AGENTS.md`（verify 条款：必须贴出实际输出）
5. `docs/agents/issue-tracker.md`、`docs/agents/domain.md`（工程流程约定）
