# CurseForge 发布规划（AutoSpellQueue）

> **状态：规划中，本次不发布。** 本文档是可直接照着执行的操作手册，不代表任何外部动作已经完成。
> 最后更新：2026-09-28 · 适用版本：`2.0.0`
>
> **密钥红线**：本文件、仓库、提交信息、issue 里**一律不写任何密钥值**。只引用 secret 名称（`CF_API_KEY` 等），值只存在于 GitHub Secrets 或本地 Bitwarden。
> 文中凡标注「人工」的步骤都需要有人登录网页后台点击；标注「待确认」的是我无法离线核实、必须在执行时当场核对的外部事实。

---

## 0. 现状快照（发布前先对一遍）

| 项 | 当前值 | 说明 |
|---|---|---|
| 插件名 / 文件夹名 | `AutoSpellQueue` | 文件夹名 == `.toc` 文件名 == 插件名，改任何一个都会导致客户端不加载 |
| 版本 | `2.0.0`（`AutoSpellQueue.toc` 的 `## Version`） | 与 `CHANGELOG.md` 顶部一致，`tools/verify.ps1` 会检查 |
| Interface | `120000, 120001, 120005, 120007, 120100, 120105` | 12.0.0–12.1.5 |
| 分类元数据 | `## Category: Combat` | 与 CurseForge 类目保持一致（见 §2） |
| 本地化 | **已实现 enUS / zhCN / zhTW 三套完整文案**（134 个键 × 3 套，由同一张源表生成，键集必然一致；`docs/ARCHITECTURE.md` §5 契约：三套键集一致，未列出的语言回退 enUS，enUS 再缺才回退键名） | 英文必须是真实文案——曾把「回退 key 本身」当英文，结果英文客户端会显示 `STATE_APPLIED` 这类内部键（已在契约里记为历史教训） |
| `## X-Website` | `https://github.com/tatechen88/AutoSpellQueue` | 已于 2026-09-28 随仓库改名同步（原 `Tate_ASQ`，改名需先解归档；旧链接由 GitHub 301 重定向） |
| `## X-Curse-Project-ID` | **已整行删除**（`.toc` 里没有任何 X-Curse 指令，只剩 `## X-Website`） | 创建项目后**新增** `## X-Curse-Project-ID: <真实 ID>` 指令，否则 packager 无法上传（详见 §4.3） |
| OptionalDeps | `LibSharedMedia-3.0` | 可选依赖，用于状态条字体；缺失时必须能正常回退 |
| 发布产物 | 尚无 | `dist/` 与 `*.zip` 已在 `.gitignore` 中 |
| CI | 尚无 `.github/` | 需要新建 workflow（见 §4.4） |
| 历史发布 | 旧名 `Tate_ASQ` 曾发布到 v1.0.2 | 需在旧项目页标注「已更名/停止更新」 |

---

## 1. 命名与占用检查（发布前必做，人工）

目标：确认 `AutoSpellQueue` 这个插件名在各分发平台都**可创建**，并且不会与已存在的插件混淆。

### 1.1 检查清单

| # | 平台 | 查什么 | 怎么查 | 通过标准 |
|---|---|---|---|---|
| 1 | CurseForge | 是否已有同名项目 | 搜索 `https://www.curseforge.com/wow/addons?search=AutoSpellQueue`；再直接探 slug `https://www.curseforge.com/wow/addons/autospellqueue` 与 `.../auto-spell-queue` | 搜索无同名项目，slug 返回 404（可创建）。若 slug 被占但项目名不同，创建时平台会自动加后缀，需要接受或换名 |
| 2 | CurseForge | 同类竞品与关键词冲突 | 搜索 `SpellQueueWindow`、`Spell Queue`、`Queue Window` | 记录同类插件（竞品不是冲突，但要在描述里说清差异，避免被当成「同类作弊插件」） |
| 3 | Wago | addon 名是否被占用 | 搜索 `https://addons.wago.io/addons?search=AutoSpellQueue`；探 `https://addons.wago.io/addons/autospellqueue` | 未占用（Wago 是可选的第二分发渠道） |
| 4 | WoWInterface | 是否已有同名文件 | 在 `https://www.wowinterface.com/downloads/` 搜索 `AutoSpellQueue` 与 `SpellQueueWindow` | 无同名项目；若已占用，可只在 CF 发布，或与对方区分大小写/前缀（不建议故意近似） |
| 5 | GitHub | 仓库名可用性与旧仓库改名 | 打开 `https://github.com/tatechen88?tab=repositories`；搜索 `https://github.com/search?q=AutoSpellQueue&type=repositories` | 自有账号下无同名仓库则可创建/改名。**改名后旧链接 301 重定向**，但要同步 `.toc` 的 `X-Website`、README 链接、CI badge（建议改名，见 §1.4，**需用户确认**） |
| 6 | 游戏内 | 文件夹重名 | 检查 `World of Warcraft\_retail_\Interface\AddOns\` 下是否已有 `AutoSpellQueue`（或大小写近似）文件夹；`/dump AutoSpellQueue` 检查全局名 | 无重名文件夹。两个同名文件夹会互相覆盖，且 `_G.AutoSpellQueue` 会被覆盖 |
| 7 | 商标/合规 | 名称是否暗示官方或含他人商标 | 名称不得以 `Blizzard` / `WoW` 开头，不得使用他人商标或暗示官方背书；「AutoSpellQueue」是描述性组合词，可接受 | 名称中不含厂商商标、不含 `official` 等暗示词 |
| 8 | 旧名去向 | 旧项目 `Tate_ASQ` 的处置 | CurseForge / WoWI / GitHub 上找到旧项目页 | 旧项目页描述顶部加一行「Renamed to AutoSpellQueue」并停止更新（避免用户继续装旧版） |

### 1.2 如果 `AutoSpellQueue` 已被占用

1. **不要**用近似拼写（`AutoSpellQueuee`、`Auto-SpellQueue`）绕过检查——容易被判定为「蹭名」。
2. 备选名（按优先级，逐个人工查一遍 §1.1）：
   - `SpellQueueTuner`
   - `AutoQueueWindow`
   - `SpellQueueAuto`
   - `SmartSpellQueue`
   
   **选择标准**（三条同时满足）：
   1. **描述性**——玩家看名字就知道它管的是「施法队列窗口」，不用猜缩写（这是本次从 `Tate_ASQ` 更名的初衷，因此**不再接受 `ASQ` 这类缩写**，它正是我们要摆脱的东西）；
   2. **未占用**——§1.1 五个平台全部可创建；
   3. **不含厂商商标**——不以 `Blizzard` / `WoW` 开头，不含他人商标、不暗示官方背书。
3. 换名成本：文件夹名 + `.toc` 文件名 + 全部 `.lua` 前缀 + SavedVariables 名 + README/CHANGELOG/文档 + `.pkgmeta` 的 `package-as`。**换名要趁发布前决定**，一旦发布再改名就是又一次破坏性变更（需要再写一次迁移）。
4. 无论是否换名，`SavedVariables` 都已从 `Tate_ASQDB` 迁移到 `AutoSpellQueueDB`，并保留一次性导入逻辑。

### 1.3 检查记录（执行时填写）

| 平台 | 查询词 / URL | 结果 | 日期 | 证据链接 |
|---|---|---|---|---|
| CurseForge | | | | |
| Wago | | | | |
| WoWInterface | | | | |
| GitHub | | | | |
| 游戏内 AddOns | | | | |

### 1.4 收尾建议：GitHub 仓库改名为 AutoSpellQueue —— **已于 2026-09-28 执行完毕**

已执行：`https://github.com/tatechen88/Tate_ASQ` → `https://github.com/tatechen88/AutoSpellQueue`，
让**仓库名 = 插件名 = 插件文件夹名 = CurseForge 项目名**一致，避免玩家在 Releases 页面下载到 `Tate_ASQ-v2.0.0.zip` 这种旧名产物。

> 执行时遇到并已处理：该仓库处于**已归档（read-only）**状态，必须先
> `gh repo unarchive tatechen88/Tate_ASQ` 才能改名与推送；改名后仓库恢复为
> public + 可写，旧路径由 GitHub 301 重定向。

改名后同步清单（逐项完成情况）：

1. ✅ `.toc` 的 `## X-Website` → 新地址；
2. ✅ `README.md` 中、英两段 Releases 链接 → 新地址；
3. ✅ 本地 `git remote set-url origin https://github.com/tatechen88/AutoSpellQueue.git`；
4. ✅ `HANDOFF.md` / 本文件的旧 URL 说明已更新为「已完成」；
5. ⏳ CI workflow 里的仓库路径引用：目前还没有 `.github/`，将来创建时直接用新名。

改名后已重跑 `pwsh tools/verify.ps1 -Package` 并重新打包（`.toc` 变更会改变 zip 内容指纹）。

---

## 2. 商店页素材清单

CurseForge 项目页需要的素材（数量为最低要求；**具体尺寸/数量以提交时平台页面的实际要求为准**——标注「待确认」的项在创建项目时当场核对）：

| # | 素材 | 规格 | 数量 | 状态 | 备注 |
|---|---|---|---|---|---|
| 1 | Logo / 项目头像 | 512×512 PNG，正方形（待确认是否为强制尺寸） | 1 | 待制作 | 建议用插件图标 `Interface\Icons\Spell_Holy_BorrowedTime` 做底 + 插件名文字；纯色深底 + 绿色（`#0cd29f`，与聊天前缀/标题色一致）点缀 |
| 2 | 截图 | ≥ 1280×720（建议 1600×900 或 1920×1080，PNG） | ≥ 3 | 待制作 | 建议内容：① 设置面板主区域（状态卡：当前值/目标值/延迟/场景）② 高级区展开 ③ 悬浮状态条 + tooltip ④ 战斗中 `pending` 状态 ⑤ `/asq status` 聊天输出。截图里不要出现他人角色名（隐私） |
| 3 | 简介 Summary | 单段短文（平台有字数上限，待确认） | en + zhCN 各 1 | 见 [`docs/DESCRIPTION.md`](DESCRIPTION.md) 末节「商店页短简介」 | 第一句必须说清「只改本地 CVar、不自动施法」 |
| 4 | 详细描述 Description | 支持 Markdown/HTML（待确认编辑器能力） | en + zhCN 各 1 | 见 [`docs/DESCRIPTION.md`](DESCRIPTION.md)（中英各自独立成篇） | 必须包含：功能、**不做什么**、安装、升级注意、命令、已知限制、许可证、反馈渠道（检查清单见 §2.2） |
| 5 | 分类 Category | CurseForge WoW 类目列表 | 1 | 建议 **Combat**（与 `.toc` 的 `## Category: Combat` 一致） | 若平台另有更贴切的类目可改，但 `.toc` 与页面**必须一致**；「Utility」若不作为独立类目存在，用标签表达 |
| 6 | 标签 Tags | 平台标签/自定义关键词 | 3–6 | 建议：`spell queue`、`latency`、`cvar`、`quality of life`，中文再加 `施法队列` | 不要用 `automation` / `bot` / `macro` 这类会被误判的词 |
| 7 | 支持的游戏版本 | CurseForge 的 game version 勾选 | — | **Retail 12.1.5**（与 Interface 最后一项 `120105` 对应），并按 `## Interface` 列表勾选 12.0.0–12.1.5 中平台列出的版本 | 每次补丁后更新（见 §7.4） |
| 8 | 依赖 Dependencies | 可选依赖 | — | **无必需依赖**；`LibSharedMedia-3.0` 是可选（`.toc` 里是 `OptionalDeps`），可作为 Optional dependency 标注 | 不要标成 Required，否则用户会被强制安装库 |
| 9 | 演示动图/视频（可选） | GIF ≤ 约 10 MB 或视频 ≤ 60 s | 0–1 | 可选 | 展示「改延迟 → 数值跟随变化」最有说服力 |

素材存放建议：源文件（PSD/AI、原始截图）放仓库**外面**或 `docs/media/`（`.pkgmeta` 已 ignore `docs/`，不会进发布 zip；但注意仓库体积）。

### 2.1 简介草稿（可直接粘贴）

> **唯一文案源已迁移到 [`docs/DESCRIPTION.md`](DESCRIPTION.md)** 的「商店页短简介」一节（zhCN + en 各一段，可直接粘贴）。
> 本文件不再重复正文，避免两处文案漂移。

### 2.2 详细描述（唯一文案源：`docs/DESCRIPTION.md`）

详细描述的完整中英两版在 **[`docs/DESCRIPTION.md`](DESCRIPTION.md)**：
中文版与 English 版各自独立成篇（不是互译），结尾另附「商店页短简介」。
上传商店页时从那里取文，**不要在本文件里另写一份**。

商店页必须覆盖的检查项（提交前逐条对照 `docs/DESCRIPTION.md` 是否都写到）：

```
# AutoSpellQueue
一句话介绍（第一句必须说清「只改本地 CVar、不自动施法」）

## What it does / 它做什么
- 只改一个 CVar：SpellQueueWindow（0–400 ms，客户端默认 400）
- 基础值（按专精）+ 延迟自适应（World 优先，可选 Home/平均/取大）+ 场景（城市仅基础值）
- 启用期间每 15 秒重新评估；战斗结束立即重新决策

## What it does NOT do / 它不做什么
- 不自动施法、不做输出循环、不模拟按键、不做战斗自动化
- 不读取战斗日志做决策；不联网、无遥测、不上传任何数据
- 它改的设置你自己也能用 /console SpellQueueWindow 改

## Install / 安装
解压到 Interface\AddOns\AutoSpellQueue\（zip 根目录已经是 AutoSpellQueue/）

## Upgrading from Tate_ASQ / 从旧版升级
先删除旧的 Tate_ASQ 文件夹。想保留旧设置需把
SavedVariables\Tate_ASQ.lua 复制为 SavedVariables\AutoSpellQueue.lua
（客户端只加载与插件文件夹同名的存档文件；不复制则回到默认设置）

## Ownership & restore / 所有权与恢复
只在自己写入的值仍生效时才归还；外部改值只放弃所有权不覆盖；登出归还；写入读回校验

## Commands / 命令
/asq、/asq status、/asq reset、/asq unlock

## Known limitations / 已知限制
战斗中不写入（脱战后生效）；延迟读数由客户端约每 30 秒刷新一次，因此数值最多滞后几十秒

## Languages / 语言
enUS / zhCN / zhTW（其他语言客户端回退英文）

## License / Feedback
MIT © 2026 Tate Chen；反馈走 CurseForge 评论或 GitHub Issues
```

> 措辞红线：不要出现 `automation` / `bot` / `cheat` / `script`（指代自动化的语境）等词，避免与违规插件混淆；强调「只改你自己也能改的本地设置」。

---

## 3. 版本与渠道策略

### 3.1 SemVer 与渠道映射

| 变更类型 | 版本位 | Git tag | CurseForge Release Type | 说明 |
|---|---|---|---|---|
| 破坏性（改名、SavedVariables 变更、行为不兼容） | MAJOR | `v2.0.0` | **Release** | 例：本次 1.0.2 → 2.0.0 |
| 新功能 / 新专精 / 新设置项 | MINOR | `v2.1.0` | **Release** | 向后兼容 |
| 修 bug / 补 TOC / 文案 | PATCH | `v2.0.1` | **Release** | 向后兼容 |
| 预发布（想让人先试） | — | `v2.1.0-beta.1` | **Beta** | tag 里带 `-beta` |
| 内部试验 | — | `v2.2.0-alpha.1` | **Alpha** | tag 里带 `-alpha` |

规则：

- **tag 与 `.toc` 的 `## Version` 必须一致**（`tools/verify.ps1` 会检查）；tag 用 `vX.Y.Z` 前缀，`.toc` 里只写 `X.Y.Z`。
- 已推送的 tag **绝不移动/重打**（会破坏用户端缓存与 CI 记录）；改错了就发下一个 PATCH。
- 渠道语义：`main` 分支上打 `v*` tag → Release；`-beta` / `-alpha` tag → Beta / Alpha，让愿意尝鲜的用户自己选。
- 每次发布必须更新 `CHANGELOG.md` 顶部新增对应版本段（CurseForge 的 changelog 会直接引用它）。

### 3.2 发布节奏建议

- 只在实际有改动时发布，不做「定期空发布」。
- 暴雪补丁（12.1.5 / 12.2）上线后 24 小时内发一个只改 `## Interface` 的 PATCH，避免客户端把插件标记为过期。
- Beta 渠道用于「新专精基础值表调整」这类需要玩家反馈的改动。

---

## 4. 打包

### 4.1 硬性约束（两种方式都必须满足）

```
AutoSpellQueue.zip
└── AutoSpellQueue/                 ← 根目录必须正好是这一层
    ├── AutoSpellQueue.toc
    ├── AutoSpellQueue_Locale.lua
    ├── AutoSpellQueue_Formula.lua
    ├── AutoSpellQueue_CVar.lua
    ├── AutoSpellQueue.lua
    └── AutoSpellQueue_Options.lua
```

- 共 **6 个文件**（1 个 `.toc` + 5 个 `.lua`），**不许多也不许少**；
- 不得包含 `tests/`、`tools/`、`docs/`、`.git*`、`node_modules/`、`dist/`、任何 zip/截图/Markdown；
- 文件名大小写必须精确匹配（Linux/macOS 解压后再拷进 Windows 也不能错）；
- `.toc` 内的加载顺序即文件列表顺序：`Locale → Formula → CVar → AutoSpellQueue → Options`。

### 4.2 方式 A：本地打包（首选，零外部依赖）

```powershell
pwsh tools/verify.ps1 -Package
# 产物：dist/AutoSpellQueue-2.0.0.zip（dist/ 与 *.zip 已在 .gitignore）
```

校验（复制粘贴即可）：

```powershell
$zip = "dist/AutoSpellQueue-2.0.0.zip"
$tmp = Join-Path $env:TEMP ("asq-" + [guid]::NewGuid())
Expand-Archive -LiteralPath $zip -DestinationPath $tmp
Get-ChildItem -Recurse -File $tmp | ForEach-Object { $_.FullName.Replace($tmp, '') }
Remove-Item -Recurse -Force $tmp
```

期望输出恰好 6 行，全部形如 `\AutoSpellQueue\<文件>`；出现任何 `\tools\`、`\docs\`、`\.git` 就是打包配置错了。

### 4.3 方式 B：BigWigs packager（CI 自动化）

仓库根目录已提供 `.pkgmeta`：

```yaml
package-as: AutoSpellQueue
enable-nolib-creation: no

ignore:
  - .gitignore
  - .gitattributes
  - .github
  - .pkgmeta
  - .scratch
  - AGENTS.md
  - CHANGELOG.md
  - HANDOFF.md
  - LICENSE
  - README.md
  - docs
  - tests
  - tools
  - node_modules
  - dist
```

要点：

- `package-as: AutoSpellQueue` 保证 zip 根目录就是 `AutoSpellQueue/`；
- `enable-nolib-creation: no`：本插件**没有内嵌库**，不需要生成 `-nolib` 版本；
- `LICENSE` / `CHANGELOG.md` / `README.md` 必须 ignore——它们会**被算进发布包文件数**，破坏「只有 6 个文件」的约束（changelog 内容会由 packager 作为 release changelog 抓取，不需要放进 zip）；
- packager 依据 **git tag** 决定版本与渠道，并会把版本写进 `.toc`（可用 `@project-version@` 占位符；本仓库当前 `.toc` 写的是字面量 `2.0.0`，采用的是「tag 与 `.toc` 手动保持一致」的方式——若要改成占位符，须同时改 `.toc` 与 `verify.ps1` 的一致性检查，以 packager 文档为准）；
- 上传 CurseForge 依赖 `.toc` 里的 `## X-Curse-Project-ID`：**创建项目后新增 `## X-Curse-Project-ID: <真实项目 ID>` 这一行**（必须是真实数字，不要写 `0` / `<id>` 之类的占位）；上传 Wago 用 `## X-Wago-ID`，WoWInterface 用 `## X-WoWI-ID`（可选渠道，不填就不上传对应平台）。
  > 为什么是「新增」而不是「改占位」：`.toc` **没有注释语法**，每一行 `##` 都是指令，任何占位写法（包括 `<id>`）严格来说都是一条非法值指令。因此这类行已从 `.toc` **整行删除**（当前只剩 `## X-Website`），拿到真实 ID 后再新增一行即可——不要试图用「注释掉的占位行」表达。
- 具体参数以 [BigWigs packager 文档](https://github.com/BigWigsMods/packager) 为准（命令名/参数随版本演进，执行时核对一次）。

### 4.4 CI 配置（需要时再建；只写 secret 名称）

`packager` 通过环境变量读取凭据，**值只放在 GitHub Secrets**：

| Secret 名称 | 用途 | 必需性 |
|---|---|---|
| `CF_API_KEY` | CurseForge 上传 API Token（CurseForge 账号设置里生成） | CurseForge 发布必需 |
| `WOWI_API_TOKEN` | WoWInterface 上传凭据 | 可选 |
| `WAGO_API_TOKEN` | Wago 上传凭据 | 可选 |
| `GITHUB_TOKEN` | 创建 GitHub Release / 上传附件 | Actions 自带，无需手动添加 |

操作（人工）：GitHub 仓库 → **Settings → Secrets and variables → Actions → New repository secret**，逐个添加；**不要把值写进 workflow、`.pkgmeta`、README 或任何提交**。

workflow 骨架（`.github/workflows/release.yml`，tag 触发）：

```yaml
name: Release
on:
  push:
    tags: ['v*']
jobs:
  package:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: BigWigsMods/packager@v2
        env:
          CF_API_KEY: ${{ secrets.CF_API_KEY }}
          # WAGO_API_TOKEN / WOWI_API_TOKEN 按需添加（值只在 Secrets 里）
          GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}
```

> `GITHUB_OAUTH` 是 packager 使用的变量名（以 packager 文档为准）；创建 workflow 时核对一次。

### 4.5 两种方式对比

| | 方式 A：本地 `tools/package.ps1` | 方式 B：BigWigs packager + CI |
|---|---|---|
| 依赖 | 本机 PowerShell | GitHub Actions + 平台凭据 |
| 适合 | 手动首发、验证 zip 结构、离线 | 之后每次 tag 自动发布、多渠道 |
| 风险 | 人工上传容易传错文件 | 配置错误会静默少传文件，**首次必须先看 packager 日志里的文件清单** |
| 首次发布建议 | ✅ 先用 A 验证结构与游戏内加载 | 稳定后再接 B |

---

## 5. 合规与政策

> 以下为要点总结，执行前请在暴雪官方政策页面（搜索 “Blizzard UI Add-On Development Policy”，以及《最终用户许可协议》）与 CurseForge 的 Author/Project 协议原文上核对一遍——标注「待确认」的条目以官方原文为准。

### 5.1 暴雪插件政策（要点）

- **不得自动化游戏行为**：插件不能代替玩家施法、不能模拟按键或做战斗决策。AutoSpellQueue 只写一个客户端 CVar，**不施法、不按键、不读战斗日志做决策**。
- **不得收费**：插件必须免费，不得设置付费墙、不得在游戏内募捐或打广告换取功能。
- **不得内嵌广告/推广**：聊天输出只用于状态与错误提示。
- **不得收集/上传玩家数据**：本插件**没有任何网络请求、没有遥测**；存档里只有本地配置与一条所有权记录（baseline / 最后写入值 / 时间戳）。
- **不得修改暴雪文件**：只读 API + 写 CVar，不 patch 客户端。
- **命名不得暗示官方背书**：不使用 `Blizzard` / `WoW` 前缀，不使用他人商标。

### 5.2 商店页需要写明的合规声明

**en**

> AutoSpellQueue only changes a local client setting (`SpellQueueWindow`) that you can also change yourself with a console command. It does not automate gameplay, cast spells, press keys, or make combat decisions. It makes no network requests, contains no telemetry, and collects or uploads no data. It is free and open source (MIT).

**zhCN**

> AutoSpellQueue 只修改一个本地客户端设置（`SpellQueueWindow`），这个设置你自己也能用控制台命令修改。它不会自动施法、不模拟按键、不做战斗决策；不发起任何网络请求、无遥测、不收集或上传任何数据。免费开源（MIT）。

### 5.3 CurseForge 侧约定（待确认）

- 创建项目时需接受平台的 Author / Project 提交协议（人工勾选）；
- 不得转载他人插件；本插件为原创，`LICENSE` 与商店页许可证字段一致；
- 若启用平台的作者激励计划（Author Rewards），需自行确认对「免费插件」定位没有影响（本插件功能永远不得因付费而变化）。

---

## 6. 发布前检查单

代码与门禁：

- [ ] `AutoSpellQueue.toc` 的 `## Version` == `CHANGELOG.md` 顶部版本 == `README.md` 标注版本，且 tag 计划为 `v2.0.0`
- [ ] `## Interface` 覆盖目标客户端版本（补丁日当天下发的是 12.1.5 → 含 `120105`）
- [ ] **新增** `## X-Curse-Project-ID: <真实项目 ID>` 指令（当前 `.toc` 里没有该指令；**没有这一行就无法上传**）
- [ ] `## X-Website` 指向最终仓库地址
- [ ] `npm --prefix tools install` 已执行
- [ ] `node tools/check-syntax.mjs` 通过
- [ ] `node tools/run-tests.mjs` 通过
- [ ] `pwsh tools/verify.ps1` 全绿（**把实际输出贴进发布说明/交接**）
- [ ] `pwsh tools/verify.ps1 -Package` 产出的 zip 结构校验通过（恰好 6 个文件，根目录为 `AutoSpellQueue/`）
- [ ] 旧文件（`Tate_ASQ.lua` / `Tate_ASQ_Formula.lua` / `Tate_ASQ_Options.lua` / `Tate_ASQ.toc`）已从仓库删除——**它们不在 `.pkgmeta` 的 ignore 列表里**，留着就会被打进发布包并突破「只有 6 个文件」的约束
- [ ] zip 解压后拷进 `_retail_\Interface\AddOns\` 能正常加载且无 Lua 报错（`/console scriptErrors 1`）

游戏内人工回归（发布前必做一次）：

- [ ] 首次登录（新存档）：默认启用，值被调整到合理区间
- [ ] 从旧版升级：旧 `Tate_ASQ` 文件夹已删除，旧设置被导入一次
- [ ] 切专精 → 数值按新专精基础值变化
- [ ] 进副本 / 团本 → 使用基础值 + 延迟自适应
- [ ] 回主城 → 回到基础值
- [ ] 战斗中 → 状态显示 `pending`，CVar 不变
- [ ] 脱战 → 立即重新决策并写入
- [ ] 战斗中关闭插件 → 归还推迟到脱战（脱战后值回到玩家原值）
- [ ] 手动 `/console SpellQueueWindow 123` → 插件不覆盖，只释放所有权
- [ ] 正常登出/重登 → 玩家原值已归还
- [ ] 关闭插件 → 值归还；再启用 → 重新接管
- [ ] `/asq`、`/asq status`、`/asq reset`、`/asq unlock` 均可用
- [ ] 三种语言（enUS / zhCN / zhTW）下界面与聊天文案都是真实文案，不出现 `PANEL_TITLE` / `CHAT_ERROR` 这类键名（源表 134 键 × 3 已离线核查，仍需游戏内逐屏确认）
- [ ] 设置面板标题在三语下都是 `AutoSpellQueue`，不含暗示自动化的措辞

商店页与素材：

- [ ] 命名占用检查完成并记录（§1.3）
- [ ] Logo 512×512、截图 ≥3 张、简介与详细描述 en/zhCN 全部就绪，**无占位文本**
- [ ] 分类 = Combat（与 `.toc` 一致）；标签不含 `automation` / `bot` 等词
- [ ] 支持版本勾选 Retail 12.1.5（及平台列出的 12.0.0–12.1.5）
- [ ] 依赖留空（`LibSharedMedia-3.0` 标为可选）
- [ ] 许可证字段与 `LICENSE`（MIT）一致
- [ ] 合规声明（§5.2）已贴在描述里
- [ ] 旧项目 `Tate_ASQ` 页面已加「已更名」提示并停止更新

发布动作：

- [ ] 提交信息/CHANGELOG 与 tag 一致，`git tag v2.0.0` 已推送
- [ ] 上传的 zip 与本地校验过的 zip 是**同一个文件**（比对大小/哈希）
- [ ] 发布后把 CurseForge 链接补进 `README.md`（英文段与中文段都要）

---

## 7. 发布后流程

### 7.1 冒烟检查（发布后 30 分钟内）

1. 从 CurseForge 页面下载刚发布的 zip，解压比对：根目录 `AutoSpellQueue/`、6 个文件；与本地 `dist/` 产物做哈希比对。
2. 页面确认：版本号、Release Type、支持版本、changelog 是否显示为 `CHANGELOG.md` 顶部段落。
3. 装进游戏复跑 §6 里最关键的 4 项：登录生效、战斗不写、脱战写入、登出归还。

### 7.2 回滚

- **能修就前进**：优先发 PATCH（例如 `2.0.1`），因为已经下载的用户不会自动回退。
- **必须下线时**：在 CurseForge 项目页删除出错的文件版本，并把上一个正常版本设为默认下载；在描述顶部/评论里说明原因与替代版本。
- **代码侧**：`git revert` 出问题提交 + 打新 tag 发布；**不要**移动或删除已推送的 tag。
- **数据侧**：如果坏版本已经写过玩家 CVar，注意它可能留下 `ownership` 记录——新版本会按既有语义归还 baseline，不要手动改用户存档。

### 7.3 Issue 追踪

| 渠道 | 用途 | 约定 |
|---|---|---|
| CurseForge 评论 | 玩家第一接触点 | 版本相关问题先要求贴 `/asq status` 输出 |
| GitHub Issues | 可复现的 bug / 功能请求 | 提供模板：插件版本、客户端版本、职业专精、场景（城市/副本/野外）、`/asq status` 输出、是否装同类插件 |
| 本地 markdown tracker | 开发期内部 ticket | 见 `docs/agents/issue-tracker.md`（`.scratch/<feature>/`） |

不要要求玩家提供任何账号/个人信息（合规红线）。

### 7.4 兼容性更新节奏与 TOC 流程

补丁号规则：`## Interface` 用 `MMmmpp`（12.1.5 → `120105`，12.2.0 → `120200`，12.2.5 → `120205`）。

- **PTR / Beta 期**：客户端能识别新 interface 号后即可提前加进列表（保留旧号，逗号分隔），例如追加 `120200` → `## Interface: 120000, ..., 120105, 120200`。
- **正式上线 24 小时内**：确认新号有效后发 PATCH 版本（只改 `.toc` + `CHANGELOG.md`）。
- 步骤：

  1. 更新 `## Interface`（追加新号，**不要删旧号**，删了会让旧客户端认为插件过期）；
  2. `CHANGELOG.md` 顶部新增 `## vX.Y.Z — 日期` 段，写明「支持 12.2.0」；
  3. `.toc` 的 `## Version` 同步 +1（PATCH 位）；
  4. 跑 `pwsh tools/verify.ps1`（版本一致性检查会拦住漏改）；
  5. `git tag vX.Y.Z` 并推送，按 §4 发布；
  6. 如果只改 TOC，Release Type 仍是 **Release**（不是 Beta）。

- **12.1.5 / 12.2 待办表**：

  | 目标 | 需要的动作 | 触发条件 |
  |---|---|---|
  | 12.1.5（已在 `.toc` 中） | 无（发版时勾选对应 game version） | 已支持 |
  | 12.2.0（`120200`） | 追加 interface 号 → PATCH 发布 | PTR 上号可识别 / 正式上线 |
  | 12.2.x 后续小版本 | 同流程追加号 | 同上 |
  | 若有 API 变更（`C_CVar` / `C_Map` / `GetNetStats`） | 先跑门禁 + 游戏内回归，再决定 PATCH 或 MINOR | 暴雪 patch notes 提到相关 API |

---

## 8. 许可证建议

**建议：MIT（已按此提供 `LICENSE`，作者 Tate Chen，年份 2026）。**

理由：

- 插件是单文件级工具、不内嵌第三方库，MIT 足够表达「随便用、随便改、保留版权声明」；
- MIT 与 CurseForge / Wago / WoWInterface 的再分发方式兼容（这些平台会原样分发 zip）；
- 其他插件作者可以把其中的 CVar 校验或公式拿走复用，符合插件生态的惯例；
- 免责条款（无担保）对这类直接写客户端设置的工具也合适。

**如果需要 GPL**（希望衍生作品必须同样开源）：

- 只需把根目录 `LICENSE` 全文替换为 GPLv3 文本，本文件与 README 的许可证段落同步改；
- `.pkgmeta` 已忽略 `LICENSE`，**不影响**「发布包只有 6 个文件」的约束；
- 商店页的许可证字段要一起改（CurseForge 项目页可声明 License）；
- 注意 GPL 与「插件被整合进闭源插件包」不兼容，会劝退一部分复用者。

**不建议**：

- 不放 `LICENSE`（默认保留全部权利，别人无法合法搬运/整合，社区通常也视为不友好）；
- `CC-BY-NC` 之类非软件许可证（与插件工具的使用方式不匹配，且「非商业」定义模糊）。

---

## 9. 附：本次不做什么

- ❌ 本次**不创建** CurseForge / Wago / WoWInterface 项目，不发布任何版本；
- ❌ 不改 GitHub 仓库名（需要时由仓库负责人统一改，并同步 `.toc` 元数据与文档链接）；
- ❌ 不写任何密钥值，不创建任何 secret；
- ❌ 不制作图形素材（只给规格与建议）。
