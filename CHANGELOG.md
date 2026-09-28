# Changelog

> 版本号以 `AutoSpellQueue.toc` 的 `## Version` 为唯一权威，本文件必须与它一致（`pwsh tools/verify.ps1` 会检查）。
> **从 v2.0.0 起，每个版本都提供中文与 English 两版**：先写玩家能感觉到的变化，再写工程细节。
> 发布日期为 ISO 格式；未发布版本的日期是代码冻结日期。

---

## v2.0.0 — 2026-09-28

> 尚未对外发布。发布规划见 [`docs/CURSEFORGE.md`](docs/CURSEFORGE.md)，玩家向全文见 [`docs/DESCRIPTION.md`](docs/DESCRIPTION.md)。

### 中文

#### 玩家能感觉到的变化

- **换名字了**：`Tate_ASQ` → **AutoSpellQueue**，插件文件夹名同步改变（升级步骤见下）。
- **装上就能用**：设置页从一整页选项精简为「总开关 + 状态卡 + 折叠的高级设置」。状态卡直接给出当前值、目标值、延迟、场景，以及**这个数字是怎么算出来的**。
- **它真的会跟着网速走**：以前只在换地图 / 切专精时算一次，延迟变了也不会更新；现在**每 15 秒重算一次**（客户端自己的延迟读数约 30 秒刷新一次，所以最坏情况滞后几十秒）。
- **界面不再说谎**：写不进去就显示「写入失败」和原因，而不是显示一个其实没生效的数字。失败 / 不可用 / 关闭这三种状态下，悬浮状态条只显示状态名，不显示任何数字。
- **战斗中关插件会等脱战**：战斗中一律不写 CVar；关闭也会显示「等待脱战」，脱战后才把你的原值还回去。
- **中英繁三语完整文案**：英文客户端不再看到 `STATE_APPLIED` 这类内部键名（上一版的问题）。

#### 修复（来自代码审查）

1. **写入不再「假成功」** —— 只有「API 没有拒绝」**且**「读回的值与目标一致」才算写入成功。旧版把「`pcall` 没抛错」当成成功，界面会显示一个并未生效的值。
2. **所有权跨重载不再丢失** —— 接管前你自己的值会被记录并写入存档；`PLAYER_LOGOUT` 归还；万一归还失败，记录仍在，下次登录还能归还。
3. **战斗中的待办不再冲突** —— 删除了「脱战后要重放的旧目标」。脱战瞬间重新读取实时状态再决策，不会把战斗前的旧值硬套上去；这条对「应用」和「归还」一视同仁。
4. **延迟变化会重算** —— 启用期间每 15 秒一次；登录后按 2 / 5 / 10 / 20 / 40 秒补算，直到客户端能报出非零延迟。
5. **配置会校验** —— 存档里越界的值、错误类型、颠倒的上下限、坏掉的所有权记录都会被修正回默认并计数；**比当前版本更新的存档不会被降级改写**。
6. **UI 精简与诚实化** —— 见上；另外面板不可见时不再刷新，控件树只构建一次。
7. **新增本地验证门禁与可复现打包** —— 语法检查、128 个用例 / 1206 条断言的单元测试、结构与版本一致性检查、打包内容校验，一条命令跑完。

#### 升级须知（破坏性变更）

- **必须先删除旧的 `AddOns\Tate_ASQ` 文件夹**：新旧是两个独立插件，会争抢同一个 CVar。
- **存档变量改名**：`Tate_ASQDB` → `AutoSpellQueueDB`。
- **想保留旧设置需要手动做一步**：客户端**只加载与插件文件夹同名的存档文件**，旧设置写在
  `WTF\Account\<账号>\SavedVariables\Tate_ASQ.lua` 里，删掉旧插件后没有任何东西会读它。
  把该文件复制 / 改名为同目录下的 `AutoSpellQueue.lua` 即可自动导入；不复制也能用，只是回到默认设置。

#### 其他

- 错误不再静默：写入 / 读取失败一定会在聊天框提示一次（同一条错误 120 秒内不重复刷屏）。
- 「重置全部设置」现在也会清掉悬浮状态条的位置。
- 新增斜杠命令：`/asq`、`/asq status`、`/asq reset`、`/asq unlock`。
- 新增 `docs/ARCHITECTURE.md`、`docs/CURSEFORGE.md`、`docs/DESCRIPTION.md`、`docs/README.md`（文档地图）、`LICENSE`(MIT)、`.pkgmeta`。

### English

#### What you will actually notice

- **New name**: `Tate_ASQ` → **AutoSpellQueue**, and the addon folder changed with it (see "Upgrading" below).
- **Works out of the box**: the options page went from a wall of settings to *master switch + status card + (collapsed) advanced*. The card shows the current value, target, latency, context, and **how the number was derived**.
- **It actually follows your connection now**: it used to recalculate only on zone / spec changes, so a latency shift never reached the value. It now **re-evaluates every 15 seconds** (the client's own latency reading refreshes roughly every 30 s, so worst case you are a few tens of seconds behind).
- **The UI stopped lying**: a failed write shows "write failed" plus the reason instead of a believable number that was never applied. While failed / unavailable / disabled, the floating bar shows the state name only — never a number.
- **Disabling in combat waits**: it never writes the CVar during combat, and disabling mid-fight shows "waiting" until combat ends before restoring your value.
- **Full enUS / zhCN / zhTW copy**: English clients no longer see internal key names such as `STATE_APPLIED` (a bug in the previous build).

#### Fixes (from the code review)

1. **No more "fake success" writes** — a write counts only when the API did not reject it **and** reading the value back matches the target. The old build treated "no exception raised" as success and displayed a value that was never applied.
2. **Ownership survives reloads** — the value you had before the addon took over is recorded and persisted; `PLAYER_LOGOUT` gives it back, and if that write fails the record still lets the next session restore it.
3. **No more combat-pending conflicts** — the cached "target to replay after combat" is gone. The moment combat ends, live state is re-read and the decision is made again, so a pre-combat value cannot be forced onto the client. The same rule covers applying and restoring.
4. **Latency changes are re-evaluated** — every 15 s while enabled, plus a 2 / 5 / 10 / 20 / 40 s warm-up after login until the client reports a non-zero latency.
5. **Settings are validated** — out-of-range values, wrong types, inverted min/max and broken ownership records are repaired and counted; a save written by a **newer** schema is never downgraded.
6. **Leaner, honest UI** — see above; the panel no longer refreshes while hidden, and the widget tree is built once.
7. **New local verification gate + reproducible packaging** — syntax check, 128 unit cases / 1206 assertions, structure and version consistency, package content validation — one command.

#### Upgrading (breaking changes)

- **Delete the old `AddOns\Tate_ASQ` folder first**: old and new are separate addons that fight over the same CVar.
- **SavedVariables renamed**: `Tate_ASQDB` → `AutoSpellQueueDB`.
- **Keeping your old settings takes one manual step**: the client only loads a SavedVariables file named after the addon folder, and the old settings live in `Tate_ASQ.lua`. Copy
  `WTF\Account\<your account>\SavedVariables\Tate_ASQ.lua` → `AutoSpellQueue.lua` in the same folder. Without that copy the addon starts from the defaults.

#### Other

- Errors are no longer silent: write / read failures always print once in chat (the same reason is throttled to once per 120 s).
- "Reset all settings" now also clears the floating bar's saved position.
- New slash commands: `/asq`, `/asq status`, `/asq reset`, `/asq unlock`.
- New docs: `docs/ARCHITECTURE.md`, `docs/CURSEFORGE.md`, `docs/DESCRIPTION.md`, `docs/README.md` (doc map), `LICENSE` (MIT), `.pkgmeta`.

---

## v1.0.2

**中文** — 设置页开关改为滑块式 UI，页面更精简；新增「显示状态条」开关；README 新增繁中与英文说明；下载链接更新到 v1.0.2。

**English** — Toggle switches in the options page; new "Show status bar" option; README gained Traditional Chinese and English sections; download link bumped to v1.0.2.

## v1.0.1

**中文** — 修复状态条位置记忆（保存完整锚点，登录后正确恢复）；位置受屏幕边界约束；精简界面词条与无用函数；README 加入下载链接。

**English** — Fixed status bar position memory (full anchor saved and restored on login); position clamped to the screen; trimmed strings and dead functions; download link added to the README.

## v1.0.0

**中文** — 首个发布版本：依职业 / 专精基础值自动调整 `SpellQueueWindow`；城市 / 副本 / 野外使用不同算法；World 延迟优先、Home 回退；悬浮状态条可拖动、左键打开设置；中英自动切换。

**English** — First release: automatic `SpellQueueWindow` tuning from a per-spec base value; different rules for cities / instances / open world; World latency first with Home fallback; draggable floating bar that opens settings on left-click; zhCN/zhTW/enUS support.
