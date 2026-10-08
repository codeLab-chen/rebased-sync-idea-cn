# config.ps1 - 配置模块
# 处理 ide.general.xml（语言设置）和 idea.properties（便携模式）

function Get-Locale {
    param([string]$XmlPath)
    if (-not (Test-Path -LiteralPath $XmlPath)) { return $null }
    $xml = Get-Content -LiteralPath $XmlPath -Raw -Encoding UTF8
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

    if (Test-Path -LiteralPath $XmlPath) {
        $xml = Get-Content -LiteralPath $XmlPath -Raw -Encoding UTF8

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

    [IO.File]::WriteAllText($XmlPath, $xml, [Text.UTF8Encoding]::new($true))
    Write-Host "  语言设置为: $Locale"
}

function Enable-PortableMode {
    param([string]$PropsPath)

    $dir = Split-Path $PropsPath -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $map = [ordered]@{
        'idea.config.path'  = 'idea.config.path=${idea.home.path}/config'
        'idea.system.path'  = 'idea.system.path=${idea.home.path}/system'
        'idea.plugins.path' = 'idea.plugins.path=${idea.config.path}/plugins'
        'idea.log.path'     = 'idea.log.path=${idea.system.path}/log'
    }

    if (Test-Path -LiteralPath $PropsPath) {
        $lines = @(Get-Content -LiteralPath $PropsPath -Encoding UTF8)
    }
    else {
        $lines = @()
    }

    $found = @{}
    $newLines = foreach ($line in $lines) {
        $matched = $false
        foreach ($key in $map.Keys) {
            if ($line -match "^\s*#?\s*$([regex]::Escape($key))\s*=") {
                $found[$key] = $true
                $matched = $true
                $map[$key]
                break
            }
        }
        if (-not $matched) { $line }
    }

    foreach ($key in $map.Keys) {
        if (-not $found.ContainsKey($key)) { $newLines += $map[$key] }
    }

    [IO.File]::WriteAllText($PropsPath, ($newLines -join "`r`n") + "`r`n", [Text.UTF8Encoding]::new($true))
    Write-Host "  已启用便携模式: $PropsPath"
}
