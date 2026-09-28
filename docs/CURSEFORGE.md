# CurseForge 发布规划与操作手册

> **状态：规划完成，尚未发布。** 本文档可直接照着执行；「人工」= 必须有人登录网页后台点击。
> 最后重写：2026-09-28（v2.0.0）。
>
> **密钥红线**：本文件、仓库、提交信息、issue 里**一律不写密钥值**，只引用 secret 名称
> （`CF_API_KEY` 等），值只存在于 GitHub Secrets 或本地 Bitwarden。
>
> 商店页文案正文在 [`DESCRIPTION.md`](DESCRIPTION.md)——**不要在本文里另写一份**。

## 0. 现状快照

| 项 | 当前值 | 说明 |
|---|---|---|
| 插件名 / 文件夹名 | `AutoSpellQueue` | 文件夹名 == `.toc` 文件名 == 插件名，改任何一个都会导致客户端不加载 |
| 版本 | 见 `AutoSpellQueue.toc` 的 `## Version` | 与 `CHANGELOG.md` 一致，`pwsh tools/verify.ps1` 会检查 |
| Interface | 见 `.toc` 的 `## Interface` | 覆盖 12.0.0–12.1.5；每次补丁后按 §7.4 更新 |
| 分类 | `## Category: Combat` | 需与 CurseForge 页面类目一致 |
| 语言 | enUS / zhCN / zhTW（其他语言回退 enUS） | 商店页写「Languages」 |
| `## X-Website` | `https://github.com/tatechen88/AutoSpellQueue` | 仓库已于 2026-09-28 由 `Tate_ASQ` 改名 |
| `## X-Curse-Project-ID` | **尚未添加** | 创建项目后**新增**该指令并填真实 ID，否则 packager 无法上传 |
| 依赖 | 无必需依赖；`LibSharedMedia-3.0` 可选（`OptionalDeps`） | 商店页标成 Optional，不要标 Required |
| 打包 | `tools/package.ps1` → `dist/AutoSpellQueue-<version>.zip` | 本地可复现，见 §4.2 |
| CI | 尚无 `.github/` | 需要时按 §4.4 建 |
| 旧项目 | `Tate_ASQ` 曾发到 v1.0.2 | 旧页面需要标注「已更名为 AutoSpellQueue」 |

## 1. 命名与占用检查（发布前，人工）

目标：确认 `AutoSpellQueue` 在各平台**可创建**，且不与已有插件混淆。

| # | 平台 | 查什么 | 怎么查 | 通过标准 |
|---|---|---|---|---|
| 1 | CurseForge | 是否已有同名项目 | 搜 `curseforge.com/wow/addons?search=AutoSpellQueue`；再直接探 slug `/autospellqueue` 与 `/auto-spell-queue` | 无同名项目、slug 404（可创建）。slug 被占但项目名不同时平台会自动加后缀 |
| 2 | CurseForge | 同类竞品与关键词 | 搜 `SpellQueueWindow`、`Spell Queue`、`Queue Window` | 记录竞品；描述里说清差异，避免被当成自动化插件 |
| 3 | Wago | 名称占用 | 搜 `addons.wago.io/addons?search=AutoSpellQueue` | 未占用（Wago 是可选的第二渠道） |
| 4 | WoWInterface | 同名文件 | 在 `wowinterface.com/downloads/` 搜 `AutoSpellQueue` / `SpellQueueWindow` | 无同名项目 |
| 5 | GitHub | 仓库名 | `github.com/tatechen88?tab=repositories` | ✅ 已改名成功（原 `Tate_ASQ`，改名前置：仓库处于归档状态，需先 `gh repo unarchive`） |
| 6 | 游戏内 | 文件夹重名 | 检查 `_retail_\Interface\AddOns\` 下是否已有同名/大小写近似文件夹；`/dump AutoSpellQueue` 看全局名 | 无重名文件夹；`_G.AutoSpellQueue` 未被占用 |
| 7 | 商标 / 合规 | 名称是否暗示官方 | 名称不得以 `Blizzard` / `WoW` 开头，不含 `official` 等暗示词 | 描述性组合词，已满足 |
| 8 | 旧名去向 | 旧项目页处置 | CurseForge / WoWI / GitHub 上找到旧项目页 | 旧页面顶部加一行「Renamed to AutoSpellQueue」，停止更新 |

**若 `AutoSpellQueue` 已被占用**：不要用近似拼写绕过（`AutoSpellQueuee`、`Auto-SpellQueue`），
按 §1.2 换一个描述性备选名；**换名要趁发布前决定**，发过之后再改就是第二次破坏性变更。
换名成本：文件夹名 + `.toc` 文件名 + 5 个 `.lua` 前缀 + SavedVariables 名 + 全部文档 + `.pkgmeta` 的 `package-as`。

**备选名（按优先级，选之前逐个查 §1.1）**：`SpellQueueTuner` · `AutoQueueWindow` · `SpellQueueAuto` · `SmartSpellQueue`。
选择标准三条：**描述性（不接受缩写——`ASQ` 这种正是本次更名要摆脱的）** + 五平台均未占用 + 不含厂商商标。

**检查记录（执行时填写）**

| 平台 | 查询词 / URL | 结果 | 日期 | 证据链接 |
|---|---|---|---|---|
| CurseForge | | | | |
| Wago | | | | |
| WoWInterface | | | | |
| GitHub | | | | ✅ 2026-09-28 已改名 |
| 游戏内 AddOns | | | | |

## 2. 商店页素材

数量为最低要求；**具体尺寸以提交时平台页面的实际要求为准**。

| # | 素材 | 规格 | 数量 | 状态 | 备注 |
|---|---|---|---|---|---|
| 1 | Logo / 项目头像 | 512×512 PNG | 1 | 待制作 | 建议用 `.toc` 的 `IconTexture` 图标做底 + 插件名；深底 + 主色 `#0cd29f`（与标题/聊天前缀一致） |
| 2 | 截图 | ≥ 1280×720（建议 1920×1080） | ≥ 3 | 待制作 | 建议：① 主区域状态卡（当前/目标/延迟/场景/算式）② 高级区 ③ 悬浮状态条 + tooltip ④ 战斗中 `pending` ⑤ `/asq status` 输出。截图里不要出现他人角色名 |
| 3 | 简介 Summary | 单段 | en + zhCN | ✅ [`DESCRIPTION.md`](DESCRIPTION.md) 末节「商店页短简介」 | 第一句必须说清「只改本地 CVar、不自动施法」 |
| 4 | 详细描述 | Markdown/HTML | en + zhCN | ✅ [`DESCRIPTION.md`](DESCRIPTION.md)（中英各自独立成篇） | 必查清单见下 |
| 5 | 分类 | WoW 类目 | 1 | 建议 **Combat** | 与 `.toc` 的 `## Category` 必须一致 |
| 6 | 标签 | 3–6 个 | — | 建议 `spell queue`、`latency`、`cvar`、`quality of life`（中文加 `施法队列`） | **不要**用 `automation` / `bot` / `macro` / `script` 这类会被误判的词 |
| 7 | 游戏版本 | 平台勾选 | — | Retail 12.x（对齐 `.toc` 的 Interface 列表） | 每次补丁后更新，见 §7.4 |
| 8 | 依赖 | — | — | 无必需；`LibSharedMedia-3.0` 标 Optional | 标成 Required 会强制用户装库 |

**详细描述必查清单**（提交前对照 `DESCRIPTION.md` 逐条确认）：

```
一句话介绍（第一句：只改本地 CVar、不自动施法）
它做什么 / What it does        —— 一个 CVar、基础值 + 延迟自适应 + 场景、15 秒重算
它不做什么 / What it does NOT  —— 不自动化、不联网、无遥测；你自己也能 /console 改
安装 / Install                 —— 解压到 AddOns\AutoSpellQueue\
升级 / Upgrading               —— 先删旧 Tate_ASQ；保留旧设置需复制 SavedVariables 文件
所有权与恢复 / Ownership       —— 只在仍是自己的值时归还；外部改值不覆盖；登出归还；写入读回校验
命令 / Commands                —— /asq、/asq status、/asq reset、/asq unlock
已知限制 / Limitations         —— 战斗中不写（脱战后生效）；延迟读数约 30 秒刷新，数值最多滞后几十秒
语言 / Languages               —— enUS / zhCN / zhTW（其他回退英文）
许可证与反馈 / License          —— MIT © 2026 Tate Chen；GitHub Issues 或项目页评论
```

素材源文件放仓库外或 `docs/media/`（`docs/` 已被 `.pkgmeta` ignore，不会进发布包，但注意仓库体积）。

## 3. 版本与渠道策略

- 版本号 `x.y.z`，与 `.toc` 的 `## Version`、`CHANGELOG.md` 顶部条目三处一致；git tag 用 `vX.Y.Z`。
- 渠道映射：`x.y.z` → **Release**；`x.y.z-beta.N` → **Beta**；`x.y.z-alpha.N` → **Alpha**。
- 破坏性变更（改 SavedVariables、改文件夹名、改默认行为）**必须**进 `CHANGELOG.md` 的「升级须知」并在商店页提示。
- 补丁适配只改 `.toc` 的 Interface 与描述里的游戏版本，`x.y.(z+1)` 即可，不必跳大版本。

## 4. 打包

### 4.1 硬性约束（两种方式都必须满足）

1. zip 根目录**正好**是 `AutoSpellQueue/`（文件夹名 == `.toc` 文件名）。
2. 只含 **6 个运行期文件**（1 `.toc` + 5 `.lua`）；`tests/`、`tools/`、`docs/`、`.github/`、`node_modules/` 一律不进包。
3. `.toc` 的 `## Version` 与本次发布版本一致。
4. 发布候选引用**逐条目内容 sha256**（跨打包器/时区/压缩等级都稳定）；zip 自身哈希只作同一脚本产出的快速校验。

### 4.2 方式 A：本地打包（首选，零外部依赖）

```powershell
pwsh tools/verify.ps1 -Package     # 语法 → 单测 → 结构/版本 → 打包
# 产物：dist/AutoSpellQueue-<version>.zip（dist/ 与 *.zip 已在 .gitignore）
```

`tools/package.ps1` 会：逐条比对 zip 内容与工作区文件、断言每条目的墙钟时间等于固定常量、
自检「同内容再打一份哈希一致」；任一失败**删除产物**并 exit 1。

### 4.3 方式 B：BigWigs packager（CI 自动化，需要时再建）

已在仓库根放置 `.pkgmeta`（`package-as: AutoSpellQueue`，ignore 开发文件）。上传到 CurseForge 需要：

1. 在 `.toc` **新增** `## X-Curse-Project-ID: <真实项目 ID>` 指令（当前没有这一行，只有 `## X-Website`）。
   注意 `.toc` **没有注释语法**，任何占位写法都是非法值指令——拿到真实 ID 之前不要写占位行。
2. GitHub 仓库 Secrets 里配置 `CF_API_KEY`（值只存在 Secrets，不写进任何文件）。
3. GitHub Actions 调用 `BigWigsMods/packager@v2`，tag 形如 `vX.Y.Z`。

### 4.4 CI 配置（需要时再建；只写 secret 名称）

```
触发：push tag v*.*.*
步骤：checkout → 安装 tools 依赖 → node tools/check-syntax.mjs → node tools/run-tests.mjs
      → BigWigsMods/packager@v2（CF_API_KEY / WAGO_API_TOKEN / WOWI_API_TOKEN 只从 Secrets 读）
```

本地门禁与 CI 用同一组命令，保证「本地过 = CI 过」。

## 5. 合规

- **不自动化游戏行为**：插件只读写一个本地 CVar，不施法、不代按键、不读战斗日志做决策。
- **免费**：不收费、不内嵌广告、不做捐赠门槛功能。
- **无数据外传**：无网络请求、无遥测；采集的仅是本地游戏状态（专精、延迟、CVar 值）。
- **不改客户端文件**：只通过公开 API 读写设置。
- 商店页措辞避开 `automation` / `bot` / `cheat`，并明确写「你可以自己用 `/console SpellQueueWindow` 改同一个值」。
- 名称不含厂商商标，不暗示官方背书。

## 6. 发布前检查单

**代码与门禁**

- [ ] `node tools/check-syntax.mjs` → 12 个文件通过（语法 0 错、双兼容 lint 0 错）
- [ ] `node tools/run-tests.mjs` → 全部用例通过（贴出真实输出）
- [ ] `pwsh tools/verify.ps1` → PASS
- [ ] `pwsh tools/verify.ps1 -Package` → zip 内容 6 个文件、根目录 `AutoSpellQueue/`
- [ ] 游戏内冒烟：加载无 Lua 报错、面板能开、`/asq status` 有输出、`/dump GetCVar("SpellQueueWindow")` 与目标值一致、战斗中关插件显示「等待脱战」且脱战后归还
- [ ] `CHANGELOG.md` 有本次版本条目且中英双语齐全；`README.md` 版本行已更新

**商店页**

- [ ] 文案取自 [`DESCRIPTION.md`](DESCRIPTION.md)，必查清单（§2）逐条覆盖
- [ ] 第一句就是「只改本地设置、不自动施法」
- [ ] 分类与 `.toc` 的 `## Category` 一致；标签不含 automation 类词
- [ ] 游戏版本勾选与 `.toc` 的 Interface 一致
- [ ] Logo / 截图已备齐，截图无他人角色名
- [ ] `.toc` 已新增 `## X-Curse-Project-ID: <真实 ID>`

**发布动作**

- [ ] `git tag vX.Y.Z && git push origin vX.Y.Z`（或手动上传 zip）
- [ ] Release 说明使用 `CHANGELOG.md` 对应段（或 `docs/DESCRIPTION.md`）
- [ ] 旧项目页（若有）标注已更名

## 7. 发布后

### 7.1 冒烟（发布后 30 分钟内）

下载自己发布的 zip → 装到干净的 `AddOns` → 进游戏确认 §6 的游戏内冒烟清单。
确认包内**没有** `tests/`、`tools/`、`docs/`。

### 7.2 回滚

发现严重问题：CurseForge 页面把上一版标记为 Release（或删除新文件），
GitHub 上 `git revert` 后打 `vX.Y.(z-1)` 的新 tag 重新发——**不要**移动已发布的 tag。

### 7.3 Issue 追踪

CurseForge 评论 + GitHub Issues 双入口；报告里要求附 `/asq status` 输出与客户端版本。

### 7.4 补丁兼容流程

1. 客户端更新后，先改 `.toc` 的 `## Interface`（新构建号加入列表，旧的可保留）。
2. 跑完整门禁；若 API 有变，先修 `AutoSpellQueue_CVar.lua`（唯一接触 CVar 的地方），再补测试。
3. 按 §3 升 `x.y.(z+1)` 发版；`CHANGELOG.md` 写一句「适配 12.x.y」。

## 8. 许可证

当前 **MIT**（见 [`../LICENSE`](../LICENSE)），适合插件生态、与同类插件一致、不限制他人复用代码。
若改为 GPL：只需替换 `LICENSE` 全文并在商店页与 `README` 同步声明；**已发布的版本无法追溯改许可**，
所以要在第一次发布前决定。发布前若你倾向其它许可，改完跑一次门禁即可（门禁不校验许可证文本）。
