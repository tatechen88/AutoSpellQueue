# 文档地图

> 本目录是这套文档的**导航与规则**。重写于 2026-09-28（v2.0.0）。
> 如果你只想改一处事实，先看下表确认「它归谁管」——**每个事实只允许有一个出处**。

## 一览

| 文档 | 读者 | 它唯一负责的内容 | 它不负责 |
|---|---|---|---|
| [`../README.md`](../README.md) | 拿到仓库的人（玩家或开发者） | 这是什么、安装/升级、一分钟上手、指向其它文档 | 不复述玩家长文、不复述发布流程 |
| [`DESCRIPTION.md`](DESCRIPTION.md) | **玩家**（也是商店页 / 发布说明的文案源） | 中文全文 + English 全文 + 商店页短简介 | 不含开发细节、不含发布流程 |
| [`../CHANGELOG.md`](../CHANGELOG.md) | 玩家 + 开发者 | 版本历史（中英双语，每版：玩家可见变化 → 修复 → 升级须知） | 不含「如何发布」 |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 开发者 | 文件与加载顺序、接口契约、状态机不变量、测试与打包约定 | 不含玩家说明 |
| [`CURSEFORGE.md`](CURSEFORGE.md) | 发布者 | 发布规划与操作手册：命名检查、素材、打包、合规、checklist、发布后流程 | 文案正文在 `DESCRIPTION.md` |
| [`../HANDOFF.md`](../HANDOFF.md) | 接手的 agent / 新会话 | 当前状态、如何验证、**待游戏内验证清单**、下一步 | 不重复 README 的安装步骤 |
| [`../AGENTS.md`](../AGENTS.md) | 自动化 agent | 验证门禁命令、仓库硬约定 | 保持极简 |
| [`../tests/REGRESSIONS.md`](../tests/REGRESSIONS.md) | 开发者 | 已修缺陷与必须保持的不变量、测试未覆盖清单 | 不复述用法 |
| [`agents/`](agents/) | 工程技能（SkillsHub） | 技能如何消费本仓的 domain 文档与 issue tracker 约定 | **上游约定，不随本项目改写** |

## 三条规则

1. **唯一出处**：上表「唯一负责的内容」里的事实，只写在该文档。其它地方要提，就写一句并给出链接。
   典型：`SpellQueueWindow` 的取值公式只在 `ARCHITECTURE.md` 里写全，`DESCRIPTION.md` 只做玩家向解释。
2. **不写会烂的数字**：版本号只从 `AutoSpellQueue.toc` 读；测试数量、包体积、哈希这类每次改动都会变的，
   写「怎么取」（跑哪条命令）而不是写死数值。**唯一例外**是 `CHANGELOG.md` 的历史条目。
3. **不写没验证过的话**：凡是推测，标「待验证」并挂到 `HANDOFF.md` 的清单；凡是没能实际跑过的命令，
   不要写成「已验证」。门禁要求贴真实输出（见 `AGENTS.md`）。

## 常见改动该动哪几个文件

| 你改了什么 | 必须同步 |
|---|---|
| 加了/改了设置项、命令、默认值 | `ARCHITECTURE.md`（契约）→ `README.md` 表格 → `DESCRIPTION.md`（玩家措辞）→ `CHANGELOG.md` |
| 修了缺陷 | `tests/REGRESSIONS.md` 加不变量 + 对应测试用例 → `CHANGELOG.md` |
| 升级了 `.toc` 的 `## Version` | `CHANGELOG.md` 先写条目 → `README.md` 版本行 → 跑 `pwsh tools/verify.ps1` |
| 改了发布包内容或目录结构 | `ARCHITECTURE.md` §发布包 → `CURSEFORGE.md` §打包 → `tools/package.ps1` 的清单 |
| 改了文件结构 / 新增文件 | `docs/README.md` 本表 → `AGENTS.md`（若有新约定） |
