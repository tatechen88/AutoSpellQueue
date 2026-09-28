## Agent skills

### verify

本仓库有本地门禁。**任何任务在声明完成之前，必须实际运行并贴出命令输出**——输出才是证据，断言「已经做完」不算。

```powershell
npm --prefix tools install     # 一次性：安装本地验证工具链（luaparse / fengari）
node tools/check-syntax.mjs    # luaparse(5.1) 解析仓库内全部 .lua
node tools/run-tests.mjs       # fengari(5.3) 执行 tests/run.lua
pwsh tools/verify.ps1          # 一条命令：语法 → 单测 → 结构与版本一致性
pwsh tools/verify.ps1 -Package # 追加打包：dist/AutoSpellQueue-<version>.zip
```

要求：

- 改动 `.lua` 后至少跑 `node tools/check-syntax.mjs` 与 `node tools/run-tests.mjs`；动到文件结构、版本号或发布包内容时跑 `pwsh tools/verify.ps1`。
- 提交说明/交接里要带上**真实输出**（含失败信息），不要只写「测试通过」。
- 本机没有 `lua` / `luac`；不要用「我目测语法没问题」代替这一步。

### 仓库约定

- `docs/ARCHITECTURE.md` 是接口冻结文档：**改接口先改它**，再改代码。
- 发布包只含 6 个运行期文件（1 个 `.toc` + 5 个 `.lua`），zip 根目录必须正好是 `AutoSpellQueue/`；`tests/`、`tools/`、`docs/` 不进包。
- 代码必须同时兼容 Lua 5.1（客户端）与 Lua 5.3（测试运行器）：不使用 `goto`、整除 `//`、位运算符、`table.unpack`。
- 不提交任何密钥；CI 只引用 secret 名称（如 `CF_API_KEY`），值只存在于 GitHub Secrets。
