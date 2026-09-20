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
)}\JetBrains",
    "$env:LOCALAPPDATA\Programs",
    "$env:LOCALAPPDATA\JetBrains\Toolbox\apps",
    "$env:APPDATA\JetBrains"
)}\JetBrains",
    "$env:LOCALAPPDATA\Programs",
    "$env:LOCALAPPDATA\JetBrains\Toolbox\apps",
    "$env:APPDATA\JetBrains"
)

function Read-JarPluginXml {
    param([string]$JarPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($JarPath)
    try {
        $entry = $zip.GetEntry('META-INF/plugin.xml')
        if (-not $entry) { throw "plugin.xml 不存在: $JarPath" }
        $sr = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $zip.Dispose() }
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
    return Test-Path "$Dir\Uninstall.exe"
}

function Find-Rebased {
    param([string[]]$SearchRoots)
    if (-not $SearchRoots) { $SearchRoots = $DefaultSearchRoots }
    $SearchRoots = @($SearchRoots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)

    $results = foreach ($root in $SearchRoots) {
        Get-ChildItem $root -Recurse -File -Filter 'product-info.json' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $info = Get-Content $_.FullName -Raw | ConvertFrom-Json
                if ($info.name -ne 'Rebased' -and $info.envVarBaseName -ne 'REBASED') { return }
                
                $dir = $_.Directory.FullName
                $exe = @("$dir\bin\rebased64.exe", "$dir\rebased64.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
                $isExe = Test-IsExeInstall $dir
                
                [pscustomobject]@{
                    Path        = $dir
                    Version     = [string]$info.version
                    Build       = [string]$info.buildNumber
                    DataDir     = [string]$info.dataDirectoryName
                    Vendor      = [string]$info.productVendor
                    Exe         = $exe
                    IsExe       = $isExe
                    IsZip       = -not $isExe
                    ProductJson = $_.FullName
                    Modified    = $_.LastWriteTime
                }
            } catch {}
        }
    }
    return @($results | Sort-Object Modified -Descending)
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
            } catch {}
        }
    }
    return @($results | Sort-Object Modified -Descending)
}

function Resolve-PluginDir {
    param($Rebased)
    
    if ($Rebased.IsZip) {
        # ZIP: idea.plugins.path = ${idea.config.path}/plugins = config/plugins/
        return "$($Rebased.Path)\config\plugins"
    }
    else {
        # EXE: AppData
        return "$env:APPDATA\$($Rebased.Vendor)\$($Rebased.DataDir)\plugins"
    }
}

function Resolve-ConfigDir {
    param($Rebased)
    
    if ($Rebased.IsZip) {
        # ZIP: idea.config.path = config/
        return [pscustomobject]@{
            IdeGeneral = "$($Rebased.Path)\config\options\ide.general.xml"
        }
    }
    else {
        # EXE: AppData
        $base = "$env:APPDATA\$($Rebased.Vendor)\$($Rebased.DataDir)"
        return [pscustomobject]@{
            IdeGeneral = "$base\options\ide.general.xml"
        }
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


