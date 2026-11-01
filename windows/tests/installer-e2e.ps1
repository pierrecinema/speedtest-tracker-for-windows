# Real install, update and uninstall. Needs elevation and changes the machine, so it runs on CI only.
param([Parameter(Mandatory)][string]$Setup)

$ErrorActionPreference = 'Stop'
$dataDir = Join-Path $env:ProgramData 'SpeedtestTracker'
$root = Join-Path $env:ProgramFiles 'Speedtest Tracker'
$rule = 'Speedtest Tracker'

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAILED: $Message" }
    Write-Host "ok: $Message"
}

function Invoke-Setup([string]$Exe, [string[]]$Arguments) {
    $process = Start-Process $Exe -ArgumentList $Arguments -Wait -PassThru
    Assert-True ($process.ExitCode -eq 0) "$(Split-Path $Exe -Leaf) exit code"
}

function Get-Health {
    (Invoke-WebRequest 'http://127.0.0.1:8765/api/healthcheck' -UseBasicParsing -TimeoutSec 10).StatusCode
}

function Show-Log {
    Get-ChildItem $env:TEMP -Filter 'SpeedtestTracker-install.log' -Recurse -ErrorAction SilentlyContinue | Get-Content
    Get-ChildItem (Join-Path $dataDir 'logs') -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "--- $($_.Name)"
        Get-Content $_.FullName -Tail 20
    }
}

try {
    Invoke-Setup $Setup @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')

    Assert-True ((Get-Service SpeedtestTracker).Status -eq 'Running') 'service runs'
    Assert-True ((Get-Service SpeedtestTracker).StartType -like 'Automatic*') 'service starts automatically'
    Assert-True ((Get-Health) -eq 200) 'web interface answers'
    Assert-True (Test-Path "$dataDir\ookla\speedtest.exe") 'Ookla CLI installed'

    $firewall = Get-NetFirewallRule -DisplayName $rule
    $filter = $firewall | Get-NetFirewallAddressFilter
    Assert-True ($filter.RemoteAddress -eq 'LocalSubnet') 'firewall is limited to the local subnet'
    Assert-True (($firewall | Get-NetFirewallPortFilter).LocalPort -eq '8765') 'firewall opens only the chosen port'

    $url = (Get-Content "$dataDir\.env" | Where-Object { $_ -match '^APP_URL=' }) -replace '^APP_URL=', ''
    Assert-True ($url -match '^http://\d+\.\d+\.\d+\.\d+:8765$') "APP_URL uses the detected address ($url)"

    $key = Get-Content "$dataDir\.env" | Where-Object { $_ -match '^APP_KEY=' }
    $marker = Join-Path $dataDir 'storage\update-marker.txt'
    Set-Content $marker 'keep'

    Restart-Service SpeedtestTracker
    Start-Sleep -Seconds 20
    Assert-True ((Get-Health) -eq 200) 'web interface answers after a restart'

    (Get-Content "$dataDir\.env") -replace '^ST_PORT=.*', 'ST_PORT=8766' | Set-Content "$dataDir\.env"
    Restart-Service SpeedtestTracker
    Start-Sleep -Seconds 20
    $moved = (Invoke-WebRequest 'http://127.0.0.1:8766/api/healthcheck' -UseBasicParsing -TimeoutSec 10).StatusCode
    Assert-True ($moved -eq 200) 'a port changed in .env takes effect after a restart'
    Assert-True ((Get-NetFirewallRule -DisplayName $rule | Get-NetFirewallPortFilter).LocalPort -eq '8766') 'the firewall follows the changed port'
    (Get-Content "$dataDir\.env") -replace '^ST_PORT=.*', 'ST_PORT=8765' | Set-Content "$dataDir\.env"
    Restart-Service SpeedtestTracker
    Start-Sleep -Seconds 20

    Invoke-Setup $Setup @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    Assert-True ((Get-Health) -eq 200) 'web interface answers after an update'
    Assert-True ((Get-Content "$dataDir\.env" | Where-Object { $_ -match '^APP_KEY=' }) -eq $key) 'update keeps APP_KEY'
    Assert-True (Test-Path $marker) 'update keeps stored data'
    Assert-True (Test-Path "$dataDir\database.sqlite") 'update keeps the database'

    Stop-Service SpeedtestTracker
    Start-Sleep -Seconds 3
    $left = Get-Process php, php-cgi, caddy -ErrorAction SilentlyContinue
    Assert-True (-not $left) 'stopping the service leaves no processes behind'
    Start-Service SpeedtestTracker

    Invoke-Setup (Join-Path $root 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    Start-Sleep -Seconds 5
    Assert-True (-not (Get-Service SpeedtestTracker -ErrorAction SilentlyContinue)) 'uninstall removes the service'
    Assert-True (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) 'uninstall removes the firewall rule'
    Assert-True (Test-Path "$dataDir\database.sqlite") 'uninstall keeps data by default'
} catch {
    Show-Log
    throw
}
