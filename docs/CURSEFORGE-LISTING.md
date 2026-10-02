# CurseForge 商店页材料（上传用副本）

> 性质：`DESCRIPTION.md` 与 `CHANGELOG.md` 的发布用派生副本——事实仍以那两份为唯一出处，
> 本文件只做三件事：①语言顺序改为 English → 简体中文 → 繁體中文（CurseForge 规则：英文必须整段在前）；
> ②转成 CF 安全格式（`<…>` 改省略号；粗体两侧与全角字符之间加空格；仓库相对链接退化为纯文本）；
> ③集中在一处，上传时直接整段复制。改内容请回去改源头，再重新生成本文件。

## Summary（General → Summary，三条分别贴）

**English**

> Melee, ranged, tank or healer - each spec gets its own baseline, and an algorithm folds in your latency. No fixed number, no manual tuning. Two checkboxes.

简体中文

> 坦克、治疗、近战、远程各有节奏，每个专精都有自己的基准值，算法再叠上你的延迟；不是固定数字，也不用手动调。

繁體中文

> 坦克、治療、近戰、遠程各有節奏，每個專精都有自己的基準值，演算法再疊上你的延遲；不是固定數字，也不用你手動調。

## Description（Description 标签 → Markdown 模式 → 整段粘贴）

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

### 简体中文

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

### 繁體中文

- 依專精給施法容限手感基準（高 APM 近戰約 140ms、標準近戰約 150ms、坦克略高、法系約 240ms）。
- 疊上世界延遲與自適應餘量（依實測抖動計算，30–150ms），取較大的那個。
- 分場景：城裡只用基準值；副本與野外跟隨你的延遲。
- 夾在用戶端允許的 0–400ms 內。
- 登入、切換區域、進副本 / 團本、或延遲真的漂移時重測；學到的延遲跨登入記住。
- 只有兩個核取方塊：啟用、顯示浮動狀態列。
- 畫面上的數字是容限值，顏色說的是你的網路 —— 與你自己平時相比，正常白色、明顯變差轉紅。
- 所有權：只在仍是自己的值時歸還；你或別的插件改過，它絕不覆蓋。戰鬥中不寫，登出前歸還，每次寫入讀回驗證。
- 不自動施法、不按鍵、不做輸出循環、不讀戰鬥紀錄。它改的就是你自己也能用 /console SpellQueueWindow 200 改的那個值。

注意：不要與改動同一 CVar 的同類插件同時使用。

我的其他插件
- [CraftPro](https://www.curseforge.com/wow/addons/craftpro) —— 打開配方按一下按鈕，就得到一張材料清單：要什麼、有多少、還缺多少。
- [StockTake](https://www.curseforge.com/wow/addons/stocktake) —— 滑鼠移到物品上，提示資訊直接告訴你全帳號持有量（背包、銀行、含戰隊銀行、所有角色）。

回報：[GitHub Issues](https://github.com/tatechen88/AutoSpellQueue/issues) —— MIT 授權條款。

## Changelog v2.0.0（Add File → Changelog，英文在前）

### English

- New name: `Tate_ASQ` → AutoSpellQueue; on Chinese clients it shows as 「施法容限」. Delete the old `AddOns\Tate_ASQ\` folder before installing (they fight over the same CVar).
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

- 换名字了：`Tate_ASQ` → AutoSpellQueue，中文客户端显示为「施法容限」。安装前先删除旧的 `AddOns\Tate_ASQ\` 文件夹（新旧会争抢同一个 CVar）。
- 不用设置了：设置页从 12 个控件砍到 2 个复选框。余量、写入阈值、延迟来源、窗口上下限全部由插件按实测数据计算。唯一手动口子是 `/asq base <50-400>`。
- 算法接管了原来 5 个设置的活：余量按实测抖动自适应（30–150ms）、写入阈值自适应、延迟平滑变差立刻跟 / 变好慢慢放。
- 它真的会跟着网速走：登录、换区、进副本团本、延迟真实漂移时重测；不再固定轮询，稳定后每 5 分钟一次廉价漂移检查。学到的延迟跨会话记住。
- 界面不再说谎：写不进去显示原因；失败 / 不可用 / 关闭时悬浮读数只显示状态名，绝不显示数字。
- 战斗中关闭会等脱战再归还你的原值。
- 悬浮读数的颜色说的是你的网络：正常白色（含边框），明显高于平时转红；失败 / 等待 / 关闭用各自状态色。悬停会写明为什么是红的。
- 悬停提示摆位：挂在读数下方留间隙；贴屏幕底部自动翻到上方，贴左右边缘自动换对齐——绝不压鼠标、不出屏。
- 简体中文 / 繁體中文 / English 三语完整文案。
- 升级：先删旧 `Tate_ASQ` 文件夹；想保留旧设置，把 `WTF\Account\…\SavedVariables\Tate_ASQ.lua` 复制改名为 `AutoSpellQueue.lua`（客户端只加载与插件文件夹同名的存档文件）。旧手动基础值会迁移为 `/asq base` 覆盖值。

### 繁體中文

- 換名字了：`Tate_ASQ` → AutoSpellQueue，中文用戶端顯示為「施法容限」。安裝前先刪除舊的 `AddOns\Tate_ASQ\` 資料夾（新舊會爭搶同一個 CVar）。
- 不用設定了：設定頁從 12 個控制項砍到 2 個核取方塊。餘量、寫入門檻、延遲來源、視窗上下限全部由插件依實測資料計算。唯一手動出口是 `/asq base <50-400>`。
- 演算法接管了原本 5 個設定的活：餘量依實測抖動自適應（30–150ms）、寫入門檻自適應、延遲平滑變差立刻跟 / 變好慢慢放。
- 它真的會跟著網速走：登入、切換區域、進副本團本、延遲真實漂移時重測；不再固定輪詢，穩定後每 5 分鐘一次廉價漂移檢查。學到的延遲跨登入記住。
- 介面不再說謊：寫不進去顯示原因；失敗 / 不可用 / 關閉時浮動讀數只顯示狀態名，絕不顯示數字。
- 戰鬥中關閉會等脫離戰鬥再歸還你的原值。
- 浮動讀數的顏色說的是你的網路：正常白色（含邊框），明顯高於平時轉紅；失敗 / 等待 / 關閉用各自狀態色。滑鼠停留會寫明為什麼是紅的。
- 停留提示擺位：掛在讀數下方留間隙；貼畫面底部自動翻到上方，貼左右邊緣自動換對齊——絕不壓滑鼠、不出畫面。
- 簡體中文 / 繁體中文 / English 三語完整文案。
- 升級：先刪舊 `Tate_ASQ` 資料夾；想保留舊設定，把 `WTF\Account\…\SavedVariables\Tate_ASQ.lua` 複製改名為 `AutoSpellQueue.lua`（用戶端只載入與插件資料夾同名的存檔檔案）。舊手動基礎值會遷移為 `/asq base` 覆寫值。
