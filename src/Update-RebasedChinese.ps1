<#
.SYNOPSIS
    Rebased 中文语言包配置工具
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$mod = Join-Path $PSScriptRoot 'src\modules'
. "$mod\discovery.ps1"
. "$mod\plugin.ps1"
. "$mod\config.ps1"
. "$mod\pack.ps1"

Write-Host ('=' * 55)
Write-Host '  Rebased 中文语言包配置工具'
Write-Host ('=' * 55)
Write-Host ''

Write-Host '如何定位 Rebased 和语言包？'
Write-Host ''
Write-Host '  [1] 自动搜索'
Write-Host '  [2] 手动指定路径'
Write-Host '  [0] 退出'
Write-Host ''

$mode = Read-Host '  输入数字'
if ($mode -eq '0') { Write-Host '已退出。'; return }
if ($mode -notin @('1','2')) { Write-Host '无效选择。'; return }

$rebasedPath = $null
$pluginPath = $null

if ($mode -eq '2') {
    Write-Host ''
    $rebasedPath = Read-Host '  输入 Rebased 目录路径'
    if (-not $rebasedPath -or -not (Test-Path "$rebasedPath\product-info.json")) {
        Write-Host "  路径无效" -ForegroundColor Red; Read-Host '按回车键退出'; return
    }
    Write-Host ''
    Write-Host '  语言包: [1] 自动搜索  [2] 手动指定'
    $pkMode = Read-Host '  输入数字'
    if ($pkMode -eq '2') {
        $pluginPath = Read-Host '  输入语言包目录路径'
        if (-not $pluginPath -or -not (Test-Path "$pluginPath\lib\localization-zh.jar")) {
            Write-Host "  路径无效" -ForegroundColor Red; Read-Host '按回车键退出'; return
        }
    }
}

Write-Host ''
Write-Host '正在搜索...'

# 找 Rebased
if ($rebasedPath) {
    $pi = Get-Content "$rebasedPath\product-info.json" -Raw | ConvertFrom-Json
    $exe = @("$rebasedPath\bin\rebased64.exe", "$rebasedPath\rebased64.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    $selectedRebased = [pscustomobject]@{ Path=$rebasedPath; Version=[string]$pi.version; Build=[string]$pi.buildNumber; DataDir=[string]$pi.dataDirectoryName; Vendor=[string]$pi.productVendor; Exe=$exe; IsExe=(Test-IsExeInstall $rebasedPath); IsZip=(-not (Test-IsExeInstall $rebasedPath)) }
} else {
    $rebasedList = Find-Rebased
    if ($rebasedList.Count -eq 0) { Write-Host '未找到 Rebased。' -ForegroundColor Red; Read-Host '按回车键退出'; return }
    Write-Host ''
    Write-Host "找到 $($rebasedList.Count) 个 Rebased:"
    for ($i = 0; $i -lt $rebasedList.Count; $i++) {
        Write-Host "  [$($i+1)] $($rebasedList[$i].Path)"
        Write-Host "      版本: $($rebasedList[$i].Version)  build $($rebasedList[$i].Build)"
    }
    Write-Host '  [0] 退出'
    $pick = Read-Host '  选择'
    if ($pick -eq '0') { return }
    $idx = [int]$pick - 1
    if ($idx -lt 0 -or $idx -ge $rebasedList.Count) { Write-Host '无效选择。'; return }
    $selectedRebased = $rebasedList[$idx]
}

# 找语言包
if ($pluginPath) {
    $xml = Read-JarPluginXml "$pluginPath\lib\localization-zh.jar"
    $sb = if($xml -match 'since-build="([^"]+)"'){$Matches[1]}else{''}
    $ub = if($xml -match 'until-build="([^"]+)"'){$Matches[1]}else{''}
    $selectedPlugin = [pscustomobject]@{ Path=$pluginPath; Jar="$pluginPath\lib\localization-zh.jar"; Version=(Get-XmlText $xml 'version'); SinceBuild=$sb; UntilBuild=$ub }
} else {
    $pluginList = Find-ChinesePlugin -ExcludeUnder $selectedRebased.Path
    if ($pluginList.Count -eq 0) { Write-Host '未找到语言包。' -ForegroundColor Red; Read-Host '按回车键退出'; return }
    Write-Host ''
    Write-Host "找到 $($pluginList.Count) 个中文语言包:"
    for ($i = 0; $i -lt $pluginList.Count; $i++) {
        Write-Host "  [$($i+1)] $($pluginList[$i].Path)"
        Write-Host "      版本: $($pluginList[$i].Version)  兼容: $($pluginList[$i].SinceBuild) ~ $($pluginList[$i].UntilBuild)"
    }
    Write-Host '  [0] 退出'
    $pick2 = Read-Host '  选择'
    if ($pick2 -eq '0') { return }
    $idx2 = [int]$pick2 - 1
    if ($idx2 -lt 0 -or $idx2 -ge $pluginList.Count) { Write-Host '无效选择。'; return }
    $selectedPlugin = $pluginList[$idx2]
}

$pluginsDir = Resolve-PluginDir $selectedRebased
$configPath = (Resolve-ConfigDir $selectedRebased).IdeGeneral

Write-Host ''
Write-Host ('=' * 55)
Write-Host '  确认信息'
Write-Host ('=' * 55)
Write-Host ''
Write-Host "  Rebased:       $($selectedRebased.Path)"
Write-Host "  版本:          $($selectedRebased.Version)  build $($selectedRebased.Build)"
Write-Host "  类型:          $(if($selectedRebased.IsZip){'ZIP 便携版'}else{'EXE 安装版'})"
Write-Host "  语言包:        $($selectedPlugin.Path)"
Write-Host "  语言包版本:    $($selectedPlugin.Version)"
Write-Host "  插件安装到:    $pluginsDir"
Write-Host "  配置写入:      $configPath"

$branch = Get-BuildBranch $selectedRebased.Build
Write-Host "  修补 until-build -> $branch.*  (自动)"

Write-Host ''
Write-Host ('=' * 55)
Write-Host '  选择操作:'
Write-Host ('=' * 55)
Write-Host ''
Write-Host '  [1] 安装语言包 + 配置中文 (推荐)'
Write-Host '  [2] 安装 + 配置 + 打包 ZIP'
Write-Host '  [3] 仅打包 ZIP'
Write-Host '  [4] 仅查看'
Write-Host '  [0] 退出'
Write-Host ''

$choice = Read-Host '  输入数字'
switch ($choice) {
    '4' { Write-Host '未做修改。'; return }
    '0' { return }
    '1' { $doInstall = $true; $doPack = $false }
    '2' { $doInstall = $true; $doPack = $true }
    '3' { $doInstall = $false; $doPack = $true }
    default { Write-Host '无效选择。'; return }
}

Write-Host ''
Write-Host '[1] 安全检查...'
if (Test-IsRunning $selectedRebased) { throw 'Rebased 正在运行！请先退出。' }
Write-Host '    通过'

if ($doInstall) {
    Write-Host ''
    Write-Host '[2] 安装中文语言包...'

    $backupDir = "$pluginsDir\_localization-zh-backups"
    $existing = "$pluginsDir\localization-zh"
    if (Test-Path $existing) { Backup-Existing $existing $backupDir }

    $copy = Install-Plugin -SourceDir $selectedPlugin.Path -TargetDir $pluginsDir

    Write-Host ''
    Write-Host "  修补 until-build -> $branch.*"
    Patch-UntilBuild -JarPath $copy.FinalJar -NewUntil "$branch.*"
    Write-Host "  审计副本 localization-zh-from-idea 保持原始 JAR"

    Write-Host ''
    Write-Host '[3] 配置中文...'
    Set-Locale $configPath 'zh-CN'

    Write-Host ''
    Write-Host ('=' * 55)
    Write-Host '  安装完成'
    Write-Host ('=' * 55)
    Write-Host ''
    Write-Host '  启动 Rebased 后:'
    Write-Host '    File -> Settings -> Appearance -> Language'
    Write-Host '    选择 Chinese (Simplified)'
}

if ($doPack) {
    Write-Host ''
    Write-Host ('=' * 55)
    Write-Host '  创建分发包...'
    Write-Host ('=' * 55)
    New-PortableZip -RebasedPath $selectedRebased.Path -Clean
    Write-Host ''
    Write-Host '  解压 ZIP 后运行 bin\rebased64.exe 即可。'
}

Read-Host '按回车键退出'

