# CurseForge 商店页材料（上传用副本）

> **性质**：`DESCRIPTION.md` 与 `CHANGELOG.md` 的**发布用派生副本**——事实仍以那两份为唯一出处，
> 本文件只做三件事：①语言顺序改为 **English → 简体中文 → 繁體中文**（CurseForge 规则：英文必须整段在前）；
> ②转成 CF 安全格式（`<…>` 改省略号；粗体两侧与全角字符之间加空格；仓库相对链接退化为纯文本）；
> ③集中在一处，上传时直接整段复制。**改内容请回去改源头，再重新生成本文件。**

## Summary（General → Summary，三条分别贴）

**English**

> Keeps your spell queue window (`SpellQueueWindow`) tuned to your spec, latency **and its jitter**, and puts your own value back when it stops managing it. **Two checkboxes and you are done**; the number on screen is white when your connection is normal and red when it is clearly worse. It only changes a local client setting - no automation, no network access, no telemetry.

**简体中文**

> 自动把「施法容限」（`SpellQueueWindow`）调整到适合你专精与网络延迟（含抖动）的值，并在它不再管理时归还你自己原来的值。**装上即用，面板里只有两个复选框**；屏幕上的数字白色=网络正常、红色=明显偏高。只修改本地客户端设置，不自动施法、不联网、无遥测。

**繁體中文**

> 自動把「施法容限」（`SpellQueueWindow`）調整到適合你專精與網路延遲（含抖動）的值，並在它不再管理時歸還你自己原本的值。**裝上即用，設定頁裡只有兩個核取方塊**；畫面上的數字白色=網路正常、紅色=明顯偏高。只修改本機用戶端設定，不自動施法、不連網、無遙測。

## Description（Description 标签 → Markdown 模式 → 整段粘贴）

### English

Install it, forget it. It keeps the game's hidden "spell queue window" (`SpellQueueWindow`) set to a value that fits your spec and your ping — and gives your own value back when it stops managing the setting.

**What the spell queue window actually is**

You've felt it: you press your next ability as the cast bar is almost done, the game remembers the press, and the next spell fires the instant the cast ends. That buffer is the spell queue, and `SpellQueueWindow` is its length in milliseconds — how early a keypress still counts before the current cast / GCD ends. Blizzard ships it at 400 ms.

400 ms is a safety net for high latency. But if you play at 20–60 ms, it also means: **the ability you fat-fingered still counts for the next 0.4 seconds.**

**Why some players feel "clunky" and others feel "sticky"**

- **Window too small** — presses land early and get dropped, leaving a visible gap between casts. Brutal on high ping.
- **Window too large** — you press A, change your mind and press B, but the server already took A. Melee and combo-point specs feel this worst: short GCDs, high keypress rate, and 400 ms can cover nearly half a GCD.

The community rule of thumb: **window ≈ your world latency + a bit of headroom** — which is exactly why it shouldn't be a fixed number.

**What this addon does**

1. Reads your spec and picks a feel baseline (~140 ms high-APM melee, ~150 ms standard melee, slightly higher for tanks, ~240 ms for casters).
2. Adds your world latency + adaptive headroom (derived from measured jitter, 30–150 ms) and takes the larger of the two.
3. Adjusts by context: cities use the baseline only; instances and the open world follow your latency.
4. Clamps into the client's 0–400 ms range.
5. Then stops probing on a fixed schedule: it re-checks on login, zone change, entering a dungeon or raid, or when latency really drifts. The learned latency is remembered across sessions.

You don't need to understand any of that. It's on by default, and there is nothing to configure: **two checkboxes, and a reset-position button.**

**The number on screen talks** — that number is the tolerance value (e.g. `220 ms`), but its colour is about your connection: white when normal (border included), red once clearly worse than your usual. The rule is relative to your own normal, so a player who lives at 200 ms is not stuck looking at red.

**What it is NOT (please read this part)**

- No automation: it doesn't cast, press keys, run a rotation, or decide anything.
- No combat-log reading, no network calls, no telemetry, no data collection.
- The only thing it changes is the number you could change yourself with `/console SpellQueueWindow 200`.

**Ownership is deliberate**: it only restores your value while its own value is still in place — if you or another addon changed it, it drops ownership and never overwrites you. It never writes during combat, it puts your value back before logout, and every write is verified by reading it back.

**Who benefits**: melee and combo-point DPS in M+ and raid; anyone above ~80 ms; casters who want cleaner end-of-cast chaining. Honest version: this is not an "install it and your DPS goes up" addon — it tunes feel. If you never noticed a problem, 400 was probably fine for you.

**FAQ, short version**: conflicts with other addons touching the same CVar (install only one); re-measures immediately on login / zone change / entering instances, then one drift check every 5 minutes; your value comes back when you disable it, because that value is yours. Retail 12.x only. It writes one local CVar — the same thing you can do with `/console` — and never touches combat logic, so it is not bannable material; still, never install anything that claims to play the game for you.

Feedback: [GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues). MIT license.

### 简体中文

装上一个插件，把你游戏里那个藏起来的设置——施法容限（`SpellQueueWindow`）——自动调成适合你专精和网速的值。你不用管它。

**「施法容限」到底是什么** ：老玩家都经历过：读条快结束了，你按了下一个技能，游戏「记住」了这次按键，读条一结束立刻接上。这个缓冲区就叫施法队列，`SpellQueueWindow` 是它的长度（中文客户端里这个选项就叫施法容限），含义是「在当前读条 / GCD 结束前多少毫秒按下的键还算数」。暴雪默认给 400ms——对 20~60ms 的人，它同时意味着：你手滑按错的那个技能，也在 0.4 秒内都算数。

**为什么有人觉得「卡手」，有人觉得「黏键」** ：窗口太小，按早了不算数，出现肉眼可见的空档；窗口太大，你按了 A 又改按 B，服务器先收到了 A。近战和连击点职业最敏感：GCD 短、按键频率高，400ms 差不多能盖住半个 GCD。所以它不该是固定值。

**这个插件做的事** ：按专精给手感基线，叠上世界延迟与自适应余量（按实测抖动算，30–150ms）取大；城里只用基线，副本 / 团本 / 野外跟延迟走；夹在 0~400ms 内；之后不再固定轮询，只在登录、换区、进副本团本或延迟真的漂移时重测。学到的延迟跨会话记住。

**面板里只有两个复选框** ：「启用自动调整」和「显示悬浮状态条」。余量、写入阈值、延迟来源、上下限、检测频率全部由插件按实测数据决定。屏幕上的数字会说话：数字本身是容限值，颜色说的是你的网络——正常白色，明显高于平时转红；悬停会写明为什么。

**它不是什么** ：不自动施法、不代按键、不做输出循环、不读战斗日志、不联网、无遥测。它改的就是你自己也能用 `/console SpellQueueWindow 200` 改的那个数字。所有权设计很讲究：只在仍是自己的值时归还，绝不覆盖你；战斗中不写；登出前归还；每次写入读回校验。

常见问题：与同类插件冲突（只装一个）；登录 / 换区 / 进本立刻重测，稳定后每 5 分钟一次漂移检查；关掉插件值会还原，因为那个值是你的。仅正式服 12.x。反馈走 [GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues)。MIT 许可。

### 繁體中文

裝上一個插件，把你遊戲裡那個藏起來的設定——施法容限（`SpellQueueWindow`）——自動調成適合你專精和網速的值。你不用管它。

**「施法容限」到底是什麼** ：老玩家都經歷過：詠唱快結束了，你按了下一個技能，遊戲「記住」了這次按鍵，詠唱一結束立刻接上。這個緩衝區就叫施法佇列，`SpellQueueWindow` 是它的長度（中文用戶端裡這個選項就叫施法容限），含義是「在目前詠唱 / GCD 結束前多少毫秒按下的鍵還算數」。暴雪預設給 400ms——對 20~60ms 的人，它同時意味著：你手滑按錯的那個技能，也在 0.4 秒內都算數。

**為什麼有人覺得「卡」，有人覺得「黏」** ：視窗太小，按早了不算數，出現肉眼可見的空檔；視窗太大，你按了 A 又改按 B，伺服器先收到了 A。近戰和連擊點職業最敏感：GCD 短、按鍵頻率高，400ms 差不多能蓋住半個 GCD。所以它不該是固定值。

**這個插件做的事** ：依專精給手感基線，疊上世界延遲與自適應餘量（依實測抖動計算，30–150ms）取大；城裡只用基線，副本 / 團本 / 野外跟延遲走；夾在 0~400ms 內；之後不再固定輪詢，只在登入、切換區域、進副本團本或延遲真的漂移時重測。學到的延遲跨登入記住。

**設定頁裡只有兩個核取方塊** ：「啟用自動調整」和「顯示浮動狀態列」。餘量、寫入門檻、延遲來源、上下限、偵測頻率全部由插件依實測資料決定。畫面上的數字會說話：數字本身是容限值，顏色說的是你的網路——正常白色，明顯高於平時轉紅；滑鼠停留會寫明為什麼。

**它不是什麼** ：不自動施法、不代按鍵、不做輸出循環、不讀戰鬥紀錄、不連網、無遙測。它改的就是你自己也能用 `/console SpellQueueWindow 200` 改的那個數字。所有權設計很講究：只在仍是自己的值時歸還，絕不覆蓋你；戰鬥中不寫；登出前歸還；每次寫入讀回驗證。

常見問題：與同類插件衝突（只裝一個）；登入 / 切換區域 / 進本立刻重測，穩定後每 5 分鐘一次漂移檢查；關掉插件值會還原，因為那個值是你的。僅正式服 12.x。回報走 [GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues)。MIT 授權條款。

## Changelog v2.0.0（Add File → Changelog，英文在前）

### English

- **New name**: `Tate_ASQ` → **AutoSpellQueue**; on Chinese clients it shows as 「施法容限」. Delete the old `AddOns\Tate_ASQ\` folder before installing (they fight over the same CVar).
- **Nothing to configure**: the options page went from 12 controls to **two checkboxes**. Headroom, write threshold, latency source and window limits are all computed from what the addon measures. The only manual escape hatch is `/asq base <50-400>`.
- **The algorithm took over what five settings used to do**: adaptive headroom from measured jitter (30–150 ms), an adaptive write threshold, and asymmetric latency smoothing (fast when worse, slow when better).
- **It actually follows your connection now**: re-measured on login, zone change, entering dungeons/raids and real latency drift — no fixed polling loop, one cheap drift check every 5 minutes once settled. The learned latency is remembered across sessions.
- **The UI stopped lying**: a failed write shows the reason; in failed / unavailable / disabled states the floating readout shows the state name, never a number.
- **Disabling in combat waits** until combat ends before restoring your value.
- **The floating readout's colour tells you about your connection**: white when normal (border included), red once clearly worse than your usual; failure / waiting / disabled keep their own colours. Hovering spells out why it is red.
- **Tooltip placement**: below the readout with a gap; flips above near the screen bottom, switches alignment near the left/right edges — never under your cursor, never off-screen.
- **Full enUS / zhCN / zhTW localization** (English clients no longer see internal key names).
- **Upgrading**: delete the old `Tate_ASQ` folder first; to keep old settings, copy `WTF\Account\…\SavedVariables\Tate_ASQ.lua` to `AutoSpellQueue.lua` (the client only loads the file named after the addon folder). Old manual base values migrate into `/asq base`.

### 简体中文

- **换名字了**：`Tate_ASQ` → **AutoSpellQueue**，中文客户端显示为「施法容限」。安装前**先删除旧的 `AddOns\Tate_ASQ\` 文件夹**（新旧会争抢同一个 CVar）。
- **不用设置了**：设置页从 12 个控件砍到 **2 个复选框**。余量、写入阈值、延迟来源、窗口上下限全部由插件按实测数据计算。唯一手动口子是 `/asq base <50-400>`。
- **算法接管了原来 5 个设置的活**：余量按实测抖动自适应（30–150ms）、写入阈值自适应、延迟平滑变差立刻跟 / 变好慢慢放。
- **它真的会跟着网速走**：登录、换区、进副本团本、延迟真实漂移时重测；不再固定轮询，稳定后每 5 分钟一次廉价漂移检查。学到的延迟跨会话记住。
- **界面不再说谎**：写不进去显示原因；失败 / 不可用 / 关闭时悬浮读数只显示状态名，绝不显示数字。
- **战斗中关闭会等脱战**再归还你的原值。
- **悬浮读数的颜色说的是你的网络**：正常白色（含边框），明显高于平时转红；失败 / 等待 / 关闭用各自状态色。悬停会写明为什么是红的。
- **悬停提示摆位**：挂在读数下方留间隙；贴屏幕底部自动翻到上方，贴左右边缘自动换对齐——绝不压鼠标、不出屏。
- **简体中文 / 繁體中文 / English 三语完整文案**。
- **升级**：先删旧 `Tate_ASQ` 文件夹；想保留旧设置，把 `WTF\Account\…\SavedVariables\Tate_ASQ.lua` 复制改名为 `AutoSpellQueue.lua`（客户端只加载与插件文件夹同名的存档文件）。旧手动基础值会迁移为 `/asq base` 覆盖值。

### 繁體中文

- **換名字了**：`Tate_ASQ` → **AutoSpellQueue**，中文用戶端顯示為「施法容限」。安裝前**先刪除舊的 `AddOns\Tate_ASQ\` 資料夾**（新舊會爭搶同一個 CVar）。
- **不用設定了**：設定頁從 12 個控制項砍到 **2 個核取方塊**。餘量、寫入門檻、延遲來源、視窗上下限全部由插件依實測資料計算。唯一手動出口是 `/asq base <50-400>`。
- **演算法接管了原本 5 個設定的活**：餘量依實測抖動自適應（30–150ms）、寫入門檻自適應、延遲平滑變差立刻跟 / 變好慢慢放。
- **它真的會跟著網速走**：登入、切換區域、進副本團本、延遲真實漂移時重測；不再固定輪詢，穩定後每 5 分鐘一次廉價漂移檢查。學到的延遲跨登入記住。
- **介面不再說謊**：寫不進去顯示原因；失敗 / 不可用 / 關閉時浮動讀數只顯示狀態名，絕不顯示數字。
- **戰鬥中關閉會等脫離戰鬥**再歸還你的原值。
- **浮動讀數的顏色說的是你的網路**：正常白色（含邊框），明顯高於平時轉紅；失敗 / 等待 / 關閉用各自狀態色。滑鼠停留會寫明為什麼是紅的。
- **停留提示擺位**：掛在讀數下方留間隙；貼畫面底部自動翻到上方，貼左右邊緣自動換對齊——絕不壓滑鼠、不出畫面。
- **簡體中文 / 繁體中文 / English 三語完整文案**。
- **升級**：先刪舊 `Tate_ASQ` 資料夾；想保留舊設定，把 `WTF\Account\…\SavedVariables\Tate_ASQ.lua` 複製改名為 `AutoSpellQueue.lua`（用戶端只載入與插件資料夾同名的存檔檔案）。舊手動基礎值會遷移為 `/asq base` 覆寫值。
