<#
.SYNOPSIS
    Rebased 中文语言包配置工具
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$mod = Join-Path $PSScriptRoot 'modules'
. (Join-Path $mod 'discovery.ps1')
. (Join-Path $mod 'plugin.ps1')
. (Join-Path $mod 'config.ps1')
. (Join-Path $mod 'migration.ps1')
. (Join-Path $mod 'pack.ps1')

function Show-RebasedList {
    param([array]$Items)
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $type = if ($Items[$i].IsZip) { 'ZIP 便携版' } else { 'EXE 安装版' }
        Write-Host "  [$($i + 1)] $($Items[$i].Path)"
        Write-Host "      版本: $($Items[$i].Version)  build $($Items[$i].Build)  类型: $type"
    }
}

function Select-Rebased {
    param(
        [array]$Items,
        [string]$Prompt
    )

    while ($true) {
        $pick = Read-Host $Prompt
        if ($pick -eq '0') { return $null }
        if ($pick -eq 'M') { return (Read-RebasedPath) }
        if ($pick -match '^\d+$' -and $pick.Length -lt 10) {
            $index = [int]$pick - 1
            if ($index -ge 0 -and $index -lt $Items.Count) { return $Items[$index] }
        }
        Write-Host '无效选择，请输入列表中的编号、M 或 0。'
    }
}

function Invoke-MigrationMode {
    Write-Host ''
    Write-Host ('=' * 55)
    Write-Host '  迁移旧版中文配置到新版 Rebased'
    Write-Host ('=' * 55)
    Write-Host ''
    Write-Host '正在自动搜索 Rebased...'

    $rebasedList = @(Find-Rebased)
    if ($rebasedList.Count -lt 2) {
        Write-Host "自动搜索找到 $($rebasedList.Count) 个 Rebased，可输入 M 手动指定旧版或新版路径。"
    }

    Write-Host ''
    Write-Host "找到 $($rebasedList.Count) 个 Rebased:"
    Show-RebasedList $rebasedList
    Write-Host '  [M] 手动输入 Rebased 安装目录或上一级目录'
    Write-Host '  [0] 退出'
    Write-Host ''

    $old = Select-Rebased $rebasedList '选择旧版本编号'
    if (-not $old) { return }
    $new = Select-Rebased $rebasedList '选择新版本编号'
    if (-not $new) { return }
    if ($old.Path.Equals($new.Path, [StringComparison]::OrdinalIgnoreCase)) {
        throw '旧版本和新版本不能是同一个目录。'
    }

    Write-Host ''
    Write-Host '确认迁移信息:'
    Write-Host "  旧版本: $($old.Path)"
    Write-Host "          $($old.Version) / $($old.Build)"
    Write-Host "  新版本: $($new.Path)"
    Write-Host "          $($new.Version) / $($new.Build)"
    if ((Get-BuildBranch $old.Build) -ne (Get-BuildBranch $new.Build)) {
        Write-Warning '新旧版本 build 分支不同，脚本会按新版分支重新修补中文插件。'
    }

    if (Test-IsRunning $old) { throw '旧版 Rebased 正在运行，请先退出。' }
    if (Test-IsRunning $new) { throw '新版 Rebased 正在运行，请先退出。' }

    Write-Host ''
    Write-Host '[1] 迁移中文插件和中文配置...'
    $result = Migrate-RebasedChinese -SourceRebased $old -TargetRebased $new

    Write-Host ''
    Write-Host ('=' * 55)
    Write-Host '  迁移完成'
    Write-Host ('=' * 55)
    Write-Host "  插件来源: $($result.SourcePlugin)"
    Write-Host "  插件目标: $($result.TargetPlugin)"
    Write-Host "  配置文件: $($result.ConfigPath)"
    Write-Host "  until-build: $($result.BuildBranch).*"
    Write-Host ''
    Write-Host '新版 Rebased 的核心文件没有被覆盖。'
    Read-Host '按回车键退出'
}

function Read-InstallationPath {
    param([ValidateSet('Rebased', 'ChinesePlugin')][string]$Kind)

    while ($true) {
        $prompt = if ($Kind -eq 'Rebased') { '  输入 Rebased 安装目录或上一级目录' } else { '  输入 IDEA 安装目录、上一级目录或语言包路径' }
        $path = Read-Host $prompt
        if ($path.Trim() -eq '0') { return $null }
        try {
            $items = @(if ($Kind -eq 'Rebased') { Find-RebasedAtPath $path } else { Find-ChinesePluginAtPath $path })
        }
        catch {
            Write-Host "  查找失败: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host '  [1] 重新输入路径'
            Write-Host '  [0] 退出'
            do {
                $retry = Read-Host '  输入数字'
                if ($retry -notin @('0', '1')) { Write-Host '  无效选择，请输入 1 或 0。' }
            } while ($retry -notin @('0', '1'))
            if ($retry -eq '0') { return $null }
            continue
        }

        if ($items.Count -eq 1) {
            Write-Host "  已找到: $($items[0].Path)"
            return $items[0]
        }
        Write-Host "  找到 $($items.Count) 个匹配，请根据完整路径和版本选择:"
        if ($Kind -eq 'Rebased') { Show-RebasedList $items }
        else {
            for ($i = 0; $i -lt $items.Count; $i++) {
                Write-Host "  [$($i + 1)] $($items[$i].Path)"
                Write-Host "      版本: $($items[$i].Version)  兼容: $($items[$i].SinceBuild) ~ $($items[$i].UntilBuild)"
            }
        }
        Write-Host '  [M] 重新输入路径'
        Write-Host '  [0] 退出'
        while ($true) {
            $pick = Read-Host '  选择编号'
            if ($pick -eq '0') { return $null }
            if ($pick -eq 'M') { break }
            if ($pick -match '^\d+$' -and $pick.Length -lt 10) {
                $index = [int]$pick - 1
                if ($index -ge 0 -and $index -lt $items.Count) { return $items[$index] }
            }
            Write-Host '  无效选择，请输入列表中的编号、M 或 0。'
        }
    }
}

function Read-RebasedPath {
    Write-Host ''
    Write-Host '  支持 Rebased 安装目录（内含 product-info.json），或它的上一级目录。'
    Write-Host '  例如 C:\Apps、C:\Apps\Rebased、C:\Apps\rebased.win；输入 0 退出。'
    Write-Host '  会检查下一层包含 rebased 的文件夹或有产品信息的文件夹；多个结果会列出供选择。'
    return (Read-InstallationPath -Kind Rebased)
}

function Read-ChinesePlugin {
    Write-Host ''
    Write-Host '  输入 IDEA 安装目录或上一级目录，脚本会自动定位中文语言包。'
    Write-Host '  路径层级示例（以下任意一层都可以）:'
    Write-Host '    C:\Apps'
    Write-Host '    C:\Apps\IntelliJ IDEA 2026.2.3'
    Write-Host '    C:\Apps\IntelliJ IDEA 2026.2.3\plugins'
    Write-Host '    C:\Apps\IntelliJ IDEA 2026.2.3\plugins\localization-zh'
    Write-Host '  也支持 lib 目录或 localization-zh.jar 文件路径；输入 0 退出。'
    Write-Host '  会检查下一层 IntelliJ IDEA 文件夹（也通过产品信息识别 IDEA）；多个结果会列出供选择。'
    return (Read-InstallationPath -Kind ChinesePlugin)
}

function Invoke-SyncMode {
    Write-Host ''
    Write-Host ('=' * 55)
    Write-Host '  同步中文语言包'
    Write-Host ('=' * 55)
    Write-Host ''
    Write-Host '如何定位 Rebased 和语言包？'
    Write-Host ''
    Write-Host '  [1] 自动搜索'
    Write-Host '  [2] 手动指定路径'
    Write-Host '  [0] 退出'
    Write-Host ''

    $searchMode = Read-Host '  输入数字'
    if ($searchMode -eq '0') { return }
    if ($searchMode -notin @('1', '2')) { throw '无效选择。' }

    $selectedRebased = $null
    $selectedPlugin = $null

    if ($searchMode -eq '2') {
        $selectedRebased = Read-RebasedPath
        if (-not $selectedRebased) { return }
        Write-Host ''
        Write-Host '  语言包: [1] 自动搜索  [2] 手动指定'
        $pluginMode = Read-Host '  输入数字'
        if ($pluginMode -eq '2') {
            $selectedPlugin = Read-ChinesePlugin
            if (-not $selectedPlugin) { return }
        }
    }

    Write-Host ''
    Write-Host '正在搜索...'

    if (-not $selectedRebased) {
        $rebasedList = @(Find-Rebased)
        if ($rebasedList.Count -eq 0) {
            Write-Host '自动搜索未找到 Rebased，请手动指定安装目录或上一级目录。'
            $selectedRebased = Read-RebasedPath
        }
        else {
            Write-Host ''
            Write-Host "找到 $($rebasedList.Count) 个 Rebased:"
            Show-RebasedList $rebasedList
            Write-Host '  [M] 手动输入 Rebased 安装目录或上一级目录'
            Write-Host '  [0] 退出'
            $selectedRebased = Select-Rebased $rebasedList '选择 Rebased 编号'
        }
        if (-not $selectedRebased) { return }
    }

    if (-not $selectedPlugin) {
        $pluginList = @(Find-ChinesePlugin -ExcludeUnder $selectedRebased.Path)
        if ($pluginList.Count -eq 0) {
            Write-Host '自动搜索未找到中文语言包，请手动指定 IDEA 安装目录。'
            $selectedPlugin = Read-ChinesePlugin
            if (-not $selectedPlugin) { return }
        }
        else {
            Write-Host ''
            Write-Host "找到 $($pluginList.Count) 个中文语言包:"
            for ($i = 0; $i -lt $pluginList.Count; $i++) {
                Write-Host "  [$($i + 1)] $($pluginList[$i].Path)"
                Write-Host "      版本: $($pluginList[$i].Version)  兼容: $($pluginList[$i].SinceBuild) ~ $($pluginList[$i].UntilBuild)"
            }
            Write-Host '  [M] 手动输入 IDEA 安装目录或语言包路径'
            Write-Host '  [0] 退出'
            $pick = Read-Host '  选择语言包编号'
            if ($pick -eq '0') { return }
            if ($pick -eq 'M') {
                $selectedPlugin = Read-ChinesePlugin
                if (-not $selectedPlugin) { return }
            }
            else {
                if ($pick -notmatch '^\d+$') { throw '选择必须是数字。' }
                $pluginIndex = [int]$pick - 1
                if ($pluginIndex -lt 0 -or $pluginIndex -ge $pluginList.Count) { throw '选择超出范围。' }
                $selectedPlugin = $pluginList[$pluginIndex]
            }
        }
    }

    $pluginsDir = Resolve-PluginDir $selectedRebased
    $configPath = (Resolve-ConfigDir $selectedRebased).IdeGeneral
    $branch = Get-BuildBranch $selectedRebased.Build
    if (-not $branch) { throw "无法从 Rebased build 识别分支: $($selectedRebased.Build)" }

    Write-Host ''
    Write-Host ('=' * 55)
    Write-Host '  确认信息'
    Write-Host ('=' * 55)
    Write-Host ''
    Write-Host "  Rebased:       $($selectedRebased.Path)"
    Write-Host "  版本:          $($selectedRebased.Version)  build $($selectedRebased.Build)"
    Write-Host "  类型:          $(if ($selectedRebased.IsZip) { 'ZIP 便携版' } else { 'EXE 安装版' })"
    Write-Host "  语言包:        $($selectedPlugin.Path)"
    Write-Host "  语言包版本:    $($selectedPlugin.Version)"
    Write-Host "  插件安装到:    $pluginsDir"
    Write-Host "  配置写入:      $configPath"
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
        default { throw '无效选择。' }
    }

    Write-Host ''
    Write-Host '[1] 安全检查...'
    if (Test-IsRunning $selectedRebased) { throw 'Rebased 正在运行！请先退出。' }
    Write-Host '    通过'

    if ($doInstall) {
        Write-Host ''
        Write-Host '[2] 安装中文语言包...'
        $existing = Join-Path $pluginsDir 'localization-zh'
        $legacyAudit = Join-Path $pluginsDir 'localization-zh-from-idea'
        $externalAuditRoot = Join-Path (Split-Path $pluginsDir -Parent) 'localization-zh-audit'
        foreach ($stale in @($existing, $legacyAudit, (Join-Path $externalAuditRoot 'localization-zh-from-idea'))) {
            if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Recurse -Force }
        }
        if (Test-Path -LiteralPath $externalAuditRoot) { Remove-Item -LiteralPath $externalAuditRoot -Recurse -Force }

        $copy = Install-Plugin -SourceDir $selectedPlugin.Path -TargetDir $pluginsDir
        Write-Host ''
        Write-Host "  修补 until-build -> $branch.*"
        Patch-UntilBuild -JarPath $copy.FinalJar -NewUntil "$branch.*"
        Write-Host ''
        Write-Host '[3] 配置中文...'
        Set-Locale $configPath 'zh-CN'
        if ($selectedRebased.IsZip) {
            Enable-PortableMode (Join-Path $selectedRebased.Path 'bin\idea.properties')
        }
        Write-Host ''
        Write-Host '安装完成。启动 Rebased 后，在 File -> Settings -> Appearance -> Language 选择 Chinese (Simplified)。'
    }

    if ($doPack) {
        if ($selectedRebased.IsExe) { throw 'EXE 安装版不能直接打包为便携 ZIP，请选择 ZIP 便携版。' }
        Write-Host ''
        Write-Host ('=' * 55)
        Write-Host '  创建分发包...'
        Write-Host ('=' * 55)
        New-PortableZip -RebasedPath $selectedRebased.Path -Clean
        Write-Host ''
        Write-Host '解压 ZIP 后运行 bin\rebased64.exe 即可。'
    }

    Read-Host '按回车键退出'
}

Write-Host ('=' * 55)
Write-Host '  Rebased 中文语言包配置工具'
Write-Host ('=' * 55)
Write-Host ''
Write-Host '请选择操作:'
Write-Host ''
Write-Host '  [1] 迁移旧版中文配置到新版 Rebased'
Write-Host '  [2] 同步中文语言包'
Write-Host '  [0] 退出'
Write-Host ''

try {
    $mode = Read-Host '  输入数字'
    switch ($mode) {
        '1' { Invoke-MigrationMode }
        '2' { Invoke-SyncMode }
        '0' { Write-Host '已退出。' }
        default { Write-Host '无效选择。' }
    }
}
catch {
    Write-Host ''
    Write-Host "操作失败: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host '按回车键退出'
}
