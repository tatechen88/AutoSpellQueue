# AGENTS.md — 本仓库给自动化 agent 的规则

> 规则尽量少，但都是硬的。文档分工见 [`docs/README.md`](docs/README.md)。

## verify

本仓库有本地门禁。**任何任务在声明完成之前，必须实际运行并贴出命令输出**——输出才是证据，
「我看过了 / 应该没问题」不算。

```powershell
npm --prefix tools install     # 一次性：安装本地验证工具链（luaparse / fengari）
node tools/check-syntax.mjs    # luaparse(5.1) 解析全部 .lua + 5.1/5.3 双兼容 lint
node tools/run-tests.mjs       # fengari(5.3) 里真跑 5 个运行期文件（tests/spec_*.lua）
pwsh tools/verify.ps1          # 一条命令：语法 → 单测 → 结构与版本一致性
pwsh tools/verify.ps1 -Package # 追加打包：dist/AutoSpellQueue-<version>.zip
```

- 改动 `.lua` 后至少跑前两条；动到文件结构、版本号或发布包内容时跑 `verify.ps1`。
- 提交说明 / 交接里要带上**真实输出**（含失败信息），不要只写「测试通过」。
- 本机**没有** `lua` / `luac`；不要用「我目测语法没问题」代替这一步。
- 改完 `.lua` / `.toc` 之后**记得重新安装到游戏目录**（路径与步骤见 `HANDOFF.md`）。

## 仓库约定

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) 是接口冻结文档：**改接口先改它**，再改代码。
- **每个事实只有一个出处**：该写哪份文档见 [`docs/README.md`](docs/README.md) 的表格，别在多处各写一份。
- 发布包只含 7 个运行期文件（1 个 `.toc` + 6 个 `.lua`），zip 根目录必须正好是 `AutoSpellQueue/`；
  `tests/`、`tools/`、`docs/` 不进包。这条由 `tools/package.ps1` 强制。
- **加设置项之前先看 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) §3**：玩家只该决定 `enabled` 与 `showStatus`。
  能量化的（延迟、抖动）写成算法，能定死的写成常量，确有异议的走 `/asq` 命令。
  `tests/spec_core.lua` 的「配置白名单」用例会拦住悄悄长回来的设置。
- 代码必须同时兼容 Lua 5.1（客户端）与 Lua 5.3（测试运行器）：不使用 `goto`、整除 `//`、
  位运算符、`table.unpack`、`setfenv`、`loadstring`、`math.mod`、`newproxy`（lint 会拦）。
- **不写会烂的数字**：版本号只从 `.toc` 读；测试数量、包体积、哈希这类改成「用哪条命令取」。
- 不提交任何密钥；CI 只引用 secret 名称（如 `CF_API_KEY`），值只存在于 GitHub Secrets。
- 版本号改动顺序：先写 `CHANGELOG.md` 条目（简体 / 繁體 / English 三语）→ 再改 `.toc` → 再跑 `verify.ps1`。
