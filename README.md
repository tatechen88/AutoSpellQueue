# AutoSpellQueue

**自动把「施法队列窗口」（`SpellQueueWindow`）调整到适合你职业专精与网络延迟的值，并在插件不工作时把你原来的值放回去。**

魔兽世界正式服（12.x）插件 · 版本 **2.0.0** · 作者 **Tate Chen** · 许可证 **MIT** · 语言 **enUS / zhCN / zhTW**

> 原名 **Tate_ASQ / Tate's AutoSpellQueue**。v2.0.0 起更名为 **AutoSpellQueue**，插件文件夹名也随之改变（升级说明见下）。
>
> 📖 **玩家视角的完整说明（中文 + English）：[`docs/DESCRIPTION.md`](docs/DESCRIPTION.md)** ——
> 它是商店页与发布说明的唯一文案源，本 README 保留安装/开发向的内容。
> Player-facing guide (中/EN) lives in [`docs/DESCRIPTION.md`](docs/DESCRIPTION.md).

---

## 它做什么 / 它不做什么

**做一件事**：读写客户端的 `SpellQueueWindow`（单位毫秒，可用范围 0–400，客户端默认 400）。这个值决定你能在「当前技能/GCD 结束前多少毫秒」预输入下一个技能。值偏小容易断档，值偏大技能会发黏。

**明确不做**：

- ❌ 不自动施法、不代打输出循环、不模拟按键、不做任何战斗自动化；
- ❌ 不读取战斗日志做决策，不替你判断该放什么技能；
- ❌ 不联网、无遥测、不上传任何玩家数据（整个插件没有任何网络请求）；
- ❌ 不修改暴雪文件，不注入代码。

它改的只是一个**你自己也能用 `/console SpellQueueWindow 200` 改**的本地客户端设置。

---

## 安装与升级

1. 下载发布包 zip（[GitHub Releases](https://github.com/tatechen88/AutoSpellQueue/releases)）。
2. 解压得到 `AutoSpellQueue` 文件夹，放到：

   ```
   World of Warcraft\_retail_\Interface\AddOns\AutoSpellQueue\
   ```

3. 进入游戏，插件默认启用。

### 从旧版（Tate_ASQ / Tate's AutoSpellQueue）升级

1. **删除旧的 `AddOns\Tate_ASQ` 文件夹**。新旧是两个独立插件，同时存在会互相争抢同一个 CVar。
2. **想保留旧设置才需要做这一步**（不做也能用，只是回到默认设置）：

   ```
   WTF\Account\<你的账号>\SavedVariables\Tate_ASQ.lua
        → 复制一份并改名为同目录下的 AutoSpellQueue.lua
   ```

   原因是客户端**只加载与插件文件夹同名的存档文件**：旧设置写在 `Tate_ASQ.lua` 里，
   删掉旧插件后没有任何东西会去读它。改名后新插件第一次登录就能读到 `Tate_ASQDB`
   并导入设置，随后清空旧变量（之后 `AutoSpellQueue.lua` 归新插件独有）。
3. 进入游戏，插件默认启用。

---

## 工作原理

最终值由三层算出来，任何一层都可以在设置面板里改：

### 1）职业 / 专精基础值

插件内置一张按专精的基础值表（`AutoSpellQueue_Formula.lua`）：高 APM 近战（盗贼、踏风）约 140，标准近战约 150，坦克略高（便于排减伤），远程瞬发偏低，读条法系约 240。未知专精（新职业、低等级、数据缺失）按职业回退，再回退到兜底值，**永远不会算出 nil**。

### 2）网络延迟自适应

读取 `GetNetStats()` 的延迟（默认用 **World**，World 为 0 时回退 Home；也可切换为 Home / 平均 / 取大）：

```
延迟需求 = 所选延迟 + 余量（默认 50 ms）
目标值   = max(基础值, 延迟需求)
```

网络好时用基础值，网络差时自动抬高。

### 3）场景

| 场景 | 算法 | 原因 |
|---|---|---|
| 城市（安全区） | 只用基础值 | 城里没有战斗，不需要追延迟 |
| 副本 / 团本 | 基础值 + 延迟自适应 | 战斗强度最高，避免断档 |
| 野外 | 基础值 + 延迟自适应 | 可能随时进战斗 / PvP |

判定方式：`IsInInstance()` → 副本；否则沿地图层级向上找 `IsCityMap` 标记 → 城市；其余为野外。

最后统一 `clamp(round(目标值), minWindow, maxWindow)`，默认 50–400 ms。

### 4）什么时候会重新计算

- 进入世界 / 切换区域（`PLAYER_ENTERING_WORLD`、`ZONE_CHANGED*`）；
- 切换专精（`PLAYER_SPECIALIZATION_CHANGED`，只认玩家自己）；
- 游戏内 CVar 被改动（`CVAR_UPDATE`，0.5 秒防抖）；
- 你在设置面板里改配置；
- **启用期间每 15 秒**重新评估一次（延迟是会变的，不能只在换区域时才更新）；
- 登录后 2 / 5 / 10 / 20 / 40 秒补算几次，直到客户端能报出非零延迟为止；
- 脱战瞬间（`PLAYER_REGEN_ENABLED`）重新评估。

### 默认设置

| 设置 | 默认 | 说明 |
|---|---|---|
| 启用 | 开 | 总开关 |
| 基础值模式 | 自动 | 自动 = 按专精表；手动 = 你指定固定基础值 |
| 手动基础值 | 200 ms | 仅手动模式生效 |
| 延迟自适应 | 开 | 关掉后只用基础值 |
| 延迟来源 | World | World / Home / 平均 / 取大 |
| 余量 | 50 ms | 加在延迟上 |
| 下限 / 上限 | 50 / 400 ms | 最终值范围 |
| 迟滞 | 10 ms | 已经接管后，差值小于它就不来回改 |
| 状态条 | 显示 | 悬浮显示当前值，可拖动、记忆位置 |
| 状态条字体 / 字号 | `Fonts\FRIZQT__.TTF` / 12 | |
| 聊天提示 | 关 | 每次改值都在聊天框报告 |

---

## 所有权与恢复语义（它和「写一次就不管」的区别）

插件只在自己「接管」这个 CVar 时才认为有权写它，接管时会记录**接管前的玩家原值（baseline）**：

- **写入必须验证**：`SetCVar` 只有在「API 没有拒绝」**且**「读回的值与目标一致」时才算成功。只 `pcall` 不报错**不等于**写成功（这是旧版最严重的问题：写入静默失败，界面却显示已生效）。写入失败会保留所有权、在状态里显示失败原因，并在下一次刷新重试。
- **只在自己的值上恢复**：关闭插件时，只有当当前值**仍然等于插件最后写入的值**，才会写回 baseline；如果这期间你（或别的插件）改过值，插件只放弃所有权，**绝不覆盖你的修改**。
- **登出前归还**：`PLAYER_LOGOUT` 会把 baseline 写回去，客户端随后保存设置；万一这次归还失败，所有权记录已经持久化，下次登录仍能归还。
- **战斗中不写**：战斗中不写 CVar（状态显示 `pending`），脱战后**重新读取当时的状态再决策**——不会把战斗前算出的旧目标硬套上去。这条对「应用」和「归还」一视同仁：战斗中关闭插件，归还也会等到脱战。
- **配置会校验**：存档里的越界值、错类型、上下限颠倒、坏掉的所有权记录都会被修正回默认值，修正次数记录在统计里；比当前版本更新的存档（未来版本写的）**不会被降级改写**。
- **错误不静默**：写入/读取错误一定会出现在聊天框（同一条错误 120 秒内不重复刷屏），即使你关掉了聊天提示。

---

## 常见问题

**延迟变化多久生效？**
插件每 15 秒重新评估一次；但客户端的 `GetNetStats()` 自身大约每 30 秒才刷新一次延迟读数，所以从网络真的变化到写入完成，通常几十秒内（最坏约 30 秒 API 刷新 + 最多 15 秒轮询 ≈ 45 秒）。这是两个不同的时间，别把它们混在一起。

**为什么我在战斗中看不到它生效？**
战斗中不写 CVar（这是插件的硬约束，避免战斗中的意外改动）。状态会显示「等待中（pending）」，脱战后立刻重新决策并写入。战斗中关闭插件也一样：归还玩家原值的动作会推迟到脱战。

**为什么我关掉插件后值会变回去？**
那是设计行为：关闭插件 = 归还你自己原来的值。

**为什么关掉插件后值没有变回去？**
说明这个值已经不是你接管前的那个值了——你在插件管理期间自己改过它，或者别的插件改过。这种情况插件只放弃所有权，不覆盖你现在的设置，这是刻意的。

**装完发现补丁后还是要等一会儿才准？**
登录后插件会按 2/5/10/20/40 秒补算，直到客户端报出非零延迟；副本切换、切专精都会立刻重算。

**会不会和我装的别的插件打架？**
如果有另一个插件也在管 `SpellQueueWindow`，两边会互相把对方视为「外部改动」并放弃所有权，最终值取决于谁最后写。建议同一时间只留一个。

**我想彻底卸载，怎么让数值干净地还原？**
先在游戏内**关闭插件**（或正常登出一次），确认状态显示已恢复原值，然后再删除 `AutoSpellQueue` 文件夹。插件文件删掉之后，它就没机会再归还了。

**我的设置存哪？**
存档变量 `AutoSpellQueueDB`（`WTF\Account\<账号>\SavedVariables\`），只包含配置和一条所有权记录（baseline / 最后写入值 / 时间戳）。没有别的数据。旧存档 `Tate_ASQDB` 会**一次性**导入后清空。

---

## 命令

| 命令 | 作用 |
|---|---|
| `/asq` | 打开设置面板（等价命令：`/autospellqueue`） |
| `/asq status` | 打印诊断（状态、当前值 / 目标值、World 与 Home 延迟、专精与定位、场景、所有权与 baseline、计数与错误） |
| `/asq reset` | 重置全部设置为默认值（含悬浮状态条位置；不影响已接管的值） |
| `/asq unlock` | 重置悬浮状态条位置 |

设置面板入口：**游戏菜单 → 选项 → 插件 → AutoSpellQueue**，或左键点状态条。

---

## 开发与验证

本机没有 `lua` / `luac`，验证走 Node 工具链（语法用 `luaparse` 按 Lua 5.1 解析，单元测试用 `fengari` 按 Lua 5.3 执行，因此代码必须 5.1/5.3 双兼容）：

```powershell
npm --prefix tools install     # 一次性，安装 luaparse / fengari
node tools/check-syntax.mjs    # 语法检查（仓库内全部 .lua）
node tools/run-tests.mjs       # 单元测试（公式 / CVar / 核心状态机）
pwsh tools/verify.ps1          # 一条命令：语法 → 单测 → 结构/版本一致性
pwsh tools/verify.ps1 -Package # 再生成 dist/AutoSpellQueue-<版本>.zip
```

任何声称「已完成」的改动，都要贴出实际命令与输出，见 [`AGENTS.md`](AGENTS.md)。

### 仓库结构

| 路径 | 说明 |
|---|---|
| `AutoSpellQueue.toc` | 插件清单（版本、加载顺序、元数据） |
| `AutoSpellQueue_Locale.lua` | 全部显示字符串（enUS / zhCN / zhTW 三套键集一致，其他语言回退 enUS） |
| `AutoSpellQueue_Formula.lua` | 纯计算：专精 / 延迟 / 场景 → 目标值（不调用任何游戏 API） |
| `AutoSpellQueue_CVar.lua` | 唯一读写 `SpellQueueWindow` 的模块（写入 + 读回双重验证） |
| `AutoSpellQueue.lua` | 配置校验与迁移、所有权状态机、事件、定时评估 |
| `AutoSpellQueue_Options.lua` | 设置面板、悬浮状态条、斜杠命令 |
| `tests/`、`tools/`、`docs/` | 开发用，不进发布包 |

发布包（zip）根目录必须是 `AutoSpellQueue/`，且只含上面 6 个运行期文件。接口契约见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

---

## 许可证

MIT，© 2026 Tate Chen，全文见 [`LICENSE`](LICENSE)。

---

## English

**AutoSpellQueue automatically keeps the spell queue window (`SpellQueueWindow`) tuned to your class, spec and latency — and puts your own value back when the addon stops managing it.**

World of Warcraft retail (12.x) · version **2.0.0** · by **Tate Chen** · **MIT** licensed · languages **enUS / zhCN / zhTW**

Formerly **Tate_ASQ / Tate's AutoSpellQueue**; renamed in v2.0.0 (the addon folder name changed too).

### What it does / what it does not do

It does exactly one thing: it reads and writes the client's `SpellQueueWindow` CVar (milliseconds, usable range 0–400, client default 400), which decides how early you can queue your next spell before the current cast/GCD ends.

It does **not** automate casting, does **not** run a rotation, does **not** press keys or make combat decisions, reads no combat log, and makes **no network requests, no telemetry, no data uploads**. It only changes a local client setting you could change yourself with `/console SpellQueueWindow 200`.

### Install / upgrade

1. Download the latest zip from [GitHub Releases](https://github.com/tatechen88/AutoSpellQueue/releases).
2. Unzip so that you get `World of Warcraft\_retail_\Interface\AddOns\AutoSpellQueue\`.
3. Log in — the addon is enabled by default.

**Upgrading from the old version: delete the old `Tate_ASQ` folder first.** Old and new are two separate addons that would fight over the same CVar.

*Keeping your old settings is optional.* The client only loads a SavedVariables file named after the addon folder, and the old settings live in `Tate_ASQ.lua` — after deleting the old addon nothing reads it. To carry them over, copy

```
WTF\Account\<your account>\SavedVariables\Tate_ASQ.lua
     → the same folder as AutoSpellQueue.lua
```

The new addon then reads `Tate_ASQDB` once on the next login and clears it. Without that copy it simply starts from the defaults.

### How it works

1. **Base value** per spec (roughly 140 ms for high-APM melee, ~150 ms for standard melee, slightly higher for tanks, ~240 ms for casters). Unknown specs fall back to the class value, then to a safe default — never nil.
2. **Latency adaptation** using `GetNetStats()` (World by default, falling back to Home; Home / average / max selectable): `target = max(base, latency + margin)`, margin default 50 ms.
3. **Context**: cities (safe areas) use the base value only; instances and the open world use latency adaptation. Finally the value is clamped to `[minWindow, maxWindow]` (default 50–400 ms).
4. **Re-evaluated** on entering the world, zone changes, spec changes, external CVar edits (0.5 s debounce), config changes, **every 15 seconds while enabled**, and a few times after login (2/5/10/20/40 s) until the client reports non-zero latency.

### Ownership and restore semantics

The addon records the value you had **before** it took over (the baseline), and only writes when it can verify the write (API accepted it **and** reading the CVar back returns the requested value). A bare `pcall` success is not treated as success. While disabled, it restores the baseline only if the current value is still the one it wrote; if you or another addon changed it, it just releases ownership and never overwrites you. On `PLAYER_LOGOUT` it puts your value back, and the persisted ownership record lets the next session finish the job if that write failed. It never writes during combat — the status shows `pending` and the decision is re-made from live state when combat ends, and the same rule applies to the restore (disabling in combat is deferred until combat ends).

### Commands

`/asq` (open settings — `/autospellqueue` also works), `/asq status` (print diagnostics), `/asq reset` (reset settings), `/asq unlock` (reset status bar position). Settings panel: Game Menu → Options → AddOns → AutoSpellQueue.

### FAQ

- **How fast does latency take effect?** The addon re-evaluates every 15 s, but `GetNetStats()` itself only refreshes roughly every 30 s; expect the change within tens of seconds (worst case ≈ 30 s API refresh + up to 15 s poll).
- **Why nothing happens in combat?** Writing is deliberately skipped in combat; it happens right after combat ends, based on freshly read state. Disabling the addon during combat is handled the same way — the restore waits for combat to end.
- **Why did the value change back when I disabled the addon?** That is the restore: your original value comes back. If it did *not* change back, someone else changed the value in the meantime — the addon refuses to overwrite that.
- **Uninstalling cleanly:** disable the addon in game (or log out once) so it can restore your value, then delete the folder.

### Development

```powershell
npm --prefix tools install
node tools/check-syntax.mjs
node tools/run-tests.mjs
pwsh tools/verify.ps1
pwsh tools/verify.ps1 -Package
```

No `lua` binary is required: syntax is parsed with `luaparse` (Lua 5.1) and tests run under `fengari` (Lua 5.3), so the code stays 5.1/5.3 compatible. Paste real output before claiming anything is done.

---

## 繁體中文（摘要）

**AutoSpellQueue** 是《魔獸世界》正式服（12.x）插件，會依職業／專精、網路延遲與目前場景，自動調整 `SpellQueueWindow`（施法佇列視窗），並在插件停用時把你自己原本的值放回去。原名 **Tate_ASQ**，v2.0.0 起更名。

- 只改一個本機 CVar（0–400 ms，客戶端預設 400），**不會自動施法、不做戰鬥自動化、不連網、不上傳任何資料**。
- 城市＝基礎值；副本／野外＝`max(基礎值, 延遲 + 餘量)`，最後 clamp 到上下限。
- 啟用期間每 15 秒重新評估；戰鬥中不寫入，脫戰後重新決策；關閉插件或登出時歸還原值。
- 從舊版升級**請先刪除 `Tate_ASQ` 資料夾**，舊設定會自動匯入一次。
- 指令：`/asq`、`/asq status`、`/asq reset`、`/asq unlock`。

詳細說明請看上面的中文與英文段落。
