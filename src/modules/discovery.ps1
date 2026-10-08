# discovery.ps1 - 路径发现模块
# EXE: AppData    ZIP: 自身目录 (config/plugins + config/options)

$DefaultSearchRoots = @(
    'C:\迅雷下载',
    'C:\home\app\devApp',
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Desktop",
    'D:\',
    'E:\',
    "$env:ProgramFiles\JetBrains",
    "${env:ProgramFiles(x86)}\JetBrains",
    "$env:LOCALAPPDATA\Programs",
    "$env:LOCALAPPDATA\JetBrains\Toolbox\apps",
    "$env:APPDATA\JetBrains"
)

function Normalize-UserPath {
    param([string]$Path)

    if (-not $Path) { return '' }
    $value = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        $value = $value.Substring(1, $value.Length - 2).Trim()
    }
    if ($value.Length -gt 3) { $value = $value.TrimEnd('\', '/') }
    return $value
}

function Read-JarPluginXml {
    param([string]$JarPath)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($JarPath)
    try {
        $entry = $zip.GetEntry('META-INF/plugin.xml')
        if (-not $entry) { throw "plugin.xml 不存在: $JarPath" }
        $sr = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    }
    finally { $zip.Dispose() }
}

function Get-XmlText {
    param([string]$Xml, [string]$Tag)
    if ($Xml -match "<$Tag>(.*?)</$Tag>") { return $Matches[1].Trim() }
    return ''
}

function Get-BuildBranch {
    param([string]$Version)
    if ($Version -match '^[A-Z]+-(\d+)\.') { return $Matches[1] }
    if ($Version -match '^(\d+)\.') { return $Matches[1] }
    return ''
}

function Test-IsExeInstall {
    param([string]$Dir)
    return Test-Path (Join-Path $Dir 'Uninstall.exe')
}

function Get-RebasedInfo {
    param([string]$Path)

    $normalized = Normalize-UserPath $Path
    if (-not $normalized) { throw 'Rebased 路径不能为空。' }
    $productJson = Join-Path $normalized 'product-info.json'
    if (-not (Test-Path -LiteralPath $productJson)) {
        throw "不是有效的 Rebased 目录（缺少 product-info.json）: $normalized"
    }

    $info = Get-Content -LiteralPath $productJson -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($info.name -ne 'Rebased' -and $info.envVarBaseName -ne 'REBASED') {
        throw "目录不是 Rebased: $normalized"
    }

    $exe = @(
        (Join-Path $normalized 'bin\rebased64.exe'),
        (Join-Path $normalized 'rebased64.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $isExe = Test-IsExeInstall $normalized

    return [pscustomobject]@{
        Path        = $normalized
        Version     = [string]$info.version
        Build       = [string]$info.buildNumber
        DataDir     = [string]$info.dataDirectoryName
        Vendor      = [string]$info.productVendor
        Exe         = $exe
        IsExe       = $isExe
        IsZip       = -not $isExe
        ProductJson = $productJson
        Modified    = (Get-Item -LiteralPath $productJson).LastWriteTime
    }
}

function Find-Rebased {
    param([string[]]$SearchRoots)
    if (-not $SearchRoots) { $SearchRoots = $DefaultSearchRoots }
    $SearchRoots = @($SearchRoots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)

    $results = foreach ($root in $SearchRoots) {
        Get-ChildItem $root -Recurse -File -Filter 'product-info.json' -ErrorAction SilentlyContinue | ForEach-Object {
            try { Get-RebasedInfo $_.Directory.FullName } catch { return }
        }
    }
    return @($results | Group-Object -Property Path | ForEach-Object { $_.Group | Sort-Object -Property Modified -Descending | Select-Object -First 1 } | Sort-Object -Property Modified -Descending)
}

function Find-ChinesePlugin {
    param(
        [string[]]$SearchRoots,
        [string]$ExcludeUnder
    )
    if (-not $SearchRoots) { $SearchRoots = $DefaultSearchRoots }
    $SearchRoots = @($SearchRoots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)

    $results = foreach ($root in $SearchRoots) {
        Get-ChildItem $root -Recurse -File -Filter 'localization-zh.jar' -ErrorAction SilentlyContinue | ForEach-Object {
            if ($ExcludeUnder -and $_.FullName.StartsWith($ExcludeUnder, [StringComparison]::OrdinalIgnoreCase)) { return }
            if ($_.FullName -match '[\\/]_localization-zh-backups[\\/]') { return }
            if ($_.Extension -eq '.bak') { return }

            try {
                $xml = Read-JarPluginXml $_.FullName
                if ($xml -notmatch '<id>\s*com\.intellij\.zh\s*</id>') { return }

                $pluginDir = $_.Directory.Parent.FullName
                [pscustomobject]@{
                    Path       = $pluginDir
                    Jar        = $_.FullName
                    Version    = Get-XmlText $xml 'version'
                    SinceBuild = if ($xml -match 'since-build="([^"]+)"') { $Matches[1] } else { '' }
                    UntilBuild = if ($xml -match 'until-build="([^"]+)"') { $Matches[1] } else { '' }
                    Modified   = $_.LastWriteTime
                }
            }
            catch {}
        }
    }
    return @($results | Group-Object -Property Path | ForEach-Object { $_.Group | Sort-Object -Property Modified -Descending | Select-Object -First 1 } | Sort-Object -Property Modified -Descending)
}

function Resolve-PluginDir {
    param($Rebased)

    if ($Rebased.IsZip) {
        return (Join-Path $Rebased.Path 'config\plugins')
    }
    return (Join-Path (Join-Path $env:APPDATA $Rebased.Vendor) "$($Rebased.DataDir)\plugins")
}

function Resolve-ConfigDir {
    param($Rebased)

    if ($Rebased.IsZip) {
        return [pscustomobject]@{
            IdeGeneral = Join-Path $Rebased.Path 'config\options\ide.general.xml'
        }
    }

    $base = Join-Path (Join-Path $env:APPDATA $Rebased.Vendor) $Rebased.DataDir
    return [pscustomobject]@{
        IdeGeneral = Join-Path $base 'options\ide.general.xml'
    }
}

function Test-IsRunning {
    param($Rebased)
    if (-not $Rebased.Exe) { return $false }
    $running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -eq $Rebased.Exe -or $_.Name -in @('rebased64.exe', 'rebased.exe')
    }
    return ($running.Count -gt 0)
}


