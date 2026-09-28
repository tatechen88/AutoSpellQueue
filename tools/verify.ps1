#Requires -Version 5.1
<#
.SYNOPSIS
    AutoSpellQueue 本地验证门禁：语法 -> 单元测试 -> 结构/版本一致性 ->（可选）打包。

.DESCRIPTION
    一条命令跑完全部门禁，任何一步失败都以非 0 退出并把原因打印清楚：
      1. node tools/check-syntax.mjs   luaparse(5.1) 解析 + 5.1/5.3 双兼容 lint
      2. node tools/run-tests.mjs      fengari(5.3) 跑 tests/spec_*.lua
      3. 结构与版本一致性（本脚本内）
         - 6 个运行期文件齐全
         - .toc 元数据与加载清单正确（加载顺序 = Locale/Formula/CVar/Core/Options）
         - .toc 的 Version == CHANGELOG 最新条目 == README 提到的版本
         - 没有残留的 Tate_ASQ* 旧文件名
         - 关键开发文件与 spec 文件存在
      4. -Package 时调用 tools/package.ps1 生成 dist/AutoSpellQueue-<version>.zip

.EXAMPLE
    pwsh tools/verify.ps1
    pwsh tools/verify.ps1 -Package
#>
[CmdletBinding()]
param(
    [switch]$Package,
    [string]$NodePath = ''
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$addonName = 'AutoSpellQueue'
$skipDirs = @('.git', 'node_modules', 'dist', '.scratch', '.vscode', '.idea')

# 运行期文件（发布包内容，顺序即 .toc 加载顺序）
$locale = "${addonName}_Locale.lua"
$formula = "${addonName}_Formula.lua"
$cvar = "${addonName}_CVar.lua"
$core = "$addonName.lua"
$options = "${addonName}_Options.lua"
$toc = "$addonName.toc"
$runtimeLua = @($locale, $formula, $cvar, $core, $options)
$runtimeAll = @($toc) + $runtimeLua

$script:Failures = @()
$script:StepFailures = 0

function Write-Head([string]$Text) {
    Write-Host ''
    Write-Host "==== $Text" -ForegroundColor Cyan
}

function Write-Ok([string]$Text) {
    Write-Host "  ok   $Text" -ForegroundColor Green
}

function Write-Bad([string]$Text) {
    Write-Host "  FAIL $Text" -ForegroundColor Red
    $script:Failures += $Text
}

function Test-Check([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) {
        Write-Ok $Name
    }
    else {
        if ([string]::IsNullOrEmpty($Detail)) { Write-Bad $Name } else { Write-Bad "$Name - $Detail" }
    }
}

# ------------------------------------------------------------------ header ---
Write-Host "AutoSpellQueue 本地验证门禁" -ForegroundColor White
Write-Host "  仓库根 : $root"

if ([string]::IsNullOrWhiteSpace($NodePath)) {
    $candidates = @()
    if ($env:ASQ_NODE) { $candidates += $env:ASQ_NODE }
    $candidates += 'D:\AI\Runtimes\NodeJS\node.exe'
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'nodejs\node.exe') }
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $NodePath = $candidate
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($NodePath)) {
        $command = Get-Command node -ErrorAction SilentlyContinue
        if ($command) { $NodePath = $command.Source }
    }
}
if ([string]::IsNullOrWhiteSpace($NodePath) -or -not (Test-Path -LiteralPath $NodePath -PathType Leaf)) {
    Write-Bad "找不到 node 可执行文件（可用 `$env:ASQ_NODE 或 -NodePath 指定）"
    Write-Host "结果: FAIL (1 项)" -ForegroundColor Red
    exit 1
}
Write-Host "  node   : $NodePath ($(& $NodePath --version))"

if (-not (Test-Path -LiteralPath (Join-Path $root 'tools\node_modules'))) {
    Write-Bad "tools/node_modules 不存在，先运行：npm --prefix tools install"
    Write-Host "结果: FAIL (1 项)" -ForegroundColor Red
    exit 1
}

# --------------------------------------------------------------- 1. syntax ---
Write-Head "[1/4] 语法检查 (luaparse 5.1 + 5.1/5.3 双兼容 lint)"
& $NodePath (Join-Path $root 'tools\check-syntax.mjs')
if ($LASTEXITCODE -ne 0) {
    $script:StepFailures++
    Write-Bad "check-syntax.mjs 退出码 $LASTEXITCODE"
}
else {
    Write-Ok "check-syntax.mjs 通过"
}

# ---------------------------------------------------------------- 2. tests ---
Write-Head "[2/4] 单元测试 (fengari 5.3, tests/spec_*.lua)"
& $NodePath (Join-Path $root 'tools\run-tests.mjs')
if ($LASTEXITCODE -ne 0) {
    $script:StepFailures++
    Write-Bad "run-tests.mjs 退出码 $LASTEXITCODE"
}
else {
    Write-Ok "run-tests.mjs 通过"
}

# ---------------------------------------------------- 3. structure/version ---
Write-Head "[3/4] 结构与版本一致性"

foreach ($file in $runtimeAll) {
    Test-Check "运行期文件存在: $file" (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf)
}

$requiredDev = @(
    'README.md', 'CHANGELOG.md', 'docs\ARCHITECTURE.md',
    'tools\check-syntax.mjs', 'tools\run-tests.mjs', 'tools\package.ps1', 'tools\verify.ps1',
    'tests\run.lua', 'tests\wow_stub.lua',
    'tests\spec_formula.lua', 'tests\spec_cvar.lua', 'tests\spec_core.lua',
    'tests\spec_locale.lua', 'tests\spec_options.lua'
)
foreach ($file in $requiredDev) {
    Test-Check "开发文件存在: $file" (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf)
}

$tocPath = Join-Path $root $toc
$version = ''
$tocText = ''
if (Test-Path -LiteralPath $tocPath -PathType Leaf) {
    $tocText = Get-Content -LiteralPath $tocPath -Raw -Encoding UTF8

    # --- 版本行
    if ($tocText -match '(?m)^##\s*Version:\s*(\S+)\s*$') {
        $version = $Matches[1]
        Test-Check ".toc 版本号格式 ($version)" ($version -match '^\d+\.\d+\.\d+$') '应为 x.y.z'
    }
    else {
        Write-Bad ".toc 缺少 ## Version: 行"
    }

    # --- Interface 行
    if ($tocText -match '(?m)^##\s*Interface:\s*(.+)$') {
        $interface = $Matches[1]
        $parts = @($interface -split ',' | ForEach-Object { $_.Trim() })
        $badParts = @($parts | Where-Object { $_ -notmatch '^\d{5,6}$' -or [int]$_ -lt 110000 })
        Test-Check "## Interface 是合法的构建号列表 ($interface)" ($parts.Count -gt 0 -and $badParts.Count -eq 0) ("异常项: " + ($badParts -join ', '))
    }
    else {
        Write-Bad ".toc 缺少 ## Interface: 行"
    }

    # --- SavedVariables 必须同时声明新旧变量（旧变量用于一次性导入）
    if ($tocText -match '(?m)^##\s*SavedVariables:\s*(.+)$') {
        $saved = $Matches[1]
        Test-Check "## SavedVariables 含 ${addonName}DB" ($saved -match "\b${addonName}DB\b") $saved
        Test-Check "## SavedVariables 含 Tate_ASQDB（legacy 导入依赖）" ($saved -match '\bTate_ASQDB\b') $saved
    }
    else {
        Write-Bad ".toc 缺少 ## SavedVariables: 行"
    }

    # --- 加载清单：必须是 5 个 .lua，顺序固定，文件都存在
    $listed = @()
    foreach ($line in ($tocText -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $listed += $trimmed
    }
    $orderOk = ($listed.Count -eq $runtimeLua.Count)
    if ($orderOk) {
        for ($i = 0; $i -lt $runtimeLua.Count; $i++) {
            if ($listed[$i] -ne $runtimeLua[$i]) { $orderOk = $false; break }
        }
    }
    Test-Check ".toc 只列出 5 个 .lua，且顺序为 Locale/Formula/CVar/Core/Options" $orderOk ("实际: " + ($listed -join ' -> '))
    foreach ($entry in $listed) {
        if ($entry -notmatch '\.lua$') {
            Write-Bad ".toc 清单里出现非 .lua 条目: $entry"
        }
        elseif ($runtimeLua -notcontains $entry) {
            Write-Bad ".toc 清单里有多余条目: $entry"
        }
    }
}
else {
    Write-Bad "找不到 $toc"
}

# --- 版本一致性：toc / CHANGELOG / README
$changelogPath = Join-Path $root 'CHANGELOG.md'
$readmePath = Join-Path $root 'README.md'
if (-not [string]::IsNullOrWhiteSpace($version)) {
    $escaped = [regex]::Escape($version)  # 例如 2\.0\.0

    if (Test-Path -LiteralPath $changelogPath -PathType Leaf) {
        $changelog = Get-Content -LiteralPath $changelogPath -Raw -Encoding UTF8
        # 接受 "## v2.0.0"、"## 2.0.0"、"## [v2.0.0]"、"### ... — 2026-09-28" 等写法
        $entryPattern = "(?m)^#{2,3}\s+\[?v?$escaped\]?(?![0-9.])"
        Test-Check "CHANGELOG.md 有 $version 的条目" ($changelog -match $entryPattern) "期望形如 ## v$version 或 ## [$version]"

        if ($changelog -match '(?m)^#{2,3}\s+\[?v?(\d+\.\d+\.\d+)\]?') {
            $latest = $Matches[1]
            Test-Check "CHANGELOG.md 最新条目 ($latest) == .toc ($version)" ($latest -eq $version) "新版本先写 CHANGELOG 再发版"
        }
        else {
            Write-Bad "CHANGELOG.md 里找不到任何 x.y.z 版本条目"
        }
    }
    else {
        Write-Bad "找不到 CHANGELOG.md"
    }

    if (Test-Path -LiteralPath $readmePath -PathType Leaf) {
        $readme = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
        # 数字两侧不能紧邻数字或点，避免 12.0.0 里的 2.0.0 误命中
        Test-Check "README.md 提到版本 $version" ($readme -match "(?<![0-9.])$escaped(?![0-9.])")
    }
    else {
        Write-Bad "找不到 README.md"
    }
}

# --- 残留旧文件名（只查文件名，不查正文：正文里出现旧名是升级说明的一部分）
$legacy = @()
$queue = New-Object System.Collections.Queue
$queue.Enqueue($root)
while ($queue.Count -gt 0) {
    $dir = $queue.Dequeue()
    $entries = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)
    foreach ($entry in $entries) {
        if ($entry.PSIsContainer) {
            if ($skipDirs -notcontains $entry.Name) { $queue.Enqueue($entry.FullName) }
        }
        elseif ($entry.Name -match '^Tate_ASQ') {
            $legacy += $entry.FullName.Substring($root.Length).TrimStart('\', '/')
        }
    }
}
Test-Check "没有残留 Tate_ASQ* 旧文件名" ($legacy.Count -eq 0) ("发现: " + ($legacy -join ', '))

# --- 发布清单（供人核对；打包脚本用的就是这一份）
Write-Host "  发布包含以下 $($runtimeAll.Count) 个文件（根目录必须是 ${addonName}/）:"
foreach ($file in $runtimeAll) { Write-Host "    ${addonName}/$file" }

# ----------------------------------------------------------------- 4. pack ---
if ($Package) {
    Write-Head "[4/4] 打包 (tools/package.ps1)"
    & (Join-Path $PSScriptRoot 'package.ps1')
    if ($LASTEXITCODE -ne 0) {
        $script:StepFailures++
        Write-Bad "package.ps1 退出码 $LASTEXITCODE"
    }
    else {
        Write-Ok "package.ps1 通过"
    }
}
else {
    Write-Head "[4/4] 打包（跳过，加 -Package 生成 dist/*.zip）"
}

# ---------------------------------------------------------------- summary ---
Write-Host ''
$total = $script:Failures.Count + $script:StepFailures
if ($total -eq 0) {
    Write-Host "结果: PASS  （语法 + 单测 + 结构/版本 全部通过）" -ForegroundColor Green
    exit 0
}
Write-Host "结果: FAIL  （$total 项）" -ForegroundColor Red
foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
if ($script:StepFailures -gt 0) { Write-Host "  - $($script:StepFailures) 个子步骤非 0 退出" -ForegroundColor Red }
exit 1
