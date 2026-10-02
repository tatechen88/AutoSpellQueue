# AutoSpellQueue — 给魔兽玩家的说明 / A player's guide

> **这份文件是面向玩家的唯一文案源。** CurseForge 商店页、GitHub Release 说明、论坛/群里转发的内容，
> 都从这里取；不要在别处另写一份（会漂移）。中文与 English **各自独立成篇**，不是逐句互译。
> 开发向文档请去 [`ARCHITECTURE.md`](ARCHITECTURE.md) / [`../README.md`](../README.md)。
>
> Store copy, release notes and forum posts all come from this file. The 中文 and English sections are
> written independently, not as literal translations of one another.

**目录**：[中文](#中文版) · [English](#english) · [商店页短简介 / Store summary](#商店页短简介--store-summary)

---

# 中文版

> 插件名：**施法容限**（英文客户端叫 Auto Spell Queue；文件夹名是 AutoSpellQueue，旧版叫 Tate_ASQ）。

## 先说一句话

坦克、治疗、近战、远程，每个**专精**的节奏都不一样——插件给每个专精各自的**施法容限**（`SpellQueueWindow`）
基准值，再用**算法**叠上你的延迟。不是固定数字，也不用你手动调；面板只有两个复选框。

## 「施法容限」到底是什么（英文客户端叫施法队列窗口 / Spell Queue Window）

老玩家都经历过这个瞬间：读条快结束了，你按了下一个技能，游戏「记住」了这次按键，读条一结束立刻接上。

这个缓冲区就叫**施法队列**；`SpellQueueWindow` 是它的长度（中文客户端里这个选项就叫**施法容限**），
单位毫秒，含义是：

> **在当前读条 / GCD 结束前多少毫秒按下的键，还算数。**

暴雪默认给 **400ms**。

400 是给高延迟玩家的保护。但对 20~60ms 的人，它同时意味着另一件事：**你手滑按错的那个技能，也在 0.4 秒内都算数。**

## 为什么有人觉得「卡手」，有人觉得「黏键」

两种毛病，方向正好相反：

- **窗口太小** —— 按早了不算数，读条结束到下一个技能之间出现肉眼可见的空档。延迟一高就特别明显。
- **窗口太大** —— 你按了 A、又改主意按 B，但服务器先收到了 A；或者你排了一个其实还没准备好的技能，它在错误的时机放出去。近战和连击点职业对这个最敏感：GCD 短、按键频率高，**400ms 差不多能盖住半个 GCD**。

社区里通行的算法其实很简单：

> **窗口 ≈ 你的世界延迟 + 一点余量**

这也就是为什么它不该是一个固定值。

## 这个插件做的事

1. 读你当前专精，给一个**手感基线**（高 APM 近战 ~140ms、标准近战 ~150ms、坦克略高、读条法系 ~240ms）
2. 叠上你的**世界延迟 + 自适应余量**，两者取大。余量不再写死 50ms：插件按实测的**延迟抖动**算，
   连接稳就少留、抖动大就多留（30–150ms），所以不会出现「稳定网络白留一截」或「抖动网络留不够」
3. 按场景微调：**城里只用基线**（城里没有战斗节奏），副本 / 团本 / 野外跟着延迟走
4. 在客户端允许的 0~400ms 内取整
5. 之后**不再固定节奏轮询**：延迟稳定后它就停止检测，只在换区、**进副本 / 团本**，或延迟真的漂移时才重测一次（记忆值会跨会话保留，所以登录时立刻就是正确值）。

你不需要懂上面任何一条。装上就是默认开启。

## 谁最该用 / 谁其实不需要

**收益明显**

- 大秘境、团本里打输出的**近战**、**连击点职业**（盗贼三系、踏风、野德、增强萨）
- **世界延迟 > 80ms** 的人：400 可能都不够用，插件会自动往上抬
- **读条职业**（法师 / 术士 / 元素萨）：读条末尾的衔接更干净
- 换过网络环境的人：手动调好的值，换网之后就错了

**收益很小**

- 延迟极低（<20ms）而且早就习惯 400 的人
- 完全不在意手感的人

诚实一点：这**不是**「装了 DPS 就涨」的插件。它调的是**手感**——断档更少、误排更少。你如果本来就没感觉到问题，那 400 对你就是合适的。

## 装完怎么确认它在工作

- `/dump GetCVar("SpellQueueWindow")` —— 看当前值
- `/asq` —— 打开面板。面板上只有一行状态（如 `已应用 · 220 ms`），**把鼠标移到那一行上**，
  它才展开告诉你：目标值、延迟、场景、以及**这个值是怎么算出来的**（不打扰不想看的人）
- `/asq status` —— 在聊天框打一份诊断（含算法当前的余量、抖动、采样策略、写入次数）
- 悬浮小条显示实时值，可以拖到顺手的位置；**左键点开面板**

**面板里只有两个复选框**：总开关，和「要不要显示悬浮读数」，外加一个「重置位置」按钮（那是动作，不是参数）。
安全余量、写入阈值、延迟来源、窗口上下限、多久检测一次，全部由插件按你的实测网络自己决定——
这些数字玩家猜不准，插件测一辈子也比你猜得准，所以它们不该变成你要操心的选项。

**它会自己安静下来**：登录、换区、进副本或团本时采样一小段，读数稳定后就**不再反复测**，
之后每 5 分钟只做一次廉价的漂移检查（真的漂移了才重新采样）。学到的延迟会记住，下次登录立刻就是正确值。

**屏幕上的数字会说话**：数字本身是容限值，但它的**颜色**说的是你的网络——延迟正常时是白色（连边框一起白），明显高于你平时的水平就变红，
一眼就能看出网络好不好。失败 / 等待脱战 / 关闭用各自的状态色。悬停会写明「为什么是红的」。

## 它不是什么（这段请认真看）

- **不自动施法**、不替你按键、不做输出循环、不判断该放什么技能
- 不读战斗日志做决策、不联网、没有遥测、不上传任何数据
- 它改的就是**你自己也能用 `/console SpellQueueWindow 200` 改的那个数字**

换句话说：它只是替你算了一个你本来该自己算、但大多数人懒得算的数字。

## 「它会乱改我的设置吗」

不会，这是它设计里最讲究的部分：

- 只在**自己写进去的值还在生效**时才归还；如果你或别的插件中途改过，它只放弃管理权，**绝不覆盖**
- **战斗中一律不写**；战斗中关插件会显示「等待脱战」，脱战后才归还
- **下线前**会把你的原值还回去，客户端再保存
- 每次写入都会**读回校验**：写不进去就明确告诉你失败原因，而不是假装成功（这是很多老插件的通病）

## 常见问题

**会和别的同类插件冲突吗？**
会——它们抢同一个 CVar。**只装一个。**

**延迟变化多久生效？**
登录、换区、进副本或团本时它立刻重测；读数稳定后它不再反复测，之后每 5 分钟做一次漂移检查，
真漂移了（超过 25ms）马上重新采样。客户端自己的延迟读数本身也是周期性刷新的（不是每秒都在变），
所以任何插件看到的延迟都会有一段时间的滞后——这也是没必要一直测的原因。

**为什么我关了插件，值就变回去了？**
因为它认为那个值是你的，不是它的。

**支持哪些版本？**
正式服 12.x（12.0.0–12.1.5）。没有 Classic 版本。

**会被封号吗？**
它只读写一个本地 CVar，等同于你自己敲 `/console`，完全不碰战斗逻辑。但请记住一句话：**任何声称替你打输出的插件都别装**——那才是会出事的东西。

**在哪反馈问题？**
[GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues)，或 CurseForge 项目页的评论。

## 一句话总结

把你懒得算的那个数字按专精和网速算好，然后闭嘴。

---

# English

> Addon name: **Auto Spell Queue** on an English client, **施法容限** on a Chinese one (the folder is
> AutoSpellQueue; older versions were called Tate_ASQ).

## The short version

Tanks, healers, melee and ranged - every **spec** plays differently, so every spec gets its own
**spell queue window** (`SpellQueueWindow`) baseline, and an **algorithm** folds in your latency.
No fixed number, no manual tuning. Two checkboxes.

## What the spell queue window actually is (「施法容限」 on a Chinese client)

You've felt it: you press your next ability as the cast bar is almost done, the game remembers the press, and the next spell fires the instant the cast ends.

That buffer is the **spell queue**, and `SpellQueueWindow` is its length in milliseconds - the option a Chinese
client calls **施法容限**:

> **How early a keypress still counts, before the current cast / GCD ends.**

Blizzard ships it at **400 ms**.

400 ms is a safety net for high latency. But if you play at 20–60 ms, it also means something else: **the ability you fat-fingered still counts for the next 0.4 seconds.**

## Why some players feel "clunky" and others feel "sticky"

Two failure modes, pointing in opposite directions:

- **Window too small** — presses land early and get dropped, leaving a visible gap between casts. Brutal on high ping.
- **Window too large** — you press A, change your mind and press B, but the server already took A. Or you queue something that wasn't ready and it fires at the wrong moment. Melee and combo-point specs feel this worst: short GCDs, high keypress rate, and **400 ms can cover nearly half a GCD.**

The community rule of thumb is simple:

> **window ≈ your world latency + a bit of headroom**

Which is exactly why it shouldn't be a fixed number.

## What this addon does

1. Reads your spec and picks a **feel baseline** (~140 ms high-APM melee, ~150 ms standard melee, slightly higher for tanks, ~240 ms for casters).
2. Adds your **world latency + adaptive headroom** and takes the larger of the two. The headroom is no longer a hardcoded 50 ms: it is derived from the **jitter it measures**, so a stable connection does not waste 50 ms and a noisy one gets more room (30–150 ms).
3. Adjusts by context: **cities use the baseline only** (no combat pacing there), instances and the open world follow your latency.
4. Rounds and clamps into the client's 0–400 ms range.
5. After that it **stops probing on a fixed schedule**: once latency settles it only re-checks on a zone change, when you **enter a dungeon or raid**, or when latency really drifts (the learned value is remembered across sessions, so logging in starts you at the right number).

You don't need to understand any of that. It's on by default, and there is nothing to configure.

## Who benefits / who doesn't

**Noticeable gains**

- Melee and **combo-point** DPS in M+ and raid (all three rogue specs, Windwalker, Feral, Enhancement)
- Anyone above **~80 ms world latency**, where 400 ms may not even be enough
- **Casters** (Mage, Warlock, Elemental) who want cleaner end-of-cast chaining
- Anyone whose connection changed after they hand-tuned a value

**Marginal**

- Very low ping players who are already happy at 400
- People who simply don't care about feel

Honest version: this is **not** an "install it and your DPS goes up" addon. It tunes **feel** — fewer dropped presses, fewer accidental queues. If you never noticed a problem, 400 was probably fine for you.

## How to confirm it works

- `/dump GetCVar("SpellQueueWindow")` — the current value
- `/asq` — opens the panel, which shows one status line (e.g. `Applied · 220 ms`); **hover that line** and it
  unfolds the details: target, latency, context and **how the number was derived** (invisible to anyone who
  does not care)
- `/asq status` — a diagnostic dump into chat (headroom, jitter, sampling policy and write count)
- The floating bar shows the live value — drag it where you want, **left-click opens the panel**

**There are exactly two checkboxes**: on/off, and whether the floating readout is drawn, plus a "reset
position" button (an action, not a setting). Safety headroom, the write threshold, the latency source, the
window limits and how often to probe are all decided by the addon from what it measures — you cannot guess
those numbers better than it can measure them, so they are not your problem to manage.

**It goes quiet on its own**: it samples briefly on login, on zone changes and when you enter a dungeon or
raid, then **stops re-measuring** once the reading settles — after that it only runs one cheap drift check
every 5 minutes (and re-samples only if latency really moved). The learned latency is remembered, so the next
login starts at the right value.

**The number on screen talks**: white while your latency is what this machine normally sees (border included),
red once it is clearly worse than usual, so the connection state is readable at a glance. Failure / waiting
for combat / disabled keep their own state colour. Hovering spells out **why** it is red.

## What it is NOT (please read this part)

- **No automation.** It doesn't cast, doesn't press keys for you, doesn't run a rotation, doesn't decide what to use.
- No combat-log reading, no network calls, no telemetry, no data collection.
- The only thing it changes is **the number you could change yourself** with `/console SpellQueueWindow 200`.

In other words: it just does the arithmetic most players never bother to do.

## "Will it mess with my settings?"

That part is deliberate:

- It only restores your value while **the value it wrote is still in place**. If you or another addon changed it in the meantime, it drops ownership and **never overwrites you**.
- **It never writes during combat.** Disabling mid-fight shows "waiting" and restores once combat ends.
- It puts your value back **before logout**, then the client saves.
- Every write is **verified by reading the value back**. If it can't write, it tells you why instead of pretending it worked — the usual failure mode of older addons.

## FAQ

**Does it conflict with similar addons?**
Yes — they fight over the same CVar. **Install one.**

**How fast does it react?**
It re-measures immediately on login, on zone changes and when you enter a dungeon or raid. Once the reading
settles it stops re-measuring and only runs one drift check every 5 minutes, re-sampling at once if latency
really moved (more than 25 ms). The client's own latency reading is refreshed periodically too (it does not
change every second), so any addon is a little behind by nature - which is exactly why there is no point in
measuring constantly.

**Why does my value change back when I disable it?**
Because that value is yours, and it knows it.

**Which versions?**
Retail 12.x (12.0.0–12.1.5). No Classic build.

**Can I get banned?**
It reads and writes one local CVar — the same thing you can do with `/console`. It never touches combat logic. Still, keep this rule: **never install anything that claims to play the game for you.** That's the stuff that gets people actioned.

**Where do I report problems?**
[GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues), or the CurseForge project page.

## One line

It does the number you couldn't be bothered to compute, then shuts up about it.

---

# 商店页短简介 / Store summary

**zhCN**

> 按专精自动调整施法容限：专精基准值 + 算法叠加你的延迟；不是固定数字，也不用你手动调。

**en**

> Spell queue window tuned per spec: your spec's baseline plus your latency, by algorithm. No fixed number, no manual tuning.

---

## 安装步骤（商店页也需要，故在此保留一份）

1. 下载 zip，解压得到 `AutoSpellQueue` 文件夹。
2. 放进 `World of Warcraft\_retail_\Interface\AddOns\`（即 `AddOns\AutoSpellQueue\AutoSpellQueue.toc`）。
3. 进游戏，默认启用。

从旧版 `Tate_ASQ` 升级：**先删除旧的 `Tate_ASQ` 文件夹**；想保留旧设置，再把
`WTF\Account\<账号>\SavedVariables\Tate_ASQ.lua` 复制为同目录的 `AutoSpellQueue.lua`
（客户端只加载与插件文件夹同名的存档文件；不复制就用默认设置）。

> 说明：安装步骤在 `README.md` 与本文各有一份是**刻意的**——商店页无法引用仓库文件。
> 其余事实只在 `README.md` / `ARCHITECTURE.md` 里维护，见 [`README.md`](README.md)（文档地图）。

## 商店页 Description（极简版 · 三语，与 CURSEFORGE-LISTING 副本一致）

### English

- Per-spec feel baseline (~140 ms high-APM melee, ~150 ms standard melee, slightly higher for tanks, ~240 ms for casters).
- Adds your world latency plus adaptive headroom (30-150 ms, from measured jitter), whichever is larger.
- Context-aware: cities use the baseline only; instances and the open world follow your latency.
- Clamped to the client's 0-400 ms range.
- Re-measures on login, zone change, entering a dungeon or raid, or real latency drift; learned latency is remembered across sessions.
- Two checkboxes: enable, and show the floating status bar.
- The number on screen is the tolerance value; its colour tracks your connection against your own normal (white = normal, red = clearly worse).
- Ownership: it only restores your value while its own value is still in place - if you or another addon changed it, it never overwrites you. No writes in combat, your value goes back before logout, and every write is verified by reading it back.
- It does not cast, press keys, run a rotation, or read the combat log. It changes only the CVar you could change yourself with /console SpellQueueWindow 200.

Note: do not run it alongside another addon that touches the same CVar.

My other addons
- [CraftPro](https://www.curseforge.com/wow/addons/craftpro) - record a crafting recipe with one click and see what it needs, what you have and what is still missing.
- [StockTake](https://www.curseforge.com/wow/addons/stocktake) - hover an item and the tooltip shows how many you own: bags, bank (warband bank included) and every character on your account.

Feedback: [GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues) - MIT license.

### 中文

- 按专精给施法容限手感基准（高 APM 近战约 140ms、标准近战约 150ms、坦克略高、法系约 240ms）。
- 叠上世界延迟与自适应余量（按实测抖动算，30–150ms），取较大的那个。
- 分场景：城里只用基准值；副本与野外跟随你的延迟。
- 夹在客户端允许的 0–400ms 内。
- 登录、换区、进副本 / 团本、或延迟真的漂移时重测；学到的延迟跨会话记住。
- 只有两个复选框：启用、显示悬浮状态条。
- 屏幕上的数字是容限值，颜色说的是你的网络 —— 与你自己平时相比，正常白色、明显变差转红。
- 所有权：只在仍是自己的值时归还；你或别的插件改过，它绝不覆盖。战斗中不写，登出前归还，每次写入读回校验。
- 不自动施法、不按键、不做输出循环、不读战斗日志。它改的就是你自己也能用 /console SpellQueueWindow 200 改的那个值。

注意：不要与改动同一 CVar 的同类插件同时使用。

我的其他插件
- [CraftPro](https://www.curseforge.com/wow/addons/craftpro) —— 打开配方点一下按钮，就得到一张材料清单：要什么、有多少、还缺多少。
- [StockTake](https://www.curseforge.com/wow/addons/stocktake) —— 鼠标移到物品上，提示框直接告诉你全账号持有量（背包、银行、含战团银行、所有角色）。

反馈：[GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues) —— MIT 许可。

