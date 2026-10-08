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

Write-Host '[1/5] 检查 PowerShell 语法'
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $discovery), [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-Equal $parseErrors.Count 0 'discovery.ps1 不应有 PowerShell 语法错误'

. $discovery
. $plugin
. $config
. $migration

$root = Join-Path ([IO.Path]::GetTempPath()) ('rebased-migration-test-' + [guid]::NewGuid().ToString('N'))
try {
    Write-Host '[2/5] 检查 Rebased 信息读取和自动发现'
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

    Write-Host '[3/5] 构造旧版中文插件和新版已有配置'
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

    Write-Host '[4/5] 执行迁移并验证结果'
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
    Write-Host '[5/5] 测试完成'
}
finally {
    if (Test-Path $root) { Remove-Item $root -Recurse -Force }
}

Write-Host '全部测试通过'
