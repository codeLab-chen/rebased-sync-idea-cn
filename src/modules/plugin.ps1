# plugin.ps1 - 插件操作模块

function Patch-UntilBuild {
    param([string]$JarPath, [string]$NewUntil)
    if (-not (Test-Path $JarPath)) { throw "JAR 不存在: $JarPath" }
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $tmp = "$env:TEMP\rebased-patch-$ts"
    
    $bakDir = Split-Path $JarPath -Parent
    $bakName = [IO.Path]::GetFileNameWithoutExtension($JarPath) + ".bak-$ts.jar"
    $bakPath = "$bakDir\$bakName"
    Copy-Item $JarPath $bakPath -Force
    Write-Host "    备份: $bakName"
    
    try {
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $zip = [System.IO.Compression.ZipFile]::OpenRead($JarPath)
        try { [System.IO.Compression.ZipFileExtensions]::ExtractToDirectory($zip, $tmp) }
        finally { $zip.Dispose() }
        
        $pxml = "$tmp\META-INF\plugin.xml"
        if (-not (Test-Path $pxml)) { throw "META-INF/plugin.xml 不存在" }
        
        $xml = [IO.File]::ReadAllText($pxml, [Text.Encoding]::UTF8)
        $oldUntil = if ($xml -match 'until-build="([^"]+)"') { $Matches[1] } else { '(无)' }
        $xml = $xml -replace 'until-build="[^"]*"', "until-build=`"$NewUntil`""
        [IO.File]::WriteAllText($pxml, $xml, [Text.Encoding]::UTF8)
        Write-Host "    修补 until-build: '$oldUntil' -> '$NewUntil'"
        
        $tmpJar = "$tmp\out.jar"
        $newZip = [System.IO.Compression.ZipFile]::Open($tmpJar, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            Get-ChildItem $tmp -Recurse -File | Where-Object { $_.FullName -ne $tmpJar } | ForEach-Object {
                $rel = $_.FullName.Substring($tmp.Length + 1) -replace '\\', '/'
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($newZip, $_.FullName, $rel)
            }
        }
        finally { $newZip.Dispose() }
        
        Remove-Item $JarPath -Force
        Move-Item $tmpJar $JarPath -Force
        Write-Host "    完成"
    }
    finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Test-NeedsPatch {
    param([string]$JarPath, [string]$RebasedBuild)
    
    $xml = Read-JarPluginXml $JarPath
    $until = if ($xml -match 'until-build="([^"]+)"') { $Matches[1] } else { return $true }
    
    # SNAPSHOT = 开发版本，兼容范围不确定，永远修补
    if ($RebasedBuild -match '\.SNAPSHOT') { return $true }
    
    # 已经是通配符就不需要
    $branch = Get-BuildBranch $RebasedBuild
    if ($until -eq "$branch.*") { return $false }
    
    # 标准化并补零对齐段数，防止 262.10968 vs 262.10968.63 误判
    $r = ($RebasedBuild -replace '^[A-Z]+-', '') -split '\.'
    $u = ($until -replace '\.\*$', '.999999') -split '\.'
    $max = [Math]::Max($r.Count, $u.Count)
    while ($r.Count -lt $max) { $r += '0' }
    while ($u.Count -lt $max) { $u += '0' }
    $vr = [version]($r -join '.')
    $vu = [version]($u -join '.')
    
    try { return ($vr -gt $vu) } catch { return $true }
}

function Install-Plugin {
    param(
        [string]$SourceDir,
        [string]$TargetDir,
        [string]$FinalName = 'localization-zh',
        [string]$AuditSuffix = '-from-idea'
    )
    
    if (-not (Test-Path $SourceDir)) { throw "源插件不存在: $SourceDir" }
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    
    $auditName = $FinalName + $AuditSuffix
    $auditPath = "$TargetDir\$auditName"
    $finalPath = "$TargetDir\$FinalName"
    
    Write-Host "  === 三步复制 ==="
    
    if (Test-Path $auditPath) { Remove-Item $auditPath -Recurse -Force }
    Copy-Item $SourceDir $auditPath -Recurse
    Write-Host "  第1步: IDEA 插件 -> $auditName (审计副本，保留原始 JAR)"
    
    if (Test-Path $finalPath) { Remove-Item $finalPath -Recurse -Force }
    Copy-Item $auditPath $finalPath -Recurse
    Write-Host "  第2步: $auditName -> $FinalName (工作副本)"
    
    return @{
        AuditPath = $auditPath
        AuditJar  = "$auditPath\lib\localization-zh.jar"
        FinalPath = $finalPath
        FinalJar  = "$finalPath\lib\localization-zh.jar"
    }
}

function Backup-Existing {
    param([string]$PluginPath, [string]$BackupRoot)
    if (-not (Test-Path $PluginPath)) { return $null }
    
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $name = Split-Path $PluginPath -Leaf
    $dest = "$BackupRoot\$name-$ts"
    Move-Item $PluginPath $dest
    Write-Host "  已备份: $dest"
    return $dest
}
