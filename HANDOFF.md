# HANDOFF

> 给接手本仓库的下一个 agent 或新会话。**最后重写：2026-09-28**（v2.0.0，已提交并推送）。
> 玩家向说明见 [`docs/DESCRIPTION.md`](docs/DESCRIPTION.md)；开发契约见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## 这是什么

**AutoSpellQueue** —— 魔兽世界正式服（12.x）插件，自动维持 `SpellQueueWindow`。
5 个 `.lua` + 1 个 `.toc`，不是可独立运行的程序；判定标准是**游戏内加载后行为正确**。

## 当前状态

| 项 | 值 |
|---|---|
| 版本 | 2.0.0（`.toc` 的 `## Version` 是唯一权威） |
| 仓库 | `https://github.com/tatechen88/AutoSpellQueue`（2026-09-28 由 `Tate_ASQ` 改名，改名前需先解归档） |
| 分支状态 | `main` 与 origin 同步，工作区干净 |
| 本地门禁 | 语法（12 文件）→ 单测（128 用例 / 1206 断言）→ 结构/版本 → 打包，全绿 |
| 本机安装 | 已装入 `D:\Game\World of Warcraft\_retail_\Interface\AddOns\AutoSpellQueue`（6 文件，与仓库逐文件哈希一致） |
| 旧插件 | 已移出扫描路径 → `Interface\AddOns.disabled\Tate_ASQ`（备份，可删） |
| 旧存档 | 已复制为 `WTF\Account\671932030#1\SavedVariables\AutoSpellQueue.lua`，原文件存为 `Tate_ASQ.lua.pre-v2.bak` |
| 尚未做 | **游戏内实测**、**打 tag / 发 Release**、**CurseForge 上传** |

## 怎么验证（贴真实输出，别写「应该没问题」）

```powershell
npm --prefix tools install       # 一次性；本机没有 lua/luac，测试用 Node + fengari
node tools/check-syntax.mjs      # luaparse(5.1) + 5.1/5.3 双兼容 lint
node tools/run-tests.mjs         # 假客户端里真跑 5 个运行期文件
pwsh tools/verify.ps1            # 语法 → 单测 → 结构/版本一致性
pwsh tools/verify.ps1 -Package   # 追加 dist/AutoSpellQueue-<version>.zip
```

失败排查顺序：语法 → `tests/spec_*.lua` 里失败的用例 → `tests/wow_stub.lua` 的环境建模是否与真实客户端一致。

## 必须保持的不变量

写入必须读回校验、所有权只在仍是自己的值时归还、战斗中不写也不重放旧目标、登出归还、
未来 schema 不降级。完整列表与对应测试见 [`tests/REGRESSIONS.md`](tests/REGRESSIONS.md)——**改动前先读它**。

## 待游戏内验证（只有真人客户端能确认）

- [ ] 加载无 Lua 报错；`/asq` 能开面板、能滚动、高级区能展开
- [ ] `/dump GetCVar("SpellQueueWindow")` 等于面板上的目标值
- [ ] `C_CVar.GetCVarInfo("SpellQueueWindow")` 的 `isSecure` / `isReadOnly` 实际取值（决定写入是否可能被拒）
- [ ] `GetNetStats()` 的真实刷新间隔是否与「约 30 秒」相符
- [ ] 城市场景判定：主城 / 中立城 / 副本入口子地图（`IsCityMap` + 上溯 4 层是否够）
- [ ] 状态条拖动在真实 UI 缩放下的坐标是否正确；tooltip 排版；`LibSharedMedia` 缺失时的字体回退
- [ ] 三语在真实字体下的换行与截断（enUS / zhCN / zhTW 各看一遍）
- [ ] 战斗中关插件 → 显示「等待脱战」→ 脱战后值回到原值
- [ ] 冒烟后确认 `WTF\...\SavedVariables\AutoSpellQueue.lua` 里 `Tate_ASQDB` 已被清空
- [ ] 专精基础值表是**调参默认值**，不是实测数据；按体感调整不算 bug

## 下一步

1. **游戏内跑一遍上面的清单**（本机已安装，直接上号）。有问题把 `/asq status` 的输出贴回来。
2. 确认无误后发版：
   `gh release create v2.0.0 dist/AutoSpellQueue-2.0.0.zip --title "v2.0.0" --notes-file CHANGELOG.md`
   （在此之前**不要**发，避免发布未经游戏内验证的构建。）
3. 走 [`docs/CURSEFORGE.md`](docs/CURSEFORGE.md)：§1 命名检查 → §2 素材 → 创建项目 → 在 `.toc`
   **新增** `## X-Curse-Project-ID: <真实 ID>` → 按 §4 打包上传。
4. 文档改动请遵守 [`docs/README.md`](docs/README.md) 的「唯一出处」规则。

## 已知边界

- opt 面板的真实渲染（Blizzard Settings 画布、滚动、tooltip、字体）无法离线验证。
- 测试覆盖逻辑与文本，不覆盖真实渲染；独立回退窗口（无 Settings API 时的路径）未跑。
- 旧存档导入依赖玩家手动复制文件（见 `ARCHITECTURE.md` §4「SavedVariables 与迁移前提」），
  这是客户端机制决定的，不是 bug。
