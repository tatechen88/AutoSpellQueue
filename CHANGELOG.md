# Changelog

> 版本号与 `AutoSpellQueue.toc` 的 `## Version` 必须一致（`tools/verify.ps1` 会检查）。日期为 ISO 格式。

## v2.0.0 — 2026-09-28

> 本版本尚未对外发布，日期为代码冻结日期；发布规划见 [`docs/CURSEFORGE.md`](docs/CURSEFORGE.md)。

### 更名

- 插件更名为 **AutoSpellQueue**（原 `Tate_ASQ` / Tate's AutoSpellQueue）。插件文件夹名、`.toc` 文件名与全部 `.lua` 文件前缀同步更改。
- 加载顺序重排为 `Locale → Formula → CVar → Core → Options`：计算、CVar 访问、运行时状态机拆成独立模块，模块间通过 `.toc` 传入的私有命名空间 `ns` 通信（不使用全局，唯一例外是 `_G.AutoSpellQueue` 供 `/dump` 排查）。
- Interface 列表更新为 `120000, 120001, 120005, 120007, 120100, 120105`（覆盖当前 12.x 正式服客户端）；保留 `## Category: Combat`。

### 按代码审查结论修复

1. **写入「pcall 假成功」** — 新增 `AutoSpellQueue_CVar.lua`，把 CVar 写入收敛到唯一一处，并且只有在 **API 没有拒绝** 且 **读回值与目标一致** 时才判定成功。API 返回 `nil`（未证实）必须读回验证；读回不一致报 `verify-failed`；另外拒绝非法值、只读 CVar、战斗中写入与缺少 API 的情况。旧实现把「`pcall` 没抛错」当成「写成功」，界面会显示一个并未生效的值。
2. **跨重载所有权丢失** — 所有权（`baseline` / `lastApplied` / `startedAt` / `schema`）持久化进存档，并在加载时校验；`PLAYER_LOGOUT` 归还玩家原值；若归还失败，存档里的所有权记录让下次登录仍能归还。
3. **战斗中的 pending 冲突** — 不再缓存待重放的 `pendingTarget`。战斗中只把状态标为 `pending` 且不写入；`PLAYER_REGEN_ENABLED` 重新读取**实时状态**再决策，避免把过期的战斗前快照硬套上去。这条规则对「应用」与「归还」一视同仁：战斗中禁用插件时，归还玩家原值同样推迟到脱战（旧实现会在战斗中直接写）。
4. **延迟变化不重算** — 启用期间每 15 秒重新评估一次（`Core.REFRESH_SECONDS`），登录后再按 2/5/10/20/40 秒补算直到客户端报出非零延迟；`CVAR_UPDATE` 触发 0.5 秒防抖重算。旧实现只在换区域/切专精时计算，网络延迟变了也不会更新。
5. **配置迁移死分支与无校验** — 迁移表 `MIGRATIONS` 改为真正按 `schemaVersion` 顺序执行；新增 `Core.Sanitize()` 对全部设置键做类型/范围/枚举校验，越界值 clamp、非法值回退默认并计数（`stats.repairs`），`minWindow > maxWindow`、坏掉的 `ownership`、越界坐标都会被修正；`Core.SetConfig` 只接受白名单键。
6. **未来 schema 不降级** — 存档 `schemaVersion` 高于当前版本时，原样保留全部字段并标记 `schemaFuture`，绝不把新版本写的数据改写成旧结构。
7. **UI 复杂与每秒全量刷新** — 设置界面重写为「总开关 + 状态卡 + 高级折叠」，状态真实反映 `applied` / `pending`（战斗）/ `error` / `unavailable` / `disabled`，写入失败直接显示原因；刷新只在面板可见时进行。旧实现每秒遍历全部控件（包括隐藏的）。
8. **缺测试与打包门禁** — 新增本地门禁：`tools/check-syntax.mjs`（luaparse，Lua 5.1 解析仓库内全部 `.lua`）、`tools/run-tests.mjs` + `tests/`（fengari，Lua 5.3 跑公式、CVar 写入校验与核心状态机的单元测试）、`pwsh tools/verify.ps1`（语法 → 单测 → 结构/版本一致性，可选 `-Package`）。打包脚本保证 zip 根目录恰好是 `AutoSpellQueue/` 且只含 6 个运行期文件。

### 破坏性变更

- **SavedVariables 更名**：`Tate_ASQDB` → `AutoSpellQueueDB`。
- **旧设置导入（有前提条件，务必看清）**：客户端**只加载与插件文件夹同名的存档文件**，旧设置写在 `WTF\Account\<账号>\SavedVariables\Tate_ASQ.lua` 里。删掉旧插件后没有任何东西会去读它，因此导入**不会自动发生**——需要把该文件复制/改名为同目录下的 `AutoSpellQueue.lua`（`.toc` 已声明 `Tate_ASQDB`，改名后首次登录即可导入配置项：启用状态、基础值模式、余量、上下限、迟滞、状态条字体/位置等），随后清空旧变量。所有权记录**不**继承（避免误写玩家当前值），baseline 会在下次接管时重新记录。不复制该文件也能正常使用，只是回到默认设置。
- **升级必须先删除旧的 `Tate_ASQ` 文件夹**：新旧是两个独立插件，会争抢同一个 CVar，且两个 `.toc` 都声明 `Tate_ASQDB`。

### 其他

- 错误不再静默：写入/读取失败一定会在聊天框提示（同一条错误 120 秒内不重复刷屏），并在状态里保留原因与时间。
- 玩家或其他插件改过值之后，本插件只释放所有权、**不覆盖**，且不重设 baseline——「归还玩家接管前的值」这个承诺保持不变。
- 迟滞（默认 10 ms）只在插件已经接管（存在 `lastApplied`）之后生效，避免接管前因抖动反复写入。
- 状态值统一为 `idle` / `disabled` / `applied` / `pending` / `error` / `unavailable`，界面与诊断输出共用。
- 「重置全部设置」现在也会清掉悬浮状态条位置（默认值表里 `statusBarPos` 是 `nil`，遍历默认值时会被跳过，旧实现因此漏掉这一项）。
- 新增斜杠命令：`/asq`、`/asq status`、`/asq reset`、`/asq unlock`。
- 界面与聊天文案提供 **enUS / zhCN / zhTW** 三套完整翻译（同一张源表生成，键集必然一致；其他语言客户端回退 enUS）。英文是真实文案而不是「回退成内部键名」——旧做法会让英文客户端显示 `STATE_APPLIED` 这类键名。设置面板标题统一为 `AutoSpellQueue`。
- 新增文档：`docs/ARCHITECTURE.md`（接口冻结契约）、`docs/CURSEFORGE.md`（发布规划）；README 中英双语重写，HANDOFF 更新为当前状态。
- 新增 `LICENSE`（MIT）与 `.pkgmeta`（BigWigs packager 配置）；文件换行统一为 LF（`.gitattributes`）。

## v1.0.2

- 設置頁開關改為滑塊式開關 UI，頁面更精簡。
- 新增「顯示狀態條」開關。
- README 新增繁體中文與英文說明。
- 下載連結更新至 v1.0.2。

## v1.0.1

- 修复状态条位置记忆：保存完整锚点信息，登入后正确恢复位置。
- 状态条位置记忆同时保持屏幕内约束，不会超出画面。
- 精简界面词条与无用函数，减少常驻内存。
- README 安装说明加入下载链接。

## v1.0.0

- 首个发布版本。
- 依职业/专精基础值自动调整 SpellQueueWindow。
- 城市 / 副本 / 野外不同计算方式。
- World 延迟优先，Home 回退。
- 悬浮状态条显示当前值，可拖动、左键打开设置。
- 中英文自动切换（zhCN / zhTW / enUS）。
