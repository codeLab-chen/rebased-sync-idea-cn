# plugin.ps1 - 插件操作模块

function Patch-UntilBuild {
    param([string]$JarPath, [string]$NewUntil)
    if (-not (Test-Path -LiteralPath $JarPath)) { throw "JAR 不存在: $JarPath" }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmp = Join-Path $env:TEMP ('rebased-patch-' + [guid]::NewGuid().ToString('N'))

    try {
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $zip = [System.IO.Compression.ZipFile]::OpenRead($JarPath)
        try { [System.IO.Compression.ZipFileExtensions]::ExtractToDirectory($zip, $tmp) }
        finally { $zip.Dispose() }

        $pxml = Join-Path $tmp 'META-INF\plugin.xml'
        if (-not (Test-Path -LiteralPath $pxml)) { throw 'META-INF/plugin.xml 不存在' }

        $xml = [IO.File]::ReadAllText($pxml, [Text.Encoding]::UTF8)
        $oldUntil = if ($xml -match 'until-build="([^"]+)"') { $Matches[1] } else { '(无)' }
        if ($xml -notmatch 'until-build="[^"]*"') {
            throw 'plugin.xml 中不存在 until-build，未执行隐式修改。'
        }
        $xml = $xml -replace 'until-build="[^"]*"', "until-build=`"$NewUntil`""
        [IO.File]::WriteAllText($pxml, $xml, [Text.Encoding]::UTF8)
        Write-Host "    修补 until-build: '$oldUntil' -> '$NewUntil'"

        $tmpJar = Join-Path $tmp 'out.jar'
        $newZip = [System.IO.Compression.ZipFile]::Open($tmpJar, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            Get-ChildItem -LiteralPath $tmp -Recurse -File | Where-Object { $_.FullName -ne $tmpJar } | ForEach-Object {
                $rel = $_.FullName.Substring($tmp.Length + 1) -replace '\\', '/'
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($newZip, $_.FullName, $rel) | Out-Null
            }
        }
        finally { $newZip.Dispose() }

        Remove-Item -LiteralPath $JarPath -Force
        Move-Item -LiteralPath $tmpJar -Destination $JarPath -Force
        Write-Host '    完成'
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Test-NeedsPatch {
    param([string]$JarPath, [string]$RebasedBuild)

    $xml = Read-JarPluginXml $JarPath
    $until = if ($xml -match 'until-build="([^"]+)"') { $Matches[1] } else { return $true }

    if ($RebasedBuild -match '\.SNAPSHOT') { return $true }

    $branch = Get-BuildBranch $RebasedBuild
    if ($until -eq "$branch.*") { return $false }

    $r = ($RebasedBuild -replace '^[A-Z]+-', '') -split '\.'
    $u = ($until -replace '\.\*$', '.999999') -split '\.'
    $max = [Math]::Max($r.Count, $u.Count)
    while ($r.Count -lt $max) { $r += '0' }
    while ($u.Count -lt $max) { $u += '0' }
    try {
        return ([version]($r -join '.') -gt [version]($u -join '.'))
    }
    catch { return $true }
}

function Install-Plugin {
    param(
        [string]$SourceDir,
        [string]$TargetDir,
        [string]$FinalName = 'localization-zh'
    )

    if (-not (Test-Path -LiteralPath $SourceDir)) { throw "源插件不存在: $SourceDir" }
    $sourceJar = Join-Path $SourceDir 'lib\localization-zh.jar'
    if (-not (Test-Path -LiteralPath $sourceJar)) { throw "源插件缺少 localization-zh.jar: $SourceDir" }

    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    $finalPath = Join-Path $TargetDir $FinalName

    if (Test-Path -LiteralPath $finalPath) { Remove-Item -LiteralPath $finalPath -Recurse -Force }
    Copy-Item -LiteralPath $SourceDir -Destination $finalPath -Recurse
    Write-Host "  中文插件已复制到: $finalPath"

    return @{
        FinalPath = $finalPath
        FinalJar  = Join-Path $finalPath 'lib\localization-zh.jar'
    }
}
