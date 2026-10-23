$ErrorActionPreference = 'Stop'

$repo = Split-Path $PSScriptRoot -Parent
$discovery = Join-Path $repo 'src\modules\discovery.ps1'
$plugin = Join-Path $repo 'src\modules\plugin.ps1'
$config = Join-Path $repo 'src\modules\config.ps1'
$migration = Join-Path $repo 'src\modules\migration.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "断言失败: $Message" }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "断言失败: $Message；实际='$Actual'，期望='$Expected'"
    }
}

Write-Host '[1/7] 检查 PowerShell 语法'
$tokens = $null
$parseErrors = $null
foreach ($scriptFile in (Get-ChildItem -LiteralPath (Join-Path $repo 'src') -Recurse -Filter '*.ps1')) {
    [System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-Equal $parseErrors.Count 0 "$($scriptFile.Name) 不应有 PowerShell 语法错误"
}
$entryAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'src\Update-RebasedChinese.ps1'), [ref]$tokens, [ref]$parseErrors)
foreach ($definition in $entryAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}

. $discovery
. $plugin
. $config
. $migration

$root = Join-Path ([IO.Path]::GetTempPath()) ('rebased-migration-test-' + [guid]::NewGuid().ToString('N'))
try {
    Write-Host '[2/7] 检查 Rebased 信息读取和自动发现'
    $old = Join-Path $root 'old'
    $new = Join-Path $root 'new'
    New-Item -ItemType Directory -Force -Path $old, $new | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $new 'bin') | Out-Null
    Set-Content -LiteralPath (Join-Path $new 'bin\idea.properties') -Value '# idea.config.path=old' -Encoding UTF8

    $oldInfo = @{
        name = 'Rebased';
        version = '1.1.16';
        buildNumber = '262.10315.SNAPSHOT';
        dataDirectoryName = 'IdeaIC1.1';
        productVendor = 'detachhead';
    } | ConvertTo-Json
    $newInfo = @{
        name = 'Rebased';
        version = '1.1.17';
        buildNumber = '262.10968.SNAPSHOT';
        dataDirectoryName = 'IdeaIC1.1-new';
        productVendor = 'detachhead';
    } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $old 'product-info.json') -Value $oldInfo -Encoding utf8
    Set-Content -LiteralPath (Join-Path $new 'product-info.json') -Value $newInfo -Encoding utf8

    $oldRebased = Get-RebasedInfo $old
    $newRebased = Get-RebasedInfo $new
    Assert-Equal $oldRebased.Build '262.10315.SNAPSHOT' '旧版本 build 应被读取'
    Assert-Equal $newRebased.Build '262.10968.SNAPSHOT' '新版本 build 应被读取'
    $found = @(Find-Rebased -SearchRoots @($root))
    Assert-Equal $found.Count 2 '自动搜索应找到旧、新两个 Rebased'

    Write-Host '[3/7] 构造旧版中文插件和新版已有配置'
    $sourcePlugin = Join-Path (Resolve-PluginDir $oldRebased) 'localization-zh-from-idea'
    $sourceJarDir = Join-Path $sourcePlugin 'lib'
    New-Item -ItemType Directory -Force -Path $sourceJarDir | Out-Null

    $newConfigPath = Join-Path $new 'config\options\ide.general.xml'
    New-Item -ItemType Directory -Force -Path (Split-Path $newConfigPath -Parent) | Out-Null
    @"
<application>
  <component name="OtherState">
    <option name="keep" value="yes" />
  </component>
  <component name="LocalizationStateService">
    <option name="selectedLocale" value="en-US" />
  </component>
</application>
"@ | Set-Content -LiteralPath $newConfigPath -Encoding utf8

    $jarWork = Join-Path $root 'jar-work'
    New-Item -ItemType Directory -Force -Path (Join-Path $jarWork 'META-INF') | Out-Null
    @"
<idea-plugin>
  <id>com.intellij.zh</id>
  <name>Chinese Language Pack</name>
  <version>262.10315.63</version>
  <idea-version since-build="262.10315.63" until-build="262.10315.63" />
</idea-plugin>
"@ | Set-Content -LiteralPath (Join-Path $jarWork 'META-INF\plugin.xml') -Encoding utf8

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $jarPath = Join-Path $sourceJarDir 'localization-zh.jar'
    $zip = [System.IO.Compression.ZipFile]::Open($jarPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $jarWork 'META-INF\plugin.xml'), 'META-INF/plugin.xml') | Out-Null
    }
    finally { $zip.Dispose() }

    Write-Host '[4/7] 检查 IDEA 各层路径解析和无效语言包'
    $ideaRoot = Join-Path $root 'IDEA 安装目录 [2026.2.3]'
    $ideaPlugin = Join-Path $ideaRoot 'plugins\localization-zh'
    $ideaLib = Join-Path $ideaPlugin 'lib'
    New-Item -ItemType Directory -Force -Path $ideaLib | Out-Null
    $ideaJar = Join-Path $ideaLib 'localization-zh.jar'
    Copy-Item -LiteralPath $jarPath -Destination $ideaJar
    foreach ($inputPath in @($ideaRoot, (Join-Path $ideaRoot 'plugins'), $ideaPlugin, $ideaLib, $ideaJar, ('"' + $ideaRoot + '\"'))) {
        $resolved = Get-ChinesePluginInfo $inputPath
        Assert-Equal $resolved.Path $ideaPlugin '各层输入均应解析为插件目录'
        Assert-Equal $resolved.Jar $ideaJar '各层输入均应定位同一 JAR'
        Assert-Equal $resolved.Version '262.10315.63' '应读取语言包版本'
    }
    $discoveredPlugins = @(Find-ChinesePlugin -SearchRoots @($ideaRoot))
    Assert-Equal $discoveredPlugins.Count 1 '自动搜索应找到 IDEA 中文语言包'
    Assert-Equal $discoveredPlugins[0].Path $ideaPlugin '自动搜索应返回插件目录'
    Assert-Equal @(Find-ChinesePlugin -SearchRoots @($ideaRoot) -ExcludeUnder $ideaRoot).Count 0 '自动搜索应排除指定目录'

    $badPlugin = Join-Path $root 'wrong-plugin'
    New-Item -ItemType Directory -Force -Path (Join-Path $badPlugin 'lib') | Out-Null
    $badJar = Join-Path $badPlugin 'lib\localization-zh.jar'
    Set-Content -LiteralPath (Join-Path $jarWork 'META-INF\plugin.xml') -Value '<idea-plugin><id>com.intellij.ja</id></idea-plugin>' -Encoding UTF8
    $zip = [System.IO.Compression.ZipFile]::Open($badJar, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $jarWork 'META-INF\plugin.xml'), 'META-INF/plugin.xml') | Out-Null
    }
    finally { $zip.Dispose() }
    foreach ($inputPath in @('', (Join-Path $root 'missing'), $new, $badPlugin)) {
        $rejected = $false
        try { Get-ChinesePluginInfo $inputPath | Out-Null } catch { $rejected = $true }
        Assert-True $rejected '空路径、不存在的路径、缺包目录和其他语言插件应被拒绝'
    }

    Write-Host '[5/7] 检查失败后重试、退出和自动搜索转手动'
    function Invoke-TestSyncConsole {
        param([string[]]$Answers, [object[]]$Plugins = @(), [object[]]$RebasedItems = @(), [switch]$MigrationMode)
        $inputQueue = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($answer in $Answers) { $inputQueue.Enqueue($answer) }
        function Read-Host {
            param([string]$Prompt)
            if ($inputQueue.Count -eq 0) { throw "测试输入已耗尽: $Prompt" }
            return $inputQueue.Dequeue()
        }
        function Find-ChinesePlugin { param($ExcludeUnder) return $Plugins }
        function Find-Rebased { return $RebasedItems }
        $output = if ($MigrationMode) { Invoke-MigrationMode 6>&1 | Out-String } else { Invoke-SyncMode 6>&1 | Out-String }
        Assert-Equal $inputQueue.Count 0 '交互流程应消费预期输入'
        return $output
    }
    $retryOutput = Invoke-TestSyncConsole -Answers @('2', $new, '2', $new, 'invalid', '1', $ideaRoot, '4')
    Assert-True ($retryOutput -match '\[1\] 重新输入路径' -and $retryOutput -match '\[0\] 退出') '找包失败应提供重试和退出选项'
    Assert-True ($retryOutput -match '无效选择，请输入 1 或 0' -and $retryOutput -match '未做修改') '重试后应能用安装根目录完成只读流程'
    $exitOutput = Invoke-TestSyncConsole -Answers @('2', $new, '2', '', '0')
    Assert-True ($exitOutput -match '查找失败' -and $exitOutput -notmatch '确认信息') '失败后选择退出应正常返回'
    $fallbackOutput = Invoke-TestSyncConsole -Answers @('2', $new, '1', $ideaRoot, '4')
    Assert-True ($fallbackOutput -match '自动搜索未找到' -and $fallbackOutput -match '未做修改') '自动搜索找不到时应允许手动指定安装目录'
    $manualOutput = Invoke-TestSyncConsole -Answers @('2', $new, '1', 'M', $ideaRoot, '4') -Plugins $discoveredPlugins
    Assert-True ($manualOutput -match '\[M\]' -and $manualOutput -match '未做修改') '搜索结果列表应支持转为手动输入'
    $listOutput = Invoke-TestSyncConsole -Answers @('2', $new, '1', '1', '4') -Plugins $discoveredPlugins
    Assert-True ($listOutput -match '未做修改') '原有语言包编号选择应继续有效'

    $rebasedParent = Join-Path $root '应用 [Rebased]'
    $rebasedA = Join-Path $rebasedParent 'Rebased'
    $rebasedB = Join-Path $rebasedParent 'rebased.win(1)'
    $rebasedRenamed = Join-Path $rebasedParent '自定义安装目录'
    $rebasedFake = Join-Path $rebasedParent 'rebased.win-invalid'
    New-Item -ItemType Directory -Force -Path $rebasedA, $rebasedB, $rebasedRenamed, $rebasedFake | Out-Null
    Set-Content -LiteralPath (Join-Path $rebasedA 'product-info.json') -Value $oldInfo -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $rebasedB 'product-info.json') -Value $newInfo -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $rebasedRenamed 'product-info.json') -Value $newInfo -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $rebasedFake 'product-info.json') -Value '{"name":"IntelliJ IDEA"}' -Encoding UTF8
    $rebasedMatches = @(Find-RebasedAtPath ('"' + $rebasedParent + '"'))
    Assert-Equal $rebasedMatches.Count 3 '应找到所有有效的 Rebased 子目录，包括产品信息确认的改名目录'
    Assert-Equal @(Find-Rebased -SearchRoots @($rebasedParent)).Count 3 '自动搜索也应支持含方括号的目录'
    Assert-True ($rebasedMatches.Path -contains $rebasedA -and $rebasedMatches.Path -contains $rebasedB -and $rebasedMatches.Path -notcontains $rebasedFake) '名称匹配后必须验证产品，不能接受假 Rebased'
    Assert-Equal @(Find-RebasedAtPath $rebasedA).Count 1 '精确安装目录应直接解析，不重复搜索其子目录'

    $ideaParent = Join-Path $root 'IDE 工具 [多版本]'
    $ideaA = Join-Path $ideaParent 'IntelliJ IDEA 2026.2.3'
    $ideaB = Join-Path $ideaParent 'IntelliJ IDEA 2026.2.3 (1)'
    $ideaRenamed = Join-Path $ideaParent '自定义 IDEA 安装目录'
    $ideaFake = Join-Path $ideaParent 'IntelliJ IDEA invalid'
    foreach ($ideaDir in @($ideaA, $ideaB, $ideaRenamed)) {
        $libDir = Join-Path $ideaDir 'plugins\localization-zh\lib'
        New-Item -ItemType Directory -Force -Path $libDir | Out-Null
        Copy-Item -LiteralPath $ideaJar -Destination (Join-Path $libDir 'localization-zh.jar')
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $ideaFake 'plugins\localization-zh\lib') | Out-Null
    Copy-Item -LiteralPath $badJar -Destination (Join-Path $ideaFake 'plugins\localization-zh\lib\localization-zh.jar')
    Set-Content -LiteralPath (Join-Path $ideaRenamed 'product-info.json') -Value '{"name":"IntelliJ IDEA Ultimate"}' -Encoding UTF8
    $ideaMatches = @(Find-ChinesePluginAtPath $ideaParent)
    Assert-Equal $ideaMatches.Count 3 '应找到多个部分重名的 IDEA 及产品信息确认的改名目录，过滤无效语言包'

    function Invoke-TestPathConsole {
        param([string]$Kind, [string[]]$Answers)
        $inputQueue = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($answer in $Answers) { $inputQueue.Enqueue($answer) }
        function Read-Host {
            param([string]$Prompt)
            if ($inputQueue.Count -eq 0) { throw "测试输入已耗尽: $Prompt" }
            return $inputQueue.Dequeue()
        }
        $console = New-Object System.Text.StringBuilder
        $selected = $null
        Read-InstallationPath -Kind $Kind 6>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.InformationRecord]) { [void]$console.AppendLine($_.ToString()) }
            else { $selected = $_ }
        }
        Assert-Equal $inputQueue.Count 0 '路径选择应消费预期输入'
        return [pscustomobject]@{ Selected = $selected; Output = $console.ToString() }
    }
    $rebasedPick = [array]::IndexOf($rebasedMatches.Path, $rebasedB) + 1
    $rebasedSelection = Invoke-TestPathConsole -Kind Rebased -Answers @($rebasedParent, 'invalid', '99999999999999999999999', '99', [string]$rebasedPick)
    Assert-Equal $rebasedSelection.Selected.Path $rebasedB '多个 Rebased 必须使用用户指定的编号，非法输入应允许重选'
    Assert-True ($rebasedSelection.Output.Contains($rebasedA) -and $rebasedSelection.Output.Contains($rebasedB) -and $rebasedSelection.Output.Contains('262.10968.SNAPSHOT')) 'Rebased 列表应显示完整路径和 build 以区分多个版本'
    $ideaPick = [array]::IndexOf($ideaMatches.Path, (Join-Path $ideaB 'plugins\localization-zh')) + 1
    $ideaSelection = Invoke-TestPathConsole -Kind ChinesePlugin -Answers @($ideaParent, [string]$ideaPick)
    Assert-Equal $ideaSelection.Selected.Path (Join-Path $ideaB 'plugins\localization-zh') '多个 IDEA 即使版本相同也应按编号准确选择'
    Assert-True ($ideaSelection.Output.Contains($ideaA) -and $ideaSelection.Output.Contains($ideaB) -and $ideaSelection.Output.Contains('262.10315.63')) '语言包列表应显示完整路径、版本和兼容范围'
    foreach ($kind in @('Rebased', 'ChinesePlugin')) {
        $parentPath = if ($kind -eq 'Rebased') { $rebasedParent } else { $ideaParent }
        $directPath = if ($kind -eq 'Rebased') { $rebasedA } else { $ideaA }
        $resetSelection = Invoke-TestPathConsole -Kind $kind -Answers @($parentPath, 'M', $directPath)
        Assert-True ($null -ne $resetSelection.Selected) '多个结果列表应允许重新输入更精确的路径'
        $cancelSelection = Invoke-TestPathConsole -Kind $kind -Answers @($parentPath, '0')
        Assert-True ($null -eq $cancelSelection.Selected) '多个结果列表应允许退出，不自动选取任何一个'
    }
    $rebasedRetry = Invoke-TestSyncConsole -Answers @('2', $ideaRoot, '1', $rebasedA, '2', $ideaRoot, '4')
    Assert-True ($rebasedRetry -match '查找失败' -and $rebasedRetry -match '未做修改') 'Rebased 查找失败应能重新输入后继续流程'
    $rebasedExit = Invoke-TestSyncConsole -Answers @('2', '', '0')
    Assert-True ($rebasedExit -match '查找失败' -and $rebasedExit -notmatch '确认信息') 'Rebased 查找失败后退出应正常返回'
    $rebasedFallback = Invoke-TestSyncConsole -Answers @('1', $rebasedA, $ideaRoot, '4')
    Assert-True ($rebasedFallback -match '自动搜索未找到 Rebased' -and $rebasedFallback -match '未做修改') 'Rebased 自动搜索为空时应转手动输入'
    $rebasedManual = Invoke-TestSyncConsole -Answers @('1', 'M', $rebasedA, $ideaRoot, '4') -RebasedItems @($newRebased)
    Assert-True ($rebasedManual -match '未做修改') 'Rebased 自动搜索结果也应支持手动输入路径'
    $migrationRetry = Invoke-TestSyncConsole -MigrationMode -Answers @('M', '', '1', $rebasedA, '0')
    Assert-True ($migrationRetry -match '查找失败' -and $migrationRetry -match '\[1\] 重新输入路径' -and $migrationRetry -notmatch '确认迁移信息') '迁移模式找不到 Rebased 时也应允许手动重试并正常退出'

    Write-Host '[6/7] 执行迁移并验证结果'
    Migrate-RebasedChinese -SourceRebased $oldRebased -TargetRebased $newRebased | Out-Null
    $targetJar = Join-Path (Resolve-PluginDir $newRebased) 'localization-zh\lib\localization-zh.jar'
    $legacyAuditJar = Join-Path (Resolve-PluginDir $newRebased) 'localization-zh-from-idea\lib\localization-zh.jar'
    $auditJar = Join-Path $new 'config\localization-zh-audit\localization-zh-from-idea\lib\localization-zh.jar'
    $backupRoot = Join-Path $new 'config\_localization-zh-backups'
    Assert-True (Test-Path $targetJar) '迁移后新版应存在工作插件'
    Assert-True (-not (Test-Path $auditJar)) '迁移后不应生成审计副本'
    Assert-True (-not (Test-Path $backupRoot)) '迁移后不应生成备份目录'
    Assert-True (-not (Test-Path $legacyAuditJar)) '审计副本不能留在活动 plugins 目录'
    $targetXml = Read-JarPluginXml $targetJar
    Assert-True ($targetXml -match 'until-build="262\.\*"') '工作插件应按新版分支修补 until-build'

    $configText = Get-Content $newConfigPath -Raw -Encoding utf8
    Assert-True ($configText -match 'selectedLocale" value="zh-CN"') '迁移后应写入 zh-CN 配置'
    Assert-True ($configText -match 'component name="OtherState"') '迁移不应覆盖新版原有配置'

    $activeJars = @(Get-ChildItem -LiteralPath (Resolve-PluginDir $newRebased) -Recurse -Filter '*.jar')
    Assert-Equal $activeJars.Count 1 '活动插件目录只能有一个 JAR，不能含备份'
    $props = Get-Content -LiteralPath (Join-Path $new 'bin\idea.properties') -Raw
    Assert-True ($props -match '(?m)^idea\.config\.path=\$\{idea\.home\.path\}/config') 'ZIP 迁移必须启用相对便携路径'
    Write-Host '[7/7] 测试完成'
}
finally {
    $resolvedRoot = [IO.Path]::GetFullPath($root)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\rebased-migration-test-'
    if (-not $resolvedRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "测试清理路径超出临时目录: $resolvedRoot" }
    if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
}

Write-Host '全部测试通过'
