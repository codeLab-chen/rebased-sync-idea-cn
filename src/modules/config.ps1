# config.ps1 - 配置模块
# 处理 ide.general.xml（语言设置）和 idea.properties（便携模式）

function Get-Locale {
    param([string]$XmlPath)
    if (-not (Test-Path $XmlPath)) { return $null }
    $xml = Get-Content $XmlPath -Raw -Encoding UTF8
    if ($xml -match '<option name="selectedLocale" value="([^"]+)"') { return $Matches[1] }
    return $null
}

function Set-Locale {
    param([string]$XmlPath, [string]$Locale = 'zh-CN')
    
    $dir = Split-Path $XmlPath -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    
    $component = @"
  <component name="LocalizationStateService">
    <option name="selectedLocale" value="$Locale" />
  </component>
"@

    if (Test-Path $XmlPath) {
        $xml = Get-Content $XmlPath -Raw -Encoding UTF8
        
        if ($xml -match '<component name="LocalizationStateService">') {
            $esc = $component.TrimEnd() -replace '\$', '$$$$'
            $xml = $xml -replace '(?s)<component name="LocalizationStateService">.*?</component>', $esc
        }
        elseif ($xml -match '</application>') {
            $xml = $xml -replace '</application>', "$component`r`n</application>"
        }
        else {
            $xml = "<application>`r`n$component`r`n$xml`r`n</application>"
        }
    }
    else {
        $xml = "<application>`r`n$component`r`n</application>"
    }
    
    [IO.File]::WriteAllText($XmlPath, $xml, [Text.Encoding]::UTF8)
    Write-Host "  语言设置为: $Locale"
}

function Enable-PortableMode {
    param([string]$PropsPath)
    if (-not (Test-Path $PropsPath)) {
        Write-Warning "idea.properties 不存在: $PropsPath"
        return
    }
    
    $lines = Get-Content $PropsPath -Encoding UTF8
    $changed = $false
    $newLines = @()
    
    $map = @{
        'idea.config.path'  = 'idea.config.path=${idea.home.path}/config'
        'idea.system.path'  = 'idea.system.path=${idea.home.path}/system'
        'idea.plugins.path' = 'idea.plugins.path=${idea.config.path}/plugins'
        'idea.log.path'     = 'idea.log.path=${idea.system.path}/log'
    }
    
    foreach ($line in $lines) {
        $matched = $false
        foreach ($kv in $map.GetEnumerator()) {
            if ($line -match "^\s*#\s*$($kv.Key)\s*=") {
                $newLines += $kv.Value
                $changed = $true
                $matched = $true
                break
            }
        }
        if (-not $matched) { $newLines += $line }
    }
    
    if ($changed) {
        [IO.File]::WriteAllText($PropsPath, ($newLines -join "`r`n"), [Text.Encoding]::UTF8)
        Write-Host "  已启用便携模式 (config/system 存储在 IDE 目录内)"
    }
}
