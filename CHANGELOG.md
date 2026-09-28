# Changelog

> **从 v2.0.0 起，每个版本都提供中文与 English 两版说明。**
> 中文部分先给「玩家能感觉到的变化」，再列工程细节；English 部分结构相同、独立成篇。
> Since v2.0.0 every entry ships in both 中文 and English: player-visible changes first, engineering details after.
>
> 版本号与 `AutoSpellQueue.toc` 的 `## Version` 必须一致（`tools/verify.ps1` 会检查）。日期为 ISO 格式。

---

## v2.0.0 — 2026-09-28

> 尚未对外发布，日期为代码冻结日期；发布规划见 [`docs/CURSEFORGE.md`](docs/CURSEFORGE.md)。
> Player-facing pitch: [`docs/DESCRIPTION.md`](docs/DESCRIPTION.md).

### 中文

#### 玩家能感觉到的变化

- **换名字了**：`Tate_ASQ` → **AutoSpellQueue**。插件文件夹名也变了，升级时请看下面的「升级须知」。
- **默认装上就能用，不用配置**：设置页从一整页选项精简成「总开关 + 一张状态卡 +（折叠起来的）高级设置」。状态卡直接告诉你：当前值、目标值、延迟、场景，以及**这个数字是怎么算出来的**。
- **它会真的跟着你的网速走**：以前只在换地图/切专精时算一次，延迟变了也照旧；现在**每 15 秒重算一次**（客户端自己的延迟读数约 30 秒刷新，所以最坏情况滞后几十秒）。
- **界面不再说谎**：写不进去就明确显示「写入失败」和原因，而不是显示一个其实没生效的数字。状态条在失败/不可用/关闭时只显示状态名，不会拿旧数字糊弄你。
- **战斗中关闭插件会等脱战**：战斗中一律不写 CVar，关闭也会显示「等待脱战」，脱战后才把你的原值还回去。
- **中英繁三语完整文案**：英文客户端不再看到内部键名（这是上一版的问题）。

#### 修复（来自代码审查）

1. **写入不再「假成功」** — 只有「API 没拒绝」**且**「读回的值与目标一致」才算写入成功。旧版把「没抛异常」当成成功，界面会显示一个并未生效的值。
2. **所有权跨重载不再丢失** — 插件记住接管前你自己的值，并把它存进存档；`PLAYER_LOGOUT` 归还；万一归还失败，下次登录仍能归还。
3. **战斗中的待办不再冲突** — 不再缓存「脱战后要写的旧目标」。脱战瞬间重新读实时状态再决策，避免把战斗前的旧值套上去。这条对「应用」和「归还」一视同仁。
4. **延迟变化会重算** — 见上，启用期间每 15 秒一次；登录后 2/5/10/20/40 秒补算，直到客户端能报出非零延迟。
5. **配置会校验** — 存档里的越界值、错类型、上下限颠倒、坏掉的所有权记录都会修正回默认并计数；未来版本写的存档**不会被降级改写**。
6. **UI 精简与诚实化** — 见上；另外面板不可见时不再刷新，控件树只构建一次。
7. **新增本地验证门禁与可复现打包** — 语法检查、128 个用例 / 1206 条断言的单元测试、结构与版本一致性检查、打包校验，一条命令跑完。

#### 升级须知（破坏性变更）

- **必须先删除旧的 `AddOns\Tate_ASQ` 文件夹**：新旧是两个独立插件，会争抢同一个 CVar。
- **存档变量改名**：`Tate_ASQDB` → `AutoSpellQueueDB`。
- **想保留旧设置，需要手动做一步**：客户端**只加载与插件文件夹同名的存档文件**，旧设置写在
  `WTF\Account\<账号>\SavedVariables\Tate_ASQ.lua` 里，删掉旧插件后没有任何东西会读它。
  把该文件复制/改名为同目录下的 `AutoSpellQueue.lua` 即可自动导入（不复制也能用，只是回到默认设置）。

#### 其他

- 错误不再静默：写入/读取失败一定会在聊天框提示（同一条错误 120 秒内不重复刷屏）。
- 「重置全部设置」现在也会清掉悬浮状态条的位置。
- 新增斜杠命令：`/asq`、`/asq status`、`/asq reset`、`/asq unlock`。
- 新增 `docs/ARCHITECTURE.md`（接口契约）、`docs/CURSEFORGE.md`（发布规划）、`docs/DESCRIPTION.md`（本说明的玩家版）、`LICENSE`（MIT）、`.pkgmeta`。

### English

#### What you will actually notice

- **New name**: `Tate_ASQ` → **AutoSpellQueue**. The addon folder changed too — see "Upgrading" below.
- **Works out of the box**: the options page went from a wall of settings to *master switch + status card + (collapsed) advanced*. The card shows current value, target, latency, context, and **how the number was derived**.
- **It actually follows your connection now**: it used to recalculate only on zone/spec changes, so a latency shift never reached the value. It now **re-evaluates every 15 seconds** (the client's own latency reading refreshes roughly every 30 s, so worst case you're a few tens of seconds behind).
- **The UI stopped lying**: a failed write now shows "write failed" plus the reason instead of a believable number that was never applied. In failed/unavailable/disabled states the floating bar shows the state name only — never a stale number.
- **Disabling in combat waits**: it never writes a CVar during combat, and disabling mid-fight shows "waiting" until combat ends before restoring your value.
- **Full enUS / zhCN / zhTW copy**: English clients no longer see internal key names (a bug in the previous build).

#### Fixes (from the code review)

1. **No more "fake success" writes** — a write only counts when the API did not reject it **and** reading the value back matches the target. The old build treated "no exception raised" as success and displayed a value that was never applied.
2. **Ownership survives reloads** — the value you had before the addon took over is recorded and persisted; `PLAYER_LOGOUT` gives it back, and if that fails the record still lets the next session restore it.
3. **No more combat-pending conflicts** — there is no cached "target to replay after combat". The moment combat ends it re-reads live state and decides again, so a pre-combat value can't be forced onto the client. Same rule for applying and for restoring.
4. **Latency changes are re-evaluated** — every 15 s while enabled, plus a 2/5/10/20/40 s warm-up after login until the client reports a non-zero latency.
5. **Settings are validated** — out-of-range values, wrong types, inverted min/max and broken ownership records are repaired and counted; a save written by a **newer** schema is never downgraded.
6. **Leaner, honest UI** — see above; the panel no longer refreshes while hidden, and the widget tree is built once.
7. **New local verification gate + reproducible packaging** — syntax check, 128 unit cases / 1206 assertions, structure and version consistency, package validation — one command.

#### Upgrading (breaking changes)

- **You must delete the old `AddOns\Tate_ASQ` folder first**: old and new are separate addons that fight over the same CVar.
- **SavedVariables renamed**: `Tate_ASQDB` → `AutoSpellQueueDB`.
- **Keeping your old settings takes one manual step**: the client only loads a SavedVariables file named after the addon folder, and the old settings live in `Tate_ASQ.lua`. Copy
  `WTF\Account\<your account>\SavedVariables\Tate_ASQ.lua` → `AutoSpellQueue.lua` in the same folder. Without that copy the addon simply starts from the defaults.

#### Other

- Errors are no longer silent: write/read failures always print once in chat (the same reason is throttled to once per 120 s).
- "Reset all settings" now also clears the floating bar's saved position.
- New slash commands: `/asq`, `/asq status`, `/asq reset`, `/asq unlock`.
- New docs: `docs/ARCHITECTURE.md` (interface contract), `docs/CURSEFORGE.md` (release plan), `docs/DESCRIPTION.md` (player-facing copy), `LICENSE` (MIT), `.pkgmeta`.

---

## v1.0.2

**中文** — 设置页开关改为滑块式 UI，页面更精简；新增「显示状态条」开关；README 新增繁中与英文说明；下载链接更新到 v1.0.2。

**English** — Toggle switches in the options page; new "Show status bar" option; README gained Traditional Chinese and English sections; download link bumped to v1.0.2.

## v1.0.1

**中文** — 修复状态条位置记忆（保存完整锚点，登录后正确恢复）；位置受屏幕边界约束；精简界面词条与无用函数；README 加入下载链接。

**English** — Fixed status bar position memory (full anchor saved and restored on login); position clamped to the screen; trimmed strings and dead functions; download link added to the README.

## v1.0.0

**中文** — 首个发布版本：依职业/专精基础值自动调整 `SpellQueueWindow`；城市 / 副本 / 野外不同算法；World 延迟优先、Home 回退；悬浮状态条可拖动、左键开设置；中英自动切换。

**English** — First release: automatic `SpellQueueWindow` tuning from a per-spec base value; different rules for cities / instances / open world; World latency first with Home fallback; draggable floating bar that opens the settings on left-click; zhCN/zhTW/enUS support.
