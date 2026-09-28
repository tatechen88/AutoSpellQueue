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

## 先说一句话

装上一个插件，把你游戏里那个藏起来的「施法队列窗口」自动调成适合你专精和网速的值。你不用管它。

## 「施法队列窗口」到底是什么

老玩家都经历过这个瞬间：读条快结束了，你按了下一个技能，游戏「记住」了这次按键，读条一结束立刻接上。

这个缓冲区就叫**施法队列**；`SpellQueueWindow` 是它的长度，单位毫秒，含义是：

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
2. 叠上你的**世界延迟 + 50ms 余量**，两者取大
3. 按场景微调：**城里只用基线**（城里没有战斗节奏），副本 / 团本 / 野外跟着延迟走
4. 在客户端允许的 0~400ms 内取整
5. 之后**每 15 秒**重看一次延迟——网速变了，值自己跟着变

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
- `/asq` —— 打开设置，主界面直接告诉你：当前值、目标值、延迟、场景，以及**这个值是怎么算出来的**
- `/asq status` —— 在聊天框打一份诊断
- 悬浮小条显示实时值，可以拖到顺手的位置；**左键点开设置**

第一次装，建议先去木桩前打两分钟，再决定要不要进高级设置里微调（或者干脆关掉）。

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
插件每 15 秒重算一次；客户端自己的延迟读数大约 30 秒刷新一次，所以最坏情况滞后几十秒。

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

## The short version

Install it, forget it. It keeps the game's hidden "spell queue window" set to a value that fits your spec and your ping.

## What the spell queue window actually is

You've felt it: you press your next ability as the cast bar is almost done, the game remembers the press, and the next spell fires the instant the cast ends.

That buffer is the **spell queue**, and `SpellQueueWindow` is its length in milliseconds:

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
2. Adds your **world latency + 50 ms** of headroom and takes the larger of the two.
3. Adjusts by context: **cities use the baseline only** (no combat pacing there), instances and the open world follow your latency.
4. Rounds and clamps into the client's 0–400 ms range.
5. Re-checks latency **every 15 seconds** while enabled — if your connection changes, the value follows.

You don't need to understand any of that. It's on by default.

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
- `/asq` — the panel shows current value, target, latency, context, and **how the number was derived**
- `/asq status` — a diagnostic dump into chat
- The floating bar shows the live value — drag it where you want, **left-click opens settings**

Give it a couple of minutes on a training dummy before you touch the advanced page, or before you decide to turn it off.

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
It re-evaluates every 15 s; the client's own latency reading refreshes roughly every 30 s, so worst case you're a few tens of seconds behind.

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

> 自动把施法队列窗口（`SpellQueueWindow`）调整到适合你专精与网络延迟的值，并在它不再管理时归还你自己原来的值。只修改本地客户端设置，不自动施法、不联网、无遥测。

**en**

> Keeps your spell queue window (`SpellQueueWindow`) tuned to your spec and latency, and puts your own value back when it stops managing it. It only changes a local client setting — no automation, no network access, no telemetry.

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
