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
- **不用设置了**：设置页从 12 个控件砍到 **2 个开关**（总开关 + 要不要显示悬浮读数）。参数不再需要你调——
  插件自己算。想微调的人只剩一条命令行逃生口 `/asq base <50-400>`（给某个专精固定基础值）。
- **算法接管了原来 5 个设置的活**：安全余量不再写死 50ms，而是按**实测抖动**算（稳定网络少留、抖动大就多留，30–150ms），
  写入阈值同样按抖动自适应，避免网络一抖就反复改值；延迟平滑改成**变差立刻跟、变好慢慢放**，既不欠缓冲也不来回跳。
- **装上就能用**：状态卡直接给出当前值、目标值、延迟、场景、**自适应余量**，以及**这个数字是怎么算出来的**。
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
7. **新增本地验证门禁与可复现打包** —— 语法检查、单元测试、结构与版本一致性检查、打包内容校验，一条命令跑完（数量会随版本变化，跑 `pwsh tools/verify.ps1` 看当次输出）。
8. **第二轮逐行审查的收尾修复** —— 关掉插件后若归还被战斗推迟或写失败，15 秒定时器继续重试（不再依赖下次换图）；上限低于 50ms 时面板给出警告；状态条几何异常时不再抛错、也不会把 NaN 写进存档；`/asq status` 的「当前值」改为实时读取并标注采样时间。
9. **修复「进入游戏后界面完全没有任何显示」** —— 状态条的字体串创建时未绑定字体，客户端在 `SetText` 时抛 `FontString:SetText(): Font not set`，而这个错误发生在界面初始化流程里，导致状态条与设置面板一起没被建出来。现在字体串自带字体，并且**每个界面部件独立初始化**：任何一个部件失败都会在聊天框报出部件名与原因，且不再影响其它部件（设置面板优先注册）。测试桩同步加严，按客户端规则模拟「无字体不得 SetText」，杜绝同类问题再次漏网。
10. **修复设置页布局：提示文字重叠 + 展开高级设置后溢出窗口** —— ①带提示的开关行里标签原本垂直居中，与提示画在同一位置（表现为「启用自动调整pellQueueWindow 还原成你原本的值。」这种两行字叠在一起）；②设置内容比画布高时客户端不会替你滚动，旧代码还把宿主高度一起撑大，于是下面的行画到窗口外、盖住暴雪的「关闭」按钮。现在提示行的标签顶对齐、提示下移，且**所有设置内容放进滚动框**（设置画布与独立窗口共用同一套滚动），内容再高也只在框内滚动。
11. **把「设置」变成「算法」（schema v2）** —— 玩家反馈「设置太多、要无感」。删掉 12 个旋钮：`baseMode`/`manualBase`（手动基础值）、`adaptive`、`latencySource`、`margin`、`minWindow`/`maxWindow`、`hysteresis`、`statusFont`/`statusFontSize`、`chatFeedback`、`showAdvanced`；新增纯算法模块 `AutoSpellQueue_Latency.lua` 承担余量（`40 + 1.5×抖动`，钳 30–150）、写入阈值（`5 + 1.0×抖动`，钳 5–25）与不对称延迟平滑（`SMOOTH_UP 0.5` / `SMOOTH_DOWN 0.15`）。旧存档里的旋钮会被 `Sanitize` 清掉，**唯一保留的是玩家刻意设过的手动基础值**——迁移为 `/asq base` 的覆盖值。新增「配置白名单」用例守住这条线：面板里出现第三个开关、或配置里冒出未经审阅的键就会失败。
12. **修复「点进选项里面是完全空白的」** —— 把设置内容放进滚动框之后，**只设了高度没设宽度**：客户端不会从锚点推导 `ScrollFrame` 子框的宽度，而所有控件都以「左+右」双锚点挂在子框上，于是全部渲染成零宽。真机上直接在游戏里读到 `CHILD 0 440`（面板 665×604、滚动框 639×602 都是对的），一眼定位。现在滚动子框显式定宽，并在窗口尺寸变化时同步。
13. **修复中文说明被截断与文字重叠** —— ①`SetWordWrap` 只按空格断行，中文没有空格，客户端直接把长句截断成「…」（副标题、脚注都中招；同时暴露出语言表里误写的 Markdown 星号），现在同时开启 `SetNonSpaceWrap`；②靠左右双锚点取宽的字体串不会回流，改为**显式宽度**；③卡片里采样说明与状态提示只隔 18px，说明一折行就叠在一起，现在各留两行高度。三处都在真机上截图确认修复。
14. **不再每 15 秒轮询（采样策略重做）** —— 延迟在几分钟内不会跳变，而真正会改变答案的事件（登录、换区、**进副本 / 团本**、切专精、别的插件改值）客户端都会主动通知，所以固定节奏轮询是白费力气。现在：**只在学习期采样**（每 15 秒，平滑值不再移动就停），稳定后**进入固定状态，每 300 秒只做一次廉价漂移检查**，只有读数真的漂移超过 25ms 才重新采样；写失败改为 60 秒退避重试（前 3 次）后降到心跳，不再无脑轰。**并把学到的延迟记住**：下次登录立刻用它在正确值上待命，不再等客户端报延迟（第一笔实测与记忆值差得多时直接采用实测）。`/asq status` 新增「采样策略 / 记住的延迟」两行，玩家能直接看到它确实没在一直检测。
15. **设置页做成极简** —— 玩家反馈「说明太多，普通玩家根本不需要知道」。页面上只留：标题、**一行状态**（如 `已应用 · 220 ms`；失败时只显示「写入失败」，绝不显示数字冒充结果）、两个开关、重置位置按钮。原先那张大状态卡（目标值/延迟/场景/专精/基础值/原值/算式/采样说明/状态解释）与底部脚注**全部移到鼠标悬停提示里**——想知道的人看得到，不需要的人不受打扰。守门用例：面板里任何一行文字不得超过 60 字节、可见文字不超过 6 行，副标题与脚注不得再出现在页面上。
16. **设置页改用 StockTake 风格（原生控件、零自绘）** —— 与姊妹插件**数量盘点 / StockTake** 保持同一套做法，玩家只需要学一次布局：标题用 `GameFontNormalLarge` 锚在 `(16,-16)`，下面一行状态；**控件全部换成暴雪原生控件**（`SettingsCheckboxTemplate` 复选框 + `UIPanelButtonTemplate` 按钮），不再自绘开关、行背景与边框；控件直接锚在面板上、**去掉滚动框**（StockTake 也没有，"滚动子框宽度为 0 导致整页空白"那类坑随之消失）；提示改为接管 `OnEnter` 并隐藏模板自带的悬停反白背景。顺带处理掉 StockTake 源码记录的两个实测坑：现代复选框模板没有文本元素（标签必须自建且带锚点），`$parentText` 只在控件有全局名时才存在（按钮必须命名，否则标签看不见）。

17. **屏幕上的数字会随延迟变色** —— 正常（≈ 本机平时水平）显示**白色**，明显偏高显示**红色**，**状态条的边框也跟着同色**（白框 / 红框），一眼就能看出网络好不好；客户端还没报出延迟时不猜，保持白色。判据是**相对你自己平时**而不是固定阈值（`clamp(平时 + 60ms, 120ms, 250ms)`）：平时就 200ms 的人不会永远看到红色。失败 / 等待 / 关闭这些状态仍用自己的颜色（那是状态信息，不是延迟问题）。偏高时悬停提示会写明「当前 X ms，平时约 Y ms」，红色不会是谜。
18. **配色全部统一** —— 插件不再有自己的"品牌色"：屏幕上的每一处着色都来自同一个函数，正常=白、偏高=红、失败/等待/关闭用各自的状态色。**状态条的边框、悬停提示的标题、独立窗口的边框与标题、以及聊天框里的插件名前缀**全部跟着变（聊天前缀原来是绿色，现在是白/红）。插件列表里显示的名字去掉了颜色码，用客户端默认色——那是静态元数据，没法随延迟变化，所以干脆不做彩色标识。
19. **中文界面改名为「施法容限」** —— 中文客户端的玩家在游戏里看到的词就是它，所以插件列表、设置页标题、聊天提示统一用这个名字（英文客户端仍为 `Auto Spell Queue`）。设置分类的内部标识没有跟着改（仍是 `AutoSpellQueue`），所以升级后你在选项里的位置、存档、命令都不受影响。
20. **悬停提示不再挡住鼠标，也不会被屏幕切掉** —— 鼠标移到悬浮读数上时，提示框现在挂在**读数条下方并留 8px 间隙**（原来贴着读数条上方，而读数条通常在屏幕上方，导致标题和状态行被切到屏幕外、提示框还压着光标）。读数条被拖到屏幕底部时会自动翻到上方，两种情况都留间隙并夹紧在屏幕内；按住拖动时提示框立刻消失。
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
- **Nothing to configure**: the options page went from 12 controls to **2 switches** (on/off, and whether the floating readout is drawn). The parameters are no longer yours to tune — the addon computes them. The only manual escape hatch left is a command: `/asq base <50-400>` (pin the base value for one spec).
- **The algorithm took over what five settings used to do**: the safety margin is no longer a hardcoded 50 ms — it is derived from **measured jitter** (a stable link wastes nothing, a noisy one gets room, 30–150 ms), and the write threshold adapts to the same jitter so a shaky connection cannot make it rewrite constantly. Latency smoothing is now **fast when you get worse, slow when you get better**: never under-buffered, never flapping.
- **Works out of the box**: the status card shows the current value, target, latency, context, **the adaptive headroom**, and **how the number was derived**.
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
7. **New local verification gate + reproducible packaging** — syntax check, unit tests, structure and version consistency, package content validation, in one command (counts change per release; run `pwsh tools/verify.ps1` for the current numbers).
8. **Follow-up fixes from a line-by-line review** — if the restore is deferred by combat or the write fails, the 15 s timer keeps retrying instead of waiting for the next zone change; the panel warns when the cap is below 50 ms; broken status-bar geometry no longer raises or stores NaN; `/asq status` now prints the live value and labels the sample age.
9. **Fixed "nothing at all shows up in game"** — the status bar's font string had no font bound, so the client raised `FontString:SetText(): Font not set` during UI setup, which took both the status bar and the settings panel down with it. The string now carries a font, and **every UI part initialises independently**: a failure names the part and the reason in chat and no longer blocks the rest (the settings panel is registered first). The test double now models the client rule ("no font ⇒ SetText fails") so this class of bug cannot slip through again.
10. **Fixed two settings-page layout bugs: overlapping hint text, and content spilling out of the window** — (1) in rows that carry a hint, the label was vertically centred and drawn on top of the hint (it looked like `启用自动调整pellQueueWindow 还原成你原本的值。`, i.e. two lines stacked on one); (2) the client does not scroll a settings canvas, and the old code also grew the host frame with the content, so the lower rows were painted outside the window and over Blizzard's own Close button. Hinted rows now top-align their label, and **all settings content lives in a scroll frame** shared by the settings canvas and the standalone window, so tall content scrolls instead of overflowing.
11. **Turned "settings" into "algorithm" (schema v2)** — players told us the options were far too complex and wanted it to just work. Twelve knobs are gone: `baseMode`/`manualBase`, `adaptive`, `latencySource`, `margin`, `minWindow`/`maxWindow`, `hysteresis`, `statusFont`/`statusFontSize`, `chatFeedback`, `showAdvanced`. A new pure module, `AutoSpellQueue_Latency.lua`, owns the headroom (`40 + 1.5 × jitter`, clamped 30–150), the write threshold (`5 + 1.0 × jitter`, clamped 5–25) and asymmetric smoothing (`SMOOTH_UP 0.5` / `SMOOTH_DOWN 0.15`). Retired keys are cleaned out of old save files by `Sanitize`; the one thing a player may have set deliberately — a manual base value — is migrated into the `/asq base` override instead of being thrown away. A new "config whitelist" test guards the line: a third switch in the panel, or any unreviewed config key, fails the suite.
12. **Fixed "the options page is completely blank"** — after moving the content into a scroll frame, the content frame got a height but **no width**: the client does not derive a ScrollFrame child's width from anchors, and every widget is anchored left+right to it, so all of them rendered at zero width. Reading it straight out of the live client gave `CHILD 0 440` (the panel 665×604 and the scroll frame 639×602 were both fine), which pinned it down immediately. The scroll child now has an explicit width, kept in sync when the window is resized.
13. **Fixed truncated Chinese text and overlapping lines** — (1) `SetWordWrap` only breaks at spaces and Chinese has none, so the client ellipsized long sentences (the subtitle and the footer both did; it also exposed Markdown asterisks I had mistakenly left in the locale table) — `SetNonSpaceWrap` is now enabled as well; (2) strings that took their width from left+right anchors do not re-flow, so wrapping strings now get an **explicit width**; (3) the card's sample note and state hint were only 18 px apart, so the note's second line landed on the hint — both now get two lines of room. All three were verified with screenshots from the running game.
14. **No more polling every 15 seconds (sampling policy rewritten)** — latency does not move much within minutes, and every event that can actually change the answer (login, zone change, **entering a dungeon or raid**, spec change, another addon touching the CVar) is already delivered to us, so a fixed polling loop was wasted work. Now it samples **only while learning** (every 15 s, and it stops as soon as the smoothed value stops moving), then settles into **one cheap drift check every 300 s** that only re-samples when the reading really moved by more than 25 ms; a failed write retries after 60 s (first three attempts) and then backs off to the heartbeat instead of hammering. It also **remembers the latency it learned**: the next login applies the right value immediately instead of waiting for the client to report anything (and if the first real reading disagrees with the memory, the reading wins outright). `/asq status` gained "Sampling" and "Remembered latency" lines so you can see for yourself that it is not probing constantly.
15. **The options page is now minimal** — players told us there was far too much explaining for something an ordinary player does not need to know. The page keeps: a title, **one status line** (e.g. `Applied · 220 ms`; on failure it shows only "write failed" and never a number pretending to be the result), two checkboxes and a reset-position button. The old status card (target / latency / context / spec / base / your original value / formula / sampling note / state explanation) and the footer all moved into **mouse-over tooltips** - there for anyone who wants them, out of the way for everyone else. Guard tests: no visible line may exceed 60 bytes and at most 6 lines may be visible.
16. **The options page now follows the StockTake style (native controls, zero custom drawing)** — it matches our sibling addon **StockTake** so one layout is all a player has to learn: a `GameFontNormalLarge` title at `(16,-16)`, one status line under it, and **Blizzard-native controls** (`SettingsCheckboxTemplate` checkboxes plus a `UIPanelButtonTemplate` button) instead of the hand-drawn switch, row backgrounds and borders. Controls anchor straight to the panel and the **scroll frame is gone** (StockTake has none either, which also removes the "zero-width scroll child renders a blank page" class of bug), and tooltips take over `OnEnter` while hiding the template`s own bright hover background. The two traps documented in StockTake`s source are handled: the modern checkbox template ships no text element (labels must be our own, anchored), and `$parentText` only exists when the control has a global name (the button must be named, or its label is invisible).

17. **The number on screen now changes colour with your latency** — white while latency is what this machine normally sees, red once it is clearly worse - and the bar's border follows the same colour (white / red), so the connection state is readable at a glance; when the client has not reported a latency yet it stays white rather than guessing. The rule is relative to your own normal, not a fixed threshold (`clamp(normal + 60 ms, 120 ms, 250 ms)`), so a player who lives at 200 ms is not stuck looking at red. Failure / waiting / disabled states keep their own colours (those are not latency problems). When it is high, the tooltip spells out "currently X ms, usually about Y ms" so the red is never a mystery.
18. **One palette everywhere** — the addon no longer has a colour of its own: every coloured surface asks the same function, so normal is white, clearly worse is red, and failure / waiting / disabled use their state colour. That now includes the **bar's border, the hover tooltip's title, the fallback window's border and title, and the addon name in chat** (the chat prefix used to be green). The name in the addon list lost its colour code and uses the client default - it is static metadata that cannot follow latency, so it carries no colour identity at all.
19. **The Chinese name is now 「施法容限」** — that is the term a Chinese client actually shows, so the addon list, the settings page title and the chat notices all use it (English clients keep `Auto Spell Queue`). The category's internal identity did not change (it is still `AutoSpellQueue`), so upgrading does not move the page, the saved variables or any command.
20. **The hover tooltip no longer sits under your cursor or off-screen** — hovering the floating readout now puts the tooltip **below it with an 8 px gap**. It used to be pinned flush above the readout, which normally lives near the top of the screen: the title and status line were cut off above the screen edge and the box sat against the pointer. If you drag the readout to the bottom of the screen it flips above instead, both cases keep the gap and stay clamped on-screen, and the tooltip disappears the moment you grab the readout.
#### Upgrading (breaking changes)

- **Delete the old `AddOns\Tate_ASQ` folder first**: old and new are separate addons that fight over the same CVar.
- **SavedVariables renamed**: `Tate_ASQDB` → `AutoSpellQueueDB`.
- **Keeping your old settings takes one manual step**: the client only loads a SavedVariables file named after the addon folder, and the old settings live in `Tate_ASQ.lua`. Copy
  `WTF\Account\<your account>\SavedVariables\Tate_ASQ.lua` → `AutoSpellQueue.lua` in the same folder. Without that copy the addon starts from the defaults.

#### Other

- Errors are no longer silent: write / read failures always print once in chat (the same reason is throttled to once per 120 s).
- Routine value changes are now **silent** (the old optional "chat feedback" is gone): the addon should be invisible while it works.
- The floating bar uses the client's own font, so it follows your game font and UI scale with no setting.
- New slash commands: `/asq`, `/asq status`, `/asq reset`, `/asq unlock`, `/asq base <ms|auto>`.
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
