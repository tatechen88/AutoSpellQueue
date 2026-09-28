# HANDOFF

> 给接手本仓库的下一个 agent 或新会话。**最后重写：2026-09-28**（v2.0.0，已提交并推送）。
> 玩家向说明见 [`docs/DESCRIPTION.md`](docs/DESCRIPTION.md)；开发契约见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。
> 插件在中文客户端里叫**施法容限**（英文 `Auto Spell Queue`）。

## 这是什么

**AutoSpellQueue** —— 魔兽世界正式服（12.x）插件，自动维持 `SpellQueueWindow`。
6 个 `.lua` + 1 个 `.toc`，不是可独立运行的程序；判定标准是**游戏内加载后行为正确**。

## 当前状态

| 项 | 值 |
|---|---|
| 版本 | 2.0.0（`.toc` 的 `## Version` 是唯一权威） |
| 仓库 | `https://github.com/tatechen88/AutoSpellQueue`（2026-09-28 由 `Tate_ASQ` 改名，改名前需先解归档） |
| 分支状态 | `main` 与 origin 同步，工作区干净 |
| 本地门禁 | 语法 → 单测 → 结构/版本 → 打包，全绿（数量取当次 `pwsh tools/verify.ps1` 输出） |
| 本机安装 | 已装入 `D:\Game\World of Warcraft\_retail_\Interface\AddOns\AutoSpellQueue`（7 文件，与仓库逐文件哈希一致） |
| 玩家可见设置 | **只有 2 个复选框**（总开关 / 是否显示悬浮读数）+ 1 个「重置位置」按钮；旋钮全部改为算法，见 `docs/ARCHITECTURE.md` §3 |
| 设置页风格 | 与姊妹插件 **StockTake（数量盘点）** 一致：暴雪原生控件、零自绘、无滚动框 |
| 命名 | 显示名随语言（`ADDON_TITLE`）；设置分类**内部名/ID 恒为** `AutoSpellQueue`；存档 `AutoSpellQueueDB` |
| 配色 | 只有一套：正常=白、偏高=红、失败/等待/关闭=各自状态色；状态条边框与数字同色 |
| 旧插件 | 已移出扫描路径 → `Interface\AddOns.disabled\Tate_ASQ`（备份，可删） |
| 旧存档 | 已复制为 `WTF\Account\671932030#1\SavedVariables\AutoSpellQueue.lua`，原文件存为 `Tate_ASQ.lua.pre-v2.bak` |
| 尚未做 | **打 tag / 发 Release**、**CurseForge 上传**、下面「只需你点几下」里未打勾的项 |

## 你自己只需点这几下（约 5 分钟）

> 这些是**脚本验证不了**的：合成鼠标/光标移动触发不了 WoW 的悬停（Cua 的 `move_cursor` 动的是它自己的
> 虚拟光标）；切换客户端语言要重启客户端；战斗状态得你本人去打。其余项已由自动流程确认（见下一节）。

| # | 怎么做 | 应该看到什么 | 不对时告诉我 |
|---|---|---|---|
| 1 | 鼠标**悬停**在悬浮状态条上（别点） | 弹出提示：标题=施法容限、状态、当前值、目标值、延迟、世界/主城、专精、采样说明 | 提示空白 / 遮挡 / 文字被截断（截图给我） |
| 2 | 进战斗，然后在设置页**取消勾选**总开关 | 状态行变「等待脱战」；脱战后自动归还你的原值（`/dump GetCVar("SpellQueueWindow")` 应等于你原来的值） | 没等待 / 脱战后没归还 |
| 3 | 进一次副本或团本，出来后再看状态行与 `/asq status` | 状态行短暂显示采样中，然后回到「已应用」；`采样策略: 已固定` 会重新出现 | 一直停在采样中 / 值不更新 |
| 4 | 走几个场景：主城 → 野外 → 副本入口子地图 → 中立城（如沙塔斯） | 主城里目标值=专精基础值；野外/副本=基础值与「延迟+余量」取大；状态行数字颜色只在延迟真的变差时才转红 | 城里被抬高 / 场景判断错 |
| 5 | （可选）把客户端换成 enUS 或 zhTW 看一遍设置页 | 标题与两个复选框标签不截断、不重叠 | 文字被截断（截图） |
| 6 | 体感：打一会儿木桩 | 断档/误排比默认 400 少 | 觉得黏键 → 基础值表可调（`/asq base`） |

> 第 5 项若嫌麻烦可以跳过：三语都有用例断言换行与截断（`spec_options`），真机只差字体渲染这一层。
> 第 6 项本来就是**调参默认值**，按体感调整不算 bug。

## 已自动确认（2026-09-28，真机 2560×1440 / zhCN 客户端，附证据）

| 项 | 结果 | 证据 |
|---|---|---|
| `/dump GetCVar("SpellQueueWindow")` 等于面板目标 | **220 = 220** | 聊天 `CVAR 220`；状态行 `已应用 · 220 ms`（银月城） |
| `C_CVar.GetCVarInfo("SpellQueueWindow")` 的返回值 | **7 个**：`value="220"`、`default="400"`，随后 5 个布尔 = `true,false,false,false,false` | `GI 1..7` 逐项打印（聊天截图） |
| 上面的布尔位与 `CVar:Info()` 的假设是否一致 | **一致**：`isStoredAccount=true`（Config.wtf 账号级 ✓）、`isStoredCharacter=false`、`isLocked=false`、`isSecure=false`、`isReadOnly=false` → **写入不会被拒** | 同上 + `AutoSpellQueue_CVar.lua:114-125` 的解包顺序 |
| 写入是否会被拒 | **不会**：现值 220 ≠ 默认 400，就是插件写进去的（写入带读回校验） | 同上 + 面板「已应用」 |
| 状态条拖动 + 位置保存 | 拖动生效：`1995,-207` → `1790,-527`（位移比 ≈0.83 = UI 缩放） | 拖动前后 `/run print(AutoSpellQueueDB.statusBarPos...)` |
| 位置跨 `/reload` 持久化 | `1790,-527` 保留 | reload 后再打印 |
| `/asq resetpos` 复位 | 位置清空（`nil nil`）→ 回到默认锚点 | 复位后打印 + 聊天确认行 |
| 数字/边框配色 | 正常=白字白框；偏高=红字红框 | 实机截图（红框用临时阈值探针触发，已还原） |
| 统一配色 | 状态条、提示标题、独立窗口、聊天前缀同源；品牌绿已移除 | 截图 + `spec_options` 用例 |
| 中文界面名 | 插件列表 / 设置页标题 / 聊天前缀都是**施法容限** | 三张实机截图 |
| 采样策略真机生效 | `采样策略: 已固定：每 300 秒只做一次漂移检查`；`记住的延迟: 29 ms`；`上次计算在 338 秒前` | `/asq status` 聊天输出 |
| 设置页渲染 | StockTake 风格（标题 + 一行状态 + 2 复选框 + 重置按钮），无滚动框 | 实机截图 |

## 怎么验证（贴真实输出，别写「应该没问题」）

```powershell
npm --prefix tools install       # 一次性；本机没有 lua/luac，测试用 Node + fengari
node tools/check-syntax.mjs      # 语法 + 5.1/5.3 双兼容 lint
node tools/run-tests.mjs         # 假客户端里真跑 6 个运行期文件
pwsh tools/verify.ps1            # 语法 → 单测 → 结构/版本一致性
pwsh tools/verify.ps1 -Package   # 追加 dist/AutoSpellQueue-<version>.zip
```

失败排查顺序：语法 → `tests/spec_*.lua` 里失败的用例 → `tests/wow_stub.lua` 的环境建模是否与真实客户端一致
（桩必须**忠实到会报错**：本项目两次靠桩自己报出真 bug）。

### 界面「看不见 / 排版乱」时怎么定位（2026-09-28 实战流程）

不要猜。本机装了 **Cua Driver**（`cua on` → `cua do ...` → 用完 `cua off`），可以截屏并往游戏里发按键/点击，
**直接在真机上复现**：

1. `cua do bring_to_front '{"pid":<Wow.exe 的 pid>}'` 把游戏切前台；
2. `cua do click '{"pid":...,"x":...,"y":...}'` 点悬浮状态条（左键 = 打开设置面板）；
3. 聊天里按 Enter → `type_text` 执行 `/run local p=AutoSpellQueueOptionsPanel; print("PANEL", p:GetWidth(), p:GetHeight(), p:GetNumPoints(), p:IsShown())`；
4. `cua do get_desktop_state '{}'` 取 base64 PNG → 解码 → 看聊天输出。

那次的输出 `PANEL 665 604 2 true` / `SCROLL 639x602` / **`CHILD 0x440`** 一次锁定了根因（整页空白 = 滚动子框宽度 0）。
**悬停提示无法这样验证**（合成光标不触发 OnEnter），只能由人眼看。

> **注入长命令会被截断（2026-09-28 实测，两次踩到）**：`type_text` 是逐字符 PostMessage。
> 18 字符的 `/run print("PING")` 正常；308 字符的命令到客户端只剩前半截 →
> `arguments expected near '<eof>'`；430 字符那条 → `'then' expected near '='`（同一条文本本地
> `luaparse` 解析是通过的，所以**本地查语法查不出截断，长度才是真正的约束**）。
> 两次都在玩家屏幕上留了 Blizzard 的 Lua 错误框，需要手动关掉。
> **规矩**：注入的 `/run` 命令保持短（<100 字符）；更长的探针写成临时插件的一条 `/命令` 再调用。
>
> **一眼判断错误框是不是本插件造成的**：看 Stack。若里面只有 `Interface/AddOns/Blizzard_*`、
> 没有任何 `Interface/AddOns/AutoSpellQueue/`，那就是探针/其它插件的问题，与本插件无关。

## 必须保持的不变量

写入必须读回校验、所有权只在仍是自己的值时归还、战斗中不写也不重放旧目标、登出归还、未来 schema 不降级、
玩家可见设置只有 2 个、配置白名单、面板 ≤6 行且每行 ≤60 字节、只有一套配色、显示名随语言而内部名恒定。
完整列表与对应测试见 [`tests/REGRESSIONS.md`](tests/REGRESSIONS.md)——**改动前先读它**。

## 下一步

1. 走一遍上面「只需你点几下」的清单（本机已安装，直接上号）。有异常把 `/asq status` 输出贴回来。
2. 确认无误后发版：
   `gh release create v2.0.0 dist/AutoSpellQueue-2.0.0.zip --title "v2.0.0" --notes-file CHANGELOG.md`
   （在此之前**不要**发，避免发布未经游戏内验证的构建。）
3. 走 [`docs/CURSEFORGE.md`](docs/CURSEFORGE.md)：§1 命名检查 → §2 素材 → 创建项目 → 在 `.toc`
   **新增** `## X-Curse-Project-ID: <真实 ID>` → 按 §4 打包上传。
4. 文档改动请遵守 [`docs/README.md`](docs/README.md) 的「唯一出处」规则。

## 已知边界

- 设置页的**真实渲染**（Blizzard Settings 画布、tooltip、字体）无法离线验证；测试覆盖逻辑与文本。
- 独立回退窗口（无 Settings API 时的路径）**从未在真机跑过**：代码与主路径共用同一套构件，但它只在
  客户端缺少 Settings API 时出现。目前未发现该 API 缺失的客户端，故此路径按「代码审阅 + 复用构件」对待。
- 悬停提示、三语真实字体换行、战斗内禁用→脱战归还需要真人客户端。
- 旧存档导入依赖玩家手动复制文件（见 `ARCHITECTURE.md` §4「SavedVariables 与迁移前提」），
  这是客户端机制决定的，不是 bug。
- 客户端自身延迟读数的刷新节奏**没有实测结论**，因此文档不再写具体秒数（只说明它是周期性刷新）。
