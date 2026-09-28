# AutoSpellQueue

> 简体中文 · [繁體中文](#zh-hant) · [English](#english)

自动把《魔兽世界》正式服的**施法容限**（`SpellQueueWindow`，也常被叫作施法队列窗口）保持在适合你
专精、网络延迟**与抖动**的值，并在它不再管理这个设置时，**把你自己原来的值还回去**。

> 正式服 12.x（12.0.0–12.1.5）· v2.0.0 · MIT · 界面语言 enUS / zhCN / zhTW
> 原名 `Tate_ASQ`（Tate's AutoSpellQueue），v2.0.0 起更名为 **AutoSpellQueue**。
> **中文界面显示为「施法容限」**（插件列表、设置页标题、聊天提示都是这个名字），英文界面为 `Auto Spell Queue`。

**📖 玩家请直接看 [`docs/DESCRIPTION.md`](docs/DESCRIPTION.md)**（简体 / 繁體 / English 三版全文：这值是什么、
为什么默认 400 让人难受、谁受益、怎么确认它在工作、它不做什么）。
README 只保留「装、跑、验证」这类实用信息（中英各一份）。

---

## 装（中文）

1. 下载 [Releases](https://github.com/tatechen88/AutoSpellQueue/releases) 里的 zip。
2. 解压到 `World of Warcraft\_retail_\Interface\AddOns\`，得到 `AddOns\AutoSpellQueue\`。
3. 进游戏。**默认就是开着的，不需要配置——面板里只有两个复选框。**

设置入口：游戏内 **选项 → 插件 → 施法容限**（英文界面为 `Auto Spell Queue`），或 `/asq`，或左键点悬浮状态条。
设置页与姊妹插件 **StockTake（数量盘点）** 同一套做法：暴雪原生控件、零自绘、只有四个元素
（标题、一行状态、两个复选框、一个「重置位置」按钮），说明放在鼠标悬停提示里。

**面板里只有两个复选框**：「启用自动调整」（总开关）和「显示悬浮状态条」。
安全余量、写入阈值、延迟来源、窗口上下限、多久检测一次，全部由插件按实测数据自己决定——
把旋钮交给玩家，等于把「调得好不好」的责任推给玩家。
唯一的手动口子是命令行的 `/asq base <50-400>`（某专精的基础值你不同意时才用），它**不出现在面板里**。

**屏幕上的数字会说话**：数字本身是容限值（比如 `220 ms`），但它的**颜色**说的是你的网络——
延迟正常时白色（边框一起白），明显高于你平时的水平就转红；失败 / 等待 / 关闭用各自的状态色。
判据是相对**你自己平时**的延迟（`平时 + 60ms`，下限 120ms、上限 250ms），
所以平时就 200ms 的人不会永远看到红色。悬停状态条会写明「为什么是红的」。

**它不会一直检测**：登录 / 换区 / 进副本团本时采样一小段，读数稳定后**停止采样**，
之后每 300 秒只做一次廉价的漂移检查（真的漂移了才重新采样）。学到的延迟会记住，下次登录立刻用上。

### 从旧版 `Tate_ASQ` 升级

1. **删掉旧的 `AddOns\Tate_ASQ` 文件夹**（新旧会争抢同一个 CVar）。
2. 想保留旧设置的话，把
   `WTF\Account\<账号>\SavedVariables\Tate_ASQ.lua` 复制一份并改名为同目录的 `AutoSpellQueue.lua`。
   客户端**只加载与插件文件夹同名的存档文件**，不复制就回到默认设置（也能用）。
   旧版的手动基础值会被迁移为 `/asq base` 的覆盖值，其余旋钮（余量、迟滞、延迟来源等）随版本退休。

### 一分钟上手

| 我想…… | 怎么做 |
|---|---|
| 看现在的值 | `/dump GetCVar("SpellQueueWindow")` |
| 看它为什么是这个值 | `/asq` → 状态行、悬停提示里有完整算式（含自适应余量） |
| 看诊断（含算法当前的余量/抖动/采样策略/写入次数） | `/asq status` |
| 临时全关、把值还给我 | `/asq` 里取消勾选总开关（战斗中点会等到脱战） |
| 状态条跑到屏幕外了 | `/asq resetpos`（`/asq unlock` 同义）——立即拉回屏幕内的默认位置 |
| 某个专精的基础值我想自己定 | `/asq base 180`（恢复自动：`/asq base auto`） |

### 它不做什么

不自动施法、不代按键、不做输出循环、不读战斗日志、不联网、无遥测。
它改的就是**你自己也能用 `/console SpellQueueWindow 200` 改的那个数字**。

### 许可证

MIT，见 [`LICENSE`](LICENSE)。反馈走 [GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues)。

---

## 给开发者

| 我想…… | 去哪 |
|---|---|
| 看懂代码结构与模块契约 | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| 跑本地验证 | 见下（也见 [`AGENTS.md`](AGENTS.md)） |
| 知道哪些坑已经踩过、哪些还没验证 | [`tests/REGRESSIONS.md`](tests/REGRESSIONS.md)、[`HANDOFF.md`](HANDOFF.md) |
| 发布到 CurseForge | [`docs/CURSEFORGE.md`](docs/CURSEFORGE.md) |
| 知道每份文档归谁管 | [`docs/README.md`](docs/README.md) |

本地没有 `lua`/`luac`，验证走 Node 工具链（`luaparse` 解析 + `fengari` 真 Lua 虚拟机跑单测）：

```powershell
npm --prefix tools install      # 一次性
node tools/check-syntax.mjs     # 语法 + 5.1/5.3 双兼容 lint
node tools/run-tests.mjs        # 假客户端里跑 Formula / Latency / CVar / Core / Locale / Options
pwsh tools/verify.ps1           # 语法 → 单测 → 结构/版本一致性
pwsh tools/verify.ps1 -Package  # 追加：dist/AutoSpellQueue-<version>.zip
```

**跑不过就是没做完**，交付时要贴真实输出（`AGENTS.md` 的硬要求）。

### 仓库结构

```
AutoSpellQueue.toc            # 插件清单（版本号唯一权威出处）
AutoSpellQueue_Locale.lua     # enUS/zhCN/zhTW 三语键表（同一张源表生成，键数由用例保证一致）
AutoSpellQueue_Formula.lua    # 纯计算：专精/延迟/场景 → 目标值（无 WoW API）
AutoSpellQueue_Latency.lua    # 纯算法：延迟平滑、抖动、采样策略（无 WoW API）
AutoSpellQueue_CVar.lua       # 唯一读写 SpellQueueWindow 的地方（写入带读回校验）
AutoSpellQueue.lua            # 配置校验与迁移、所有权状态机、事件与采样节奏
AutoSpellQueue_Options.lua    # 设置面板（StockTake 风格）、悬浮状态条、斜杠命令
tests/ tools/                 # 本地门禁（不进发布包）
docs/                         # 文档（不进发布包）
```

发布包只含 `AutoSpellQueue/` 下的 **7 个运行期文件**（1 个 `.toc` + 6 个 `.lua`），
由 `tools/package.ps1` 保证；结构与指纹规则见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

---

---

<a id="zh-hant"></a>

# 繁體中文

自動把《魔獸世界》正式服的**施法容限**（`SpellQueueWindow`，也常被稱為施法佇列視窗）維持在適合你
專精、網路延遲**與抖動**的值，並在它不再管理這個設定時，**把你自己原本的值還回去**。

> 正式服 12.x（12.0.0–12.1.5）· v2.0.0 · MIT · 介面語言 enUS / zhCN / zhTW
> 原名 `Tate_ASQ`（Tate's AutoSpellQueue），v2.0.0 起更名為 **AutoSpellQueue**。
> **中文介面顯示為「施法容限」**（插件清單、設定頁標題、聊天提示都是這個名字），英文介面為 `Auto Spell Queue`。

**📖 玩家請直接看 [`docs/DESCRIPTION.md`](docs/DESCRIPTION.md)**（簡體 / 繁體 / English 三版全文：這個值是什麼、
為什麼預設 400 讓人難受、誰受益、怎麼確認它在工作、它不做什麼）。
README 只保留「安裝、執行、驗證」這類實用資訊（簡體 / 繁體 / English 各一份）。

## 安裝（繁體）

1. 下載 [Releases](https://github.com/tatechen88/AutoSpellQueue/releases) 裡的 zip。
2. 解壓縮到 `World of Warcraft\_retail_\Interface\AddOns\`，得到 `AddOns\AutoSpellQueue\`。
3. 進入遊戲。**預設就是開啟的，不需要設定——設定頁裡只有兩個核取方塊。**

設定入口：遊戲內 **選項 → 插件 → 施法容限**（英文介面為 `Auto Spell Queue`），或 `/asq`，或左鍵點浮動狀態列。
設定頁與姊妹插件 **StockTake** 同一套做法：暴雪原生控制項、零自繪、只有四個元素
（標題、一行狀態、兩個核取方塊、一個「重設位置」按鈕），說明放在滑鼠停留提示裡。

**設定頁裡只有兩個核取方塊**：「啟用自動調整」（總開關）和「顯示浮動狀態列」。
安全餘量、寫入門檻、延遲來源、視窗上下限、多久偵測一次，全部由插件依實測資料自行決定——
把旋鈕交給玩家，等於把「調得好不好」的責任推給玩家。
唯一的手動出口是指令列的 `/asq base <50-400>`（某個專精的基礎值你不同意時才用），它**不出現在設定頁裡**。

**畫面上的數字會說話**：數字本身是容限值（比如 `220 ms`），但它的**顏色**說的是你的網路——
延遲正常時白色（邊框一起白），明顯高於你平時的水準就轉紅；失敗 / 等待 / 關閉用各自的狀態色。
判斷標準是相對**你自己平時**的延遲（`平時 + 60ms`，下限 120ms、上限 250ms），
所以平時就 200ms 的人不會永遠看到紅色。滑鼠移到狀態列上會寫明「為什麼是紅的」。

**它不會一直偵測**：登入 / 切換區域 / 進副本團本時取樣一小段，讀數穩定後**停止取樣**，
之後每 300 秒只做一次廉價的漂移檢查（真的漂移了才重新取樣）。學到的延遲會記住，下次登入立刻用上。

### 從舊版 `Tate_ASQ` 升級

1. **刪掉舊的 `AddOns\Tate_ASQ` 資料夾**（新舊會爭搶同一個 CVar）。
2. 想保留舊設定的話，把
   `WTF\Account\<帳號>\SavedVariables\Tate_ASQ.lua` 複製一份並改名為同目錄的 `AutoSpellQueue.lua`。
   用戶端**只載入與插件資料夾同名的存檔檔案**，不複製就回到預設設定（也能用）。
   舊版的手動基礎值會被遷移為 `/asq base` 的覆寫值，其餘旋鈕（餘量、遲滯、延遲來源等）隨版本退休。

### 一分鐘上手

| 我想…… | 怎麼做 |
|---|---|
| 看現在的值 | `/dump GetCVar("SpellQueueWindow")` |
| 看它為什麼是這個值 | `/asq` → 狀態列、停留提示裡有完整算式（含自適應餘量） |
| 看診斷（含演算法目前的餘量/抖動/取樣策略/寫入次數） | `/asq status` |
| 臨時全關、把值還給我 | `/asq` 裡取消勾選總開關（戰鬥中點擊會等到脫離戰鬥） |
| 狀態列跑到畫面外了 | `/asq resetpos`（`/asq unlock` 同義）——立即拉回畫面內的預設位置 |
| 某個專精的基礎值我想自己定 | `/asq base 180`（恢復自動：`/asq base auto`） |

### 它不做什麼

不自動施法、不代按鍵、不做輸出循環、不讀戰鬥紀錄、不連網、無遙測。
它改的就是**你自己也能用 `/console SpellQueueWindow 200` 改的那個數字**。

### 授權條款

MIT，見 [`LICENSE`](LICENSE)。回報問題走 [GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues)。

<a id="english"></a>

# English

Automatically keeps World of Warcraft Retail's **spell queue window** (`SpellQueueWindow`) at a value that
fits your spec, your latency **and its jitter** - and gives **your own original value back** when it stops
managing the setting.

> Retail 12.x (12.0.0-12.1.5) · v2.0.0 · MIT · UI languages enUS / zhCN / zhTW
> Formerly `Tate_ASQ` (Tate's AutoSpellQueue); renamed to **AutoSpellQueue** in v2.0.0.
> **On a Chinese client it shows as 「施法容限」** (addon list, settings page title and chat notices all use that name); on an English client it is `Auto Spell Queue`.

**📖 Players: read [`docs/DESCRIPTION.md`](docs/DESCRIPTION.md)** for the full write-up in Simplified Chinese, Traditional Chinese and English
(what the setting is, why the 400 ms default feels bad, who benefits, how to confirm it works, what it never does).
This README keeps only practical information, in both languages.

## Install

1. Download the zip from [Releases](https://github.com/tatechen88/AutoSpellQueue/releases).
2. Extract it into `World of Warcraft\_retail_\Interface\AddOns\` so you get `AddOns\AutoSpellQueue\`.
3. Log in. **It is on by default and needs no configuration - the panel has just two checkboxes.**

Where to find it: **Options → AddOns → Auto Spell Queue**, or `/asq`, or left-click the floating readout.
The settings page follows our sibling addon **StockTake**: Blizzard-native controls, zero custom drawing, four
elements only (title, one status line, two checkboxes, one "reset position" button), with the explanations on
mouse-over tooltips.

**Two checkboxes, that is the whole configuration**: "Enable auto tuning" (the master switch) and
"Show floating status bar". Safety headroom, write threshold, latency source, window limits and how often
to probe are all decided by the addon from what it measures - handing those knobs to a player just moves
the responsibility for getting them right onto the player. The only manual escape hatch is the command
`/asq base <50-400>` (pin the base value for one spec); it is deliberately **not** in the panel.

**The number on screen talks**: the number itself is the tolerance value (e.g. `220 ms`), but its
**colour** is about your connection - white while your latency is what this machine normally sees
(border included), red once it is clearly worse than usual; failure / waiting / disabled keep their own
state colour. The rule is relative to **your own normal** (`normal + 60 ms`, floored at 120 ms and capped
at 250 ms), so a player who lives at 200 ms is not stuck looking at red. Hovering the readout spells out
**why** it is red.

**It does not keep probing**: it samples briefly on login, zone changes and when you enter a dungeon or raid,
then **stops sampling** once the reading settles - after that it only does one cheap drift check every 300 s
(re-sampling only if latency really moved). The learned latency is remembered, so the next login starts at the
right value.

### Upgrading from the old `Tate_ASQ`

1. **Delete the old `AddOns\Tate_ASQ` folder** (old and new fight over the same CVar).
2. To keep your old settings, copy
   `WTF\Account\<account>\SavedVariables\Tate_ASQ.lua` to `AutoSpellQueue.lua` in the same folder. The client
   **only loads the SavedVariables file named after the addon folder**, so without that copy you start from the
   defaults (which is fine too). An old manual base value is migrated into the `/asq base` override; the other
   knobs (margin, hysteresis, latency source, ...) retired with this version.

### Quick reference

| I want to... | How |
|---|---|
| See the current value | `/dump GetCVar("SpellQueueWindow")` |
| See why it is that value | `/asq` - the status line and its tooltip show the full formula (including adaptive headroom) |
| See diagnostics (headroom, jitter, sampling policy, write count) | `/asq status` |
| Turn it off and get my value back | Untick the master checkbox in `/asq` (in combat it waits for combat to end) |
| The readout ended up off-screen | `/asq resetpos` (`/asq unlock` works too) - snaps it straight back to the default on-screen spot |
| Pin the base value for one spec | `/asq base 180` (back to automatic: `/asq base auto`) |

### What it never does

No automation, no key pressing, no rotation, no combat-log reading, no network calls, no telemetry. The only
thing it changes is **the number you could change yourself** with `/console SpellQueueWindow 200`.

## For developers

| I want to... | Where |
|---|---|
| Understand the code structure and module contract | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Run the local gate | Below (also [`AGENTS.md`](AGENTS.md)) |
| Know which traps are already fixed and what is unverified | [`tests/REGRESSIONS.md`](tests/REGRESSIONS.md), [`HANDOFF.md`](HANDOFF.md) |
| Publish to CurseForge | [`docs/CURSEFORGE.md`](docs/CURSEFORGE.md) |
| Know who owns which document | [`docs/README.md`](docs/README.md) |

This machine has no `lua`/`luac`; verification runs on a Node toolchain (`luaparse` for parsing, `fengari` - a
real Lua VM - for the unit tests):

```powershell
npm --prefix tools install      # once
node tools/check-syntax.mjs     # syntax + Lua 5.1/5.3 compatibility lint
node tools/run-tests.mjs        # Formula / Latency / CVar / Core / Locale / Options against a fake client
pwsh tools/verify.ps1           # syntax -> unit tests -> structure/version consistency
pwsh tools/verify.ps1 -Package  # also builds dist/AutoSpellQueue-<version>.zip
```

**If it does not pass, it is not done**; paste the real output when handing work over (a hard rule in `AGENTS.md`).

### Repository layout

```
AutoSpellQueue.toc            # addon manifest (the only authority for the version)
AutoSpellQueue_Locale.lua     # enUS/zhCN/zhTW key table (one source table; a spec keeps all three in step)
AutoSpellQueue_Formula.lua    # pure math: spec/latency/context -> target value (no WoW API)
AutoSpellQueue_Latency.lua    # pure algorithm: smoothing, jitter, sampling policy (no WoW API)
AutoSpellQueue_CVar.lua       # the only place SpellQueueWindow is read/written (writes are verified by read-back)
AutoSpellQueue.lua            # config validation and migration, ownership state machine, events, cadence
AutoSpellQueue_Options.lua    # settings panel (StockTake style), floating readout, slash commands
tests/ tools/                 # local gate (not shipped)
docs/                         # documentation (not shipped)
```

The release package contains exactly the **7 runtime files** under `AutoSpellQueue/` (one `.toc` + six `.lua`),
enforced by `tools/package.ps1`; structure and fingerprint rules live in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## License

MIT - see [`LICENSE`](LICENSE). Feedback via [GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues).

---

> 简体中文 · 繁體中文 · English：三份内容等价。玩家向全文（含"为什么"）在
> [`docs/DESCRIPTION.md`](docs/DESCRIPTION.md)，版本历史（中英双语）在 [`CHANGELOG.md`](CHANGELOG.md)。
> Simplified Chinese, Traditional Chinese and English; all three say the same things. The player-facing long-form copy lives in
> [`docs/DESCRIPTION.md`](docs/DESCRIPTION.md) and the version history (bilingual) in [`CHANGELOG.md`](CHANGELOG.md).
