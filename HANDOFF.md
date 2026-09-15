# HANDOFF

> 交接说明：给接手本仓库的下一个 agent 或新 session。最后更新 2026-09-15。

## 这是什么

**Tate's AutoSpellQueue** —— 魔兽世界正式服（12.x）插件。三个 Lua 文件加一个 `.toc` 清单，属于游戏内加载的插件包，不是可独立运行的程序。

## 快速上手

| 事项 | 做法 |
|---|---|
| 本地安装 | 把整个目录放进 `World of Warcraft\_retail_\Interface\AddOns\`，重启客户端 |
| 验证 | **本仓无自动化门禁**。声明完成前必须贴出你实际运行的命令与输出：游戏内加载并确认无 Lua 报错（`/console scriptErrors 1`），如有 Lua 工具链可先跑 `luac -p *.lua` 做语法检查 |
| 版本记录 | `CHANGELOG.md` |
| issues / specs | `docs/agents/issue-tracker.md`——本地 markdown tracker，放在 `.scratch/<feature>/` |

## 最近在做什么

```
9e86803 2026-09-15 chore: 接入 SkillsHub 工程流程约定
bcc9c24 2026-08-29 Fix README download link text to v1.0.2
d882f41 2026-08-29 v1.0.2 version update
f604d56 2026-08-29 Add English README section
```

最近的实质变更是 v1.0.2 版本更新与 README 中英双语补齐。

## 关键文件

- `Tate_ASQ.lua`——主逻辑（队列与施法）
- `Tate_ASQ_Formula.lua`——公式 / 优先级计算
- `Tate_ASQ_Options.lua`——设置界面
- `Tate_ASQ.toc`——插件清单（版本号、加载顺序、元数据）
- `CHANGELOG.md`、`README.md`（中英双语）

## 接手时先读

1. `README.md`（功能与安装说明）
2. `CHANGELOG.md`（版本演进）
3. `AGENTS.md`（`## Agent skills` 的 verify 条款）
4. `docs/agents/issue-tracker.md` 与 `docs/agents/domain.md`
