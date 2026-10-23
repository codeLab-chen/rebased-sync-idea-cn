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
    $SearchRoots = @($SearchRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)

    $results = foreach ($root in $SearchRoots) {
        Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'product-info.json' -ErrorAction SilentlyContinue | ForEach-Object {
            try { Get-RebasedInfo $_.Directory.FullName } catch { return }
        }
    }
    return @($results | Group-Object -Property Path | ForEach-Object { $_.Group | Sort-Object -Property Modified -Descending | Select-Object -First 1 } | Sort-Object -Property Modified -Descending)
}

function Find-RebasedAtPath {
    param([string]$Path)

    $normalized = Normalize-UserPath $Path
    if (-not $normalized) { throw 'Rebased 路径不能为空。' }
    if (-not (Test-Path -LiteralPath $normalized -PathType Container)) { throw "目录不存在: $normalized" }
    $directory = Get-Item -LiteralPath $normalized
    try { return (Get-RebasedInfo $directory.FullName) } catch {}

    $results = @(foreach ($child in (Get-ChildItem -LiteralPath $directory.FullName -Directory)) {
        if ($child.Name -notlike '*rebased*' -and -not (Test-Path -LiteralPath (Join-Path $child.FullName 'product-info.json') -PathType Leaf)) { continue }
        try { Get-RebasedInfo $child.FullName } catch { continue }
    })
    if ($results.Count -eq 0) {
        throw "未找到 Rebased: $normalized。已检查当前目录及下一层子文件夹（如 Rebased、rebased.win），安装目录需包含有效的 Rebased product-info.json。"
    }
    return $results
}

function Find-ChinesePlugin {
    param(
        [string[]]$SearchRoots,
        [string]$ExcludeUnder
    )
    if (-not $SearchRoots) { $SearchRoots = @('C:\home\codeApp') + $DefaultSearchRoots }
    $SearchRoots = @($SearchRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)

    $results = foreach ($root in $SearchRoots) {
        Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'localization-zh.jar' -ErrorAction SilentlyContinue | ForEach-Object {
            if ($ExcludeUnder -and $_.FullName.StartsWith($ExcludeUnder, [StringComparison]::OrdinalIgnoreCase)) { return }
            if ($_.FullName -match '[\\/]_localization-zh-backups[\\/]') { return }
            if ($_.Extension -eq '.bak') { return }

            try {
                Get-ChinesePluginInfo $_.FullName
            }
            catch {}
        }
    }
    return @($results | Group-Object -Property Path | ForEach-Object { $_.Group | Sort-Object -Property Modified -Descending | Select-Object -First 1 } | Sort-Object -Property Modified -Descending)
}

function Get-ChinesePluginInfo {
    param([string]$Path)

    $normalized = Normalize-UserPath $Path
    if (-not $normalized) { throw '语言包路径不能为空，请输入 IDEA 安装目录或 localization-zh 目录。' }
    if (-not (Test-Path -LiteralPath $normalized)) { throw "路径不存在: $normalized" }

    $item = Get-Item -LiteralPath $normalized
    $candidates = if ($item.PSIsContainer) {
        @(
            (Join-Path $item.FullName 'plugins\localization-zh\lib\localization-zh.jar'),
            (Join-Path $item.FullName 'localization-zh\lib\localization-zh.jar'),
            (Join-Path $item.FullName 'lib\localization-zh.jar'),
            (Join-Path $item.FullName 'localization-zh.jar')
        )
    }
    else { @($item.FullName) }

    $jar = $null
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $file = Get-Item -LiteralPath $candidate
        if ($file.Name -eq 'localization-zh.jar' -and $file.Directory.Name -eq 'lib') {
            $jar = $file
            break
        }
    }
    if (-not $jar) {
        throw "未找到中文语言包: $normalized。请选择 IDEA 安装目录（内含 plugins\localization-zh\lib\localization-zh.jar），或 localization-zh 目录（内含 lib\localization-zh.jar）。"
    }

    $xml = Read-JarPluginXml $jar.FullName
    if ($xml -notmatch '<id>\s*com\.intellij\.zh\s*</id>') {
        throw "该文件不是简体中文语言包（com.intellij.zh）: $($jar.FullName)"
    }
    return [pscustomobject]@{
        Path       = $jar.Directory.Parent.FullName
        Jar        = $jar.FullName
        Version    = Get-XmlText $xml 'version'
        SinceBuild = if ($xml -match 'since-build="([^"]+)"') { $Matches[1] } else { '' }
        UntilBuild = if ($xml -match 'until-build="([^"]+)"') { $Matches[1] } else { '' }
        Modified   = $jar.LastWriteTime
    }
}

function Find-ChinesePluginAtPath {
    param([string]$Path)

    $normalized = Normalize-UserPath $Path
    if (-not $normalized) { throw '语言包路径不能为空，请输入 IDEA 安装目录或其上一级目录。' }
    if (-not (Test-Path -LiteralPath $normalized)) { throw "路径不存在: $normalized" }
    try { return (Get-ChinesePluginInfo $normalized) }
    catch {
        if (-not (Test-Path -LiteralPath $normalized -PathType Container)) { throw }
        $directError = $_.Exception.Message
    }

    $results = @(foreach ($child in (Get-ChildItem -LiteralPath $normalized -Directory)) {
        $isIdea = $child.Name -like '*IntelliJ IDEA*'
        if (-not $isIdea) {
            $productJson = Join-Path $child.FullName 'product-info.json'
            if (Test-Path -LiteralPath $productJson -PathType Leaf) {
                try {
                    $info = Get-Content -LiteralPath $productJson -Raw -Encoding UTF8 | ConvertFrom-Json
                    $isIdea = $info.name -like '*IntelliJ IDEA*'
                }
                catch { continue }
            }
        }
        if (-not $isIdea) { continue }
        try { Get-ChinesePluginInfo $child.FullName } catch { continue }
    })
    if ($results.Count -eq 0) {
        throw "$directError 已检查下一层名称包含 IntelliJ IDEA 或产品信息确认为 IDEA 的子文件夹，未找到有效中文语言包。"
    }
    return $results
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


