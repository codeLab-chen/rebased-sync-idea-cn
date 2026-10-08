# migration.ps1 - 旧版 Rebased 中文配置迁移模块

function Resolve-ExistingChinesePlugin {
    param($Rebased)

    $pluginsDir = Resolve-PluginDir $Rebased
    $externalAuditPath = Join-Path (Join-Path (Split-Path $pluginsDir -Parent) 'localization-zh-audit') 'localization-zh-from-idea'
    $legacyAuditPath = Join-Path $pluginsDir 'localization-zh-from-idea'
    $workPath = Join-Path $pluginsDir 'localization-zh'

    foreach ($candidate in @($externalAuditPath, $legacyAuditPath, $workPath)) {
        $jar = Join-Path $candidate 'lib\localization-zh.jar'
        if (-not (Test-Path -LiteralPath $jar)) { continue }
        $xml = Read-JarPluginXml $jar
        if ($xml -notmatch '<id>\s*com\.intellij\.zh\s*</id>') {
            throw "插件不是中文语言包: $candidate"
        }
        return [pscustomobject]@{ Path = $candidate }
    }

    throw "旧版本中没有找到中文插件: $pluginsDir"
}

function Migrate-RebasedChinese {
    param(
        [Parameter(Mandatory = $true)]$SourceRebased,
        [Parameter(Mandatory = $true)]$TargetRebased
    )

    $sourcePlugin = Resolve-ExistingChinesePlugin $SourceRebased
    $sourcePluginsDir = Split-Path $sourcePlugin.Path -Parent
    $targetPluginsDir = Resolve-PluginDir $TargetRebased

    $sourceFull = [IO.Path]::GetFullPath($sourcePluginsDir).TrimEnd('\', '/')
    $targetFull = [IO.Path]::GetFullPath($targetPluginsDir).TrimEnd('\', '/')
    if ($sourceFull.Equals($targetFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw '旧版和新版共用同一个插件目录，不需要迁移；请确认选择的是不同的数据目录。'
    }

    $branch = Get-BuildBranch $TargetRebased.Build
    if (-not $branch) { throw "无法从新版 build 识别分支: $($TargetRebased.Build)" }

    $targetPlugin = Join-Path $targetPluginsDir 'localization-zh'
    $legacyAudit = Join-Path $targetPluginsDir 'localization-zh-from-idea'
    $externalAuditRoot = Join-Path (Split-Path $targetPluginsDir -Parent) 'localization-zh-audit'
    $externalAudit = Join-Path $externalAuditRoot 'localization-zh-from-idea'

    # 用户明确不需要备份：清理旧工作插件、旧审计副本和旧审计目录。
    foreach ($stale in @($targetPlugin, $legacyAudit, $externalAudit)) {
        if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Recurse -Force }
    }
    if (Test-Path -LiteralPath $externalAuditRoot) {
        Remove-Item -LiteralPath $externalAuditRoot -Recurse -Force
    }

    $copy = Install-Plugin -SourceDir $sourcePlugin.Path -TargetDir $targetPluginsDir
    Patch-UntilBuild -JarPath $copy.FinalJar -NewUntil "$branch.*"

    $configPath = (Resolve-ConfigDir $TargetRebased).IdeGeneral
    Set-Locale $configPath 'zh-CN'
    if ($TargetRebased.IsZip) {
        Enable-PortableMode (Join-Path $TargetRebased.Path 'bin\idea.properties')
    }

    return [pscustomobject]@{
        SourcePlugin = $sourcePlugin.Path
        TargetPlugin = $copy.FinalPath
        ConfigPath   = $configPath
        BuildBranch  = $branch
    }
}
