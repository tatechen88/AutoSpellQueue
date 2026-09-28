# AutoSpellQueue

自动把《魔兽世界》正式服的**施法队列窗口**（`SpellQueueWindow`）保持在适合你专精与网络延迟的值，
并在它不再管理这个设置时，**把你自己原来的值还回去**。

> 正式服 12.x（12.0.0–12.1.5）· v2.0.0 · MIT · 语言 enUS / zhCN / zhTW
> 原名 `Tate_ASQ`（Tate's AutoSpellQueue），v2.0.0 起更名为 **AutoSpellQueue**。

**📖 玩家请直接看 [`docs/DESCRIPTION.md`](docs/DESCRIPTION.md)**（中文 + English 两版全文：这值是什么、
为什么默认 400 让人难受、谁受益、怎么确认它在工作、它不做什么）。
README 只保留「装、跑、验证」这类实用信息。

---

## 装

1. 下载 [Releases](https://github.com/tatechen88/AutoSpellQueue/releases) 里的 zip。
2. 解压到 `World of Warcraft\_retail_\Interface\AddOns\`，得到 `AddOns\AutoSpellQueue\`。
3. 进游戏。**默认就是开着的，不需要配置。**

设置入口：游戏内 **选项 → 插件 → AutoSpellQueue**，或 `/asq`，或左键点悬浮状态条。

### 从旧版 `Tate_ASQ` 升级

1. **删掉旧的 `AddOns\Tate_ASQ` 文件夹**（新旧会争抢同一个 CVar）。
2. 想保留旧设置的话，把
   `WTF\Account\<账号>\SavedVariables\Tate_ASQ.lua` 复制一份并改名为同目录的 `AutoSpellQueue.lua`。
   客户端**只加载与插件文件夹同名的存档文件**，不复制就回到默认设置（也能用）。

## 一分钟上手

| 我想…… | 怎么做 |
|---|---|
| 看现在的值 | `/dump GetCVar("SpellQueueWindow")` |
| 看它为什么是这个值 | `/asq` → 状态卡里有完整算式 |
| 看诊断 | `/asq status` |
| 临时全关、把值还给我 | `/asq` 里关掉总开关（战斗中点会等到脱战） |
| 状态条跑到屏幕外了 | `/asq unlock` |

## 它不做什么

不自动施法、不代按键、不做输出循环、不读战斗日志、不联网、无遥测。
它改的就是**你自己也能用 `/console SpellQueueWindow 200` 改的那个数字**。

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
node tools/run-tests.mjs        # 假客户端里跑 Formula / CVar / Core / Locale / Options
pwsh tools/verify.ps1           # 语法 → 单测 → 结构/版本一致性
pwsh tools/verify.ps1 -Package  # 追加：dist/AutoSpellQueue-<version>.zip
```

**跑不过就是没做完**，交付时要贴真实输出（`AGENTS.md` 的硬要求）。

### 仓库结构

```
AutoSpellQueue.toc            # 插件清单（版本号唯一权威出处）
AutoSpellQueue_Locale.lua     # 136 个键 × enUS/zhCN/zhTW（同一张源表生成）
AutoSpellQueue_Formula.lua    # 纯计算：专精/延迟/场景 → 目标值（无 WoW API）
AutoSpellQueue_CVar.lua       # 唯一读写 SpellQueueWindow 的地方（写入带读回校验）
AutoSpellQueue.lua            # 配置校验与迁移、所有权状态机、事件与定时刷新
AutoSpellQueue_Options.lua    # 设置面板、悬浮状态条、斜杠命令
tests/ tools/                 # 本地门禁（不进发布包）
docs/                         # 文档（不进发布包）
```

发布包只含 `AutoSpellQueue/` 下的 **6 个运行期文件**（1 个 `.toc` + 5 个 `.lua`），
由 `tools/package.ps1` 保证；结构与指纹规则见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## 许可证

MIT，见 [`LICENSE`](LICENSE)。反馈走 [GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues)。
