# pack.ps1 - 打包模块

function New-PortableZip {
    param([string]$RebasedPath, [string]$OutputZip, [switch]$Clean)
    
    if (-not (Test-Path $RebasedPath)) { throw "路径不存在: $RebasedPath" }
    
    $checks = @{
        'product-info.json'          = Test-Path "$RebasedPath\product-info.json"
        'rebased64.exe'              = (Test-Path "$RebasedPath\bin\rebased64.exe") -or (Test-Path "$RebasedPath\rebased64.exe")
        'config/plugins/localization-zh' = Test-Path "$RebasedPath\config\plugins\localization-zh\lib\localization-zh.jar"
        'config/options/ide.general.xml' = Test-Path "$RebasedPath\config\options\ide.general.xml"
    }
    
    $allOk = ($checks.Values -notcontains $false)
    Write-Host "  组件检查:"
    foreach ($kv in $checks.GetEnumerator()) {
        $status = if ($kv.Value) { 'OK' } else { 'MISS' }
        Write-Host "    [$status] $($kv.Key)"
    }
    
    if (-not $allOk) {
        Write-Warning "部分组件缺失，打包后可能无法直接使用中文"
    }
    
    if (-not $OutputZip) {
        $name = Split-Path $RebasedPath -Leaf
        $ver = ''
        try {
            $pi = Get-Content "$RebasedPath\product-info.json" -Raw | ConvertFrom-Json
            $ver = "-v$($pi.version)"
        } catch {}
        $OutputZip = "$(Split-Path $RebasedPath -Parent)\$name$ver-cn.zip"
    }
    
    Write-Host "  输出: $OutputZip"
    
    if ($Clean) {
        @('system', 'config\eval') | ForEach-Object {
            $p = "$RebasedPath\$_"
            if (Test-Path $p) {
                Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "  清理: $_"
            }
        }
    }
    
    if (Test-Path $OutputZip) { Remove-Item $OutputZip -Force }
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($OutputZip, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $baseName = Split-Path $RebasedPath -Leaf
        $exclude = @('*.log', '*.lock', 'config\eval\*', 'config\options\recentProjects.xml',
                     'config\options\window.state.xml', 'config\options\trusted-paths.xml')
        
        Get-ChildItem $RebasedPath -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($RebasedPath.Length + 1)
            foreach ($pat in $exclude) {
                if ($rel -like $pat) { return }
            }
            $entry = "$baseName/$($rel -replace '\\', '/')"
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entry)
        }
    }
    finally { $zip.Dispose() }
    
    $size = (Get-Item $OutputZip).Length
    Write-Host "  打包完成: $OutputZip ($('{0:N0}' -f $size) bytes)"
    return $OutputZip
}
