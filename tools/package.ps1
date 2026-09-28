#Requires -Version 5.1
<#
.SYNOPSIS
    生成 AutoSpellQueue 发布包（dist/AutoSpellQueue-<version>.zip）。

.DESCRIPTION
    zip 根目录必须**正好**是 AutoSpellQueue/，且只含 6 个运行期文件
    （1 个 .toc + 5 个 .lua）。tests/、tools/、docs/ 一律不进包。
    这一条由本脚本保证，并在写完后重新打开 zip 逐条核对（入口数量、路径、
    大小），任何不一致都以非 0 退出。

    用 .NET ZipArchive 而不是 Compress-Archive，是为了控制入口名使用 "/"
    分隔符——部分解压器/客户端对 "\\" 分隔的 zip 会解出错误的目录层级。

.PARAMETER Version
    覆盖版本号（默认取 AutoSpellQueue.toc 的 ## Version）。

.PARAMETER OutputDirectory
    输出目录，默认 <仓库根>/dist。

.EXAMPLE
    pwsh tools/package.ps1
    pwsh tools/package.ps1 -Version 2.0.0
#>
[CmdletBinding()]
param(
    [string]$Version = '',
    [string]$OutputDirectory = '',
    # zip 内条目的时间戳，写法是「本地墙钟」yyyy-MM-ddTHH:mm:ss（不带时区偏移）。
    # 为什么要固定它：ZipArchive.CreateEntry() 默认写「打包那一刻」，同样的内容
    # 每次打包都会得到不同的 zip 哈希，无法用来判断「这是不是我验证过的那份产物」。
    #
    # 关于时区（实测 .NET 行为，见 tests/REGRESSIONS.md）：zip 的 DOS 时间字段按
    # 本地墙钟存储，赋值时给的偏移量会被丢弃——传 +00:00 / -05:00 / 本地
    # DateTime 三种写法，读回来都是同一个墙钟值。所以这里必须给墙钟，不能给
    # 「某个 UTC 瞬间」；反过来，同一个墙钟在任何时区都写出同样的字节，因此
    # 跨机器打包同一份内容也能得到相同的 zip。
    # 想恢复「真实打包时间」可以传 -Timestamp (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')，
    # 但那会让每次打包的哈希都不同。
    [string]$Timestamp = '2000-01-01T00:00:00'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$addonName = 'AutoSpellQueue'
$manifest = @(
    "$addonName.toc",
    "${addonName}_Locale.lua",
    "${addonName}_Formula.lua",
    "${addonName}_Latency.lua",
    "${addonName}_CVar.lua",
    "$addonName.lua",
    "${addonName}_Options.lua"
)

function Fail([string]$Message) {
    Write-Host "package: FAIL - $Message" -ForegroundColor Red
    exit 1
}

function Info([string]$Message) {
    Write-Host $Message
}

# ---------------------------------------------------------------- version ---
if ([string]::IsNullOrWhiteSpace($Version)) {
    $tocPath = Join-Path $root "$addonName.toc"
    if (-not (Test-Path -LiteralPath $tocPath)) { Fail "找不到 $addonName.toc" }
    $tocText = Get-Content -LiteralPath $tocPath -Raw -Encoding UTF8
    if ($tocText -notmatch '(?m)^##\s*Version:\s*(\S+)\s*$') {
        Fail "AutoSpellQueue.toc 里没有 ## Version: 行"
    }
    $Version = $Matches[1]
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Fail "版本号格式不对：'$Version'（应为 x.y.z）"
}

# ------------------------------------------------------------------ inputs ---
$missing = @()
foreach ($file in $manifest) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf)) {
        $missing += $file
    }
}
if ($missing.Count -gt 0) {
    Fail ("缺少运行期文件: " + ($missing -join ', '))
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root 'dist'
}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$zipPath = Join-Path $OutputDirectory "$addonName-$Version.zip"

Info "AutoSpellQueue 打包"
Info "  仓库根 : $root"
Info "  版本   : $Version"
Info "  产物   : $zipPath"
Info "  清单   :"
foreach ($file in $manifest) {
    $size = (Get-Item -LiteralPath (Join-Path $root $file)).Length
    Info ("    {0,-42} {1,8} B" -f "$addonName/$file", $size)
}

# ------------------------------------------------------------------- build ---
Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

# Entry timestamps are pinned. ZipArchive.CreateEntry() defaults to "now", which
# made the archive hash change on every run even when every byte inside was
# identical - useless for "is this the artifact we validated?". A fixed wall
# clock makes the zip reproducible: same content in, same bytes out.
if ($Timestamp -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$') {
    Fail "-Timestamp 必须是本地墙钟 yyyy-MM-ddTHH:mm:ss（不要带时区偏移，zip 的 DOS 字段存不了偏移）: '$Timestamp'"
}
$entryWallClock = [datetime]::ParseExact(
    $Timestamp, 'yyyy-MM-ddTHH:mm:ss',
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::None)

# 打包一份 zip，返回「条目名 -> 工作区文件 sha256」。
# 写成函数是为了能连打两份，做「产物可复现」自检。
function New-PackageArchive([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }
    $hashes = [ordered]@{}
    $zip = [System.IO.Compression.ZipFile]::Open(
        $Path, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $manifest) {
            $entryName = "$addonName/$file"
            $entry = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
            # 赋墙钟：DOS 字段只存墙钟、且不带时区（原始字节实测 dosTime=0x0000,
            # dosDate=0x2821 -> 2000-01-01 00:00:00，且 extra field 长度为 0）
            $entry.LastWriteTime = $entryWallClock
            $stream = $entry.Open()
            try {
                $bytes = [System.IO.File]::ReadAllBytes((Join-Path $root $file))
                $stream.Write($bytes, 0, $bytes.Length)
            }
            finally {
                $stream.Dispose()
            }
            $hashes[$entryName] = (Get-FileHash -LiteralPath (Join-Path $root $file) -Algorithm SHA256).Hash.ToLower()
        }
    }
    finally {
        $zip.Dispose()
    }
    return $hashes
}

$fileHashes = New-PackageArchive $zipPath

# 复现性自检：同样的内容再打一份，逐字节比较。这条能抓住任何「隐藏的非确定性」
# （额外的 extra field、条目顺序、压缩状态泄漏等）。注意「时间戳写成打包那一刻」
# 这类回归由下面的逐条墙钟断言负责——DOS 时间粒度是 2 秒，两次连续打包有可能
# 落在同一格里，光靠比较哈希抓不住。
$reproPath = Join-Path ([System.IO.Path]::GetTempPath()) ("asq-repro-" + [guid]::NewGuid().ToString('N') + ".zip")
try {
    [void](New-PackageArchive $reproPath)
    $firstHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    $secondHash = (Get-FileHash -LiteralPath $reproPath -Algorithm SHA256).Hash
    if ($firstHash -ne $secondHash) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        Fail ("产物不可复现：同样的内容两次打包得到不同的 zip（{0} vs {1}）——检查是否有额外的 extra field / 条目顺序变化；未通过的产物已删除" -f `
                $firstHash.Substring(0, 16), $secondHash.Substring(0, 16))
    }
}
finally {
    if (Test-Path -LiteralPath $reproPath) { Remove-Item -LiteralPath $reproPath -Force }
}

# ------------------------------------------------------------------ verify ---
$expected = @($manifest | ForEach-Object { "$addonName/$_" })
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
$entryHashes = [ordered]@{}
$entryWalls = @()
try {
    $actual = @($archive.Entries | ForEach-Object { $_.FullName })
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($entry in $archive.Entries) {
            $stream = $entry.Open()
            try {
                $entryHashes[$entry.FullName] =
                    ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLower()
            }
            finally {
                $stream.Dispose()
            }
            # 读回来的是墙钟（Kind=Unspecified），只比较墙钟，不碰 UTC 换算
            $entryWalls += [pscustomobject]@{
                Name = $entry.FullName
                Wall = $entry.LastWriteTime.DateTime
            }
        }
    }
    finally {
        $sha.Dispose()
    }
}
finally {
    $archive.Dispose()
}

$problems = @()
if ($actual.Count -ne $expected.Count) {
    $problems += "zip 入口数量 $($actual.Count)，应为 $($expected.Count)"
}
foreach ($name in $expected) {
    if ($actual -notcontains $name) { $problems += "zip 缺少 $name" }
}
foreach ($name in $actual) {
    if ($expected -notcontains $name) { $problems += "zip 多出不该有的入口 $name" }
    if ($name.StartsWith('/') -or $name.Contains('\')) { $problems += "入口名分隔符不合法: $name" }
    if ($name -match '(^|/)(tests|tools|docs)/') { $problems += "发布包里混入了开发目录: $name" }
}
# 内容必须与工作区逐字节一致：这是发布候选真正的指纹
foreach ($name in $expected) {
    if ($entryHashes[$name] -ne $fileHashes[$name]) {
        $problems += "zip 内 $name 的内容与工作区文件不一致"
    }
}
# 时间戳必须全部等于配置的墙钟常量（防回归：默认值一旦退回“打包那一刻”，
# zip 哈希就会每次不同，而这件事只有这条断言能可靠地抓住）
foreach ($item in $entryWalls) {
    if ($item.Wall -ne $entryWallClock) {
        $problems += ("{0} 的条目时间 {1:yyyy-MM-dd HH:mm:ss} != 约定墙钟 {2}" -f `
            $item.Name, $item.Wall, $Timestamp)
    }
}

if ($problems.Count -gt 0) {
    foreach ($problem in $problems) { Write-Host "  FAIL $problem" -ForegroundColor Red }
    # 校验没过的产物不留下来：dist/ 里出现一个「看起来像发布候选」的 zip
    # 比没有产物危险得多。
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Info "已删除未通过校验的产物: $zipPath"
    Fail "zip 结构/内容/时间戳校验未通过"
}

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
$zipSize = (Get-Item -LiteralPath $zipPath).Length
Info ""
Info "zip 内条目 sha256（发布候选的稳定指纹；zip 自身哈希已通过固定墙钟变得可复现）:"
foreach ($name in $expected) {
    Info ("    {0}  {1}" -f $fileHashes[$name], $name)
}
Info ""
Info ("zip 内容（$($actual.Count) 个入口，根目录 = $addonName/；条目墙钟固定为 {0}，已逐条核对）:" -f $Timestamp)
foreach ($item in $entryWalls) {
    Info ("    {0,-40}  mtime={1:yyyy-MM-dd HH:mm:ss}" -f $item.Name, $item.Wall)
}
Info ""
Info ("结果: OK  $zipPath  ({0} B, sha256 {1})" -f $zipSize, $hash)
exit 0
