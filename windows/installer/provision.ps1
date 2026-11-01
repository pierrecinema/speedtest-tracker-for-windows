# Runs elevated from the installer. Must stay compatible with Windows PowerShell 5.1.
param(
    [ValidateSet('Install', 'Uninstall', 'StopService', 'Load')][string]$Action = 'Load',
    [string]$Root,
    [string]$DataDir = (Join-Path $env:ProgramData 'SpeedtestTracker'),
    [int]$Port = 8765,
    [string]$Schedule = '30 * * * *',
    [switch]$RemoveData
)

. (Join-Path $PSScriptRoot '..\runtime\common.ps1')

$FirewallRule = 'Speedtest Tracker'

function New-AppKey {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return 'base64:' + [Convert]::ToBase64String($bytes)
}

function Write-EnvFile {
    param([string]$Path, [int]$Port, [string]$Schedule, [string]$AppUrl)

    if (Test-Path $Path) { return }

    $database = Join-Path (Split-Path $Path -Parent) 'database.sqlite'
    $lines = @(
        'APP_NAME="Speedtest Tracker"'
        'APP_ENV=production'
        "APP_KEY=$(New-AppKey)"
        'APP_DEBUG=false'
        "APP_URL=$AppUrl"
        'APP_LOCALE=de_DE'
        'APP_TIMEZONE=UTC'
        'DISPLAY_TIMEZONE=Europe/Zurich'
        "SPEEDTEST_SCHEDULE=`"$Schedule`""
        'DB_CONNECTION=sqlite'
        "DB_DATABASE='$database'"
        'QUEUE_CONNECTION=database'
        'CACHE_STORE=database'
        'SESSION_DRIVER=cookie'
        'LOG_LEVEL=warning'
        "ST_PORT=$Port"
    )
    [IO.File]::WriteAllLines($Path, [string[]]$lines)
}

function Test-PortFree {
    param([int]$Port)
    $listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Any, $Port)
    try {
        $listener.Start()
        return $true
    } catch [Net.Sockets.SocketException] {
        return $false
    } finally {
        $listener.Stop()
    }
}

function Install-OoklaCli {
    param([string]$Dest, [string]$Url, [string]$Sha256, [string]$Version)

    $marker = Join-Path $Dest 'version.txt'
    if ((Test-Path (Join-Path $Dest 'speedtest.exe')) -and (Test-Path $marker) -and ((Get-Content $marker -Raw).Trim() -eq $Version)) {
        return
    }

    $temp = Join-Path ([IO.Path]::GetTempPath()) "ookla-$([Guid]::NewGuid()).zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {
            (New-Object Net.WebClient).DownloadFile($Url, $temp)
        } catch {
            throw "Ookla download failed: $($_.Exception.Message)"
        }
        if ((Get-FileHash $temp -Algorithm SHA256).Hash -ne $Sha256.ToUpper()) {
            throw "Ookla download has the wrong checksum"
        }
        New-Item -ItemType Directory -Force $Dest | Out-Null
        Expand-Archive $temp $Dest -Force
        Set-Content $marker $Version
    } finally {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
    }
}

function Test-ReparsePoint {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    return [bool]((Get-Item $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Remove-DataLinks {
    param([string]$Root)
    $storage = Join-Path $Root 'app\storage'
    if (Test-ReparsePoint $storage) { [IO.Directory]::Delete($storage) }
    $envLink = Join-Path $Root 'app\.env'
    if (Test-Path $envLink) { Remove-Item $envLink -Force }
}

function Set-DataLinks {
    param([string]$Root, [string]$DataDir)

    $appStorage = Join-Path $Root 'app\storage'
    $dataStorage = Join-Path $DataDir 'storage'
    Remove-DataLinks -Root $Root
    if (Test-Path $appStorage) {
        if (-not (Test-Path $dataStorage)) {
            Move-Item $appStorage $dataStorage
        } else {
            Copy-Item (Join-Path $appStorage '*') $dataStorage -Recurse -Force -Exclude '*.log'
            Remove-Item $appStorage -Recurse -Force
        }
    }
    New-Item -ItemType Junction -Path $appStorage -Target $dataStorage | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $Root 'app\.env') -Target (Join-Path $DataDir '.env') | Out-Null
}

function Invoke-Checked {
    param([string]$FilePath, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $FilePath @Arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) {
        throw "$(Split-Path $FilePath -Leaf) $($Arguments -join ' ') failed with exit code ${code}: $output"
    }
    return $output
}

function Get-ServiceExe {
    param([string]$Root)
    return Join-Path $Root 'winsw\SpeedtestTracker.exe'
}

function Stop-TrackerService {
    param([string]$Root)
    $service = Get-Service SpeedtestTracker -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Stopped') {
        Stop-Service SpeedtestTracker -Force
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(45))
    }
}

function Start-TrackerService {
    param([string]$Root, [int]$Port)
    $exe = Get-ServiceExe -Root $Root
    if (Get-Service SpeedtestTracker -ErrorAction SilentlyContinue) {
        Invoke-Checked $exe @('refresh') | Out-Null
    } else {
        Invoke-Checked $exe @('install') | Out-Null
    }
    Start-Service SpeedtestTracker

    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest "http://127.0.0.1:$Port/api/healthcheck" -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -eq 200) { return }
        } catch {
        }
        Start-Sleep -Seconds 2
    }
    throw "The service started, but the web interface does not answer on port $Port"
}

function Set-FirewallRule {
    param([int]$Port)
    Remove-NetFirewallRule -DisplayName $FirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $FirewallRule -Direction Inbound -Protocol TCP -LocalPort $Port `
        -RemoteAddress LocalSubnet -Action Allow -Profile Any | Out-Null
}

function Protect-DataDir {
    param([string]$DataDir)
    Invoke-Checked 'icacls.exe' @($DataDir, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F') | Out-Null
}

function Invoke-Migrations {
    param([string]$Root)
    $env:ST_ROOT = $Root
    $php = Join-Path $Root 'php\php.exe'
    $ini = Join-Path $Root 'php\php.ini'
    $artisan = Join-Path $Root 'app\artisan'
    Push-Location (Join-Path $Root 'app')
    try {
        Invoke-Checked $php @('-c', $ini, $artisan, 'migrate', '--force') | Out-Null
        Invoke-Checked $php @('-c', $ini, $artisan, 'optimize:clear') | Out-Null
    } finally {
        Pop-Location
    }
}

function Invoke-Install {
    param([string]$Root, [string]$DataDir, [int]$Port, [string]$Schedule, $Versions)

    $envPath = Join-Path $DataDir '.env'
    $existing = Get-EnvValue -Path $envPath -Key 'ST_PORT'
    if ($existing) { $Port = [int]$existing }

    Stop-TrackerService -Root $Root
    Install-OoklaCli -Dest (Join-Path $DataDir 'ookla') -Url $Versions.ookla.url -Sha256 $Versions.ookla.sha256 -Version $Versions.ookla.version
    if (-not (Test-PortFree -Port $Port)) {
        throw "Port $Port is already in use"
    }

    New-Item -ItemType Directory -Force (Join-Path $DataDir 'logs') | Out-Null
    $ip = Get-PrimaryIPv4
    if (-not $ip) { $ip = 'localhost' }
    Write-EnvFile -Path $envPath -Port $Port -Schedule $Schedule -AppUrl "http://${ip}:$Port"
    Set-DataLinks -Root $Root -DataDir $DataDir

    $database = Join-Path $DataDir 'database.sqlite'
    if (-not (Test-Path $database)) { New-Item -ItemType File $database | Out-Null }
    Invoke-Migrations -Root $Root

    Write-Caddyfile -TemplatePath (Join-Path $Root 'runtime\Caddyfile.tpl') -Path (Join-Path $DataDir 'Caddyfile') -Port $Port -Root $Root -DataDir $DataDir
    Set-FirewallRule -Port $Port
    Protect-DataDir -DataDir $DataDir
    Start-TrackerService -Root $Root -Port $Port
}

function Invoke-Uninstall {
    param([string]$Root, [string]$DataDir, [switch]$RemoveData)

    Stop-TrackerService -Root $Root
    if (Get-Service SpeedtestTracker -ErrorAction SilentlyContinue) {
        Invoke-Checked (Get-ServiceExe -Root $Root) @('uninstall') | Out-Null
    }
    Remove-NetFirewallRule -DisplayName $FirewallRule -ErrorAction SilentlyContinue
    Remove-DataLinks -Root $Root
    if ($RemoveData -and (Test-Path $DataDir)) {
        Remove-Item $DataDir -Recurse -Force
    }
}

if ($Action -ne 'Load') {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $log = Join-Path ([IO.Path]::GetTempPath()) 'SpeedtestTracker-install.log'
    try {
        switch ($Action) {
            'StopService' { Stop-TrackerService -Root $Root }
            'Uninstall' { Invoke-Uninstall -Root $Root -DataDir $DataDir -RemoveData:$RemoveData }
            'Install' {
                $versions = Get-Content (Join-Path $Root 'versions.json') -Raw | ConvertFrom-Json
                Invoke-Install -Root $Root -DataDir $DataDir -Port $Port -Schedule $Schedule -Versions $versions
            }
        }
    } catch {
        Set-Content $log "$(Get-Date -Format s) $Action failed: $($_.Exception.Message)"
        Write-Error $_.Exception.Message -ErrorAction Continue
        exit 1
    }
    exit 0
}
