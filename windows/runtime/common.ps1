# Shared by supervisor.ps1 and provision.ps1. Must stay compatible with Windows PowerShell 5.1.

function Get-EnvValue {
    param([string]$Path, [string]$Key)
    $line = Get-Content $Path -ErrorAction SilentlyContinue | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
    if ($line) { return ($line -replace "^$Key=", '').Trim('"', "'") }
    return $null
}

function Set-EnvValue {
    param([string]$Path, [string]$Key, [string]$Value)
    $lines = @(Get-Content $Path -ErrorAction SilentlyContinue)
    $entry = "$Key=$Value"
    if ($lines -match "^$Key=") {
        $lines = $lines | ForEach-Object { if ($_ -match "^$Key=") { $entry } else { $_ } }
    } else {
        $lines += $entry
    }
    [IO.File]::WriteAllLines($Path, [string[]]$lines)
}

function Get-PrimaryIPv4 {
    try {
        $route = Find-NetRoute -RemoteIPAddress '1.1.1.1' -ErrorAction Stop |
            Where-Object { $_.IPAddress } | Select-Object -First 1
        if ($route -and $route.IPAddress -notmatch '^169\.254\.') { return $route.IPAddress }
    } catch {
    }
    return $null
}

function Update-AppUrl {
    param([string]$EnvPath, [string]$IPv4 = (Get-PrimaryIPv4))
    if (-not $IPv4) { return }
    $current = Get-EnvValue -Path $EnvPath -Key 'APP_URL'
    if ($current -notmatch '^http://(\d+\.\d+\.\d+\.\d+|localhost):\d+$') { return }
    $port = Get-EnvValue -Path $EnvPath -Key 'ST_PORT'
    $url = "http://${IPv4}:$port"
    if ($current -ne $url) {
        Set-EnvValue -Path $EnvPath -Key 'APP_URL' -Value $url
    }
}

function Set-FirewallRule {
    param([int]$Port)
    Remove-NetFirewallRule -DisplayName 'Speedtest Tracker' -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'Speedtest Tracker' -Direction Inbound -Protocol TCP -LocalPort $Port `
        -RemoteAddress LocalSubnet -Action Allow -Profile Any | Out-Null
}

function Sync-PortConfig {
    param([string]$EnvPath, [string]$Root, [string]$DataDir)
    $port = [int](Get-EnvValue -Path $EnvPath -Key 'ST_PORT')
    $caddyfile = Join-Path $DataDir 'Caddyfile'
    if ((Get-Content $caddyfile -Raw -ErrorAction SilentlyContinue) -match "(?m)^:$port \{") { return }
    Write-Caddyfile -TemplatePath (Join-Path $Root 'runtime\Caddyfile.tpl') -Path $caddyfile -Port $port -Root $Root -DataDir $DataDir
    Set-FirewallRule -Port $port
}

function Write-Caddyfile {
    param([string]$TemplatePath, [string]$Path, [int]$Port, [string]$Root, [string]$DataDir)
    $text = (Get-Content $TemplatePath -Raw).
        Replace('{{PORT}}', "$Port").
        Replace('{{ROOT}}', $Root.Replace('\', '/')).
        Replace('{{DATA}}', $DataDir.Replace('\', '/'))
    [IO.File]::WriteAllText($Path, $text)
}
