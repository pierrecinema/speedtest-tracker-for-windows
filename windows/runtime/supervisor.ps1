# Keeps the web server, PHP workers, queue and scheduler running. Started by WinSW.
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$DataDir
)

. (Join-Path $PSScriptRoot 'common.ps1')

function Get-ProcessDefinitions {
    param([string]$Root, [string]$DataDir)

    $php = "$Root\php\php.exe"
    $iniArg = "-c `"$Root\php\php.ini`""
    $artisan = "$iniArg `"$Root\app\artisan`""
    $app = "$Root\app"

    $defs = @([pscustomobject]@{
            Name             = 'caddy'
            FilePath         = "$Root\caddy\caddy.exe"
            Arguments        = "run --config `"$DataDir\Caddyfile`" --adapter caddyfile"
            WorkingDirectory = "$Root\caddy"
        })
    foreach ($i in 1..3) {
        $defs += [pscustomobject]@{
            Name             = "php-cgi-$i"
            FilePath         = "$Root\php\php-cgi.exe"
            Arguments        = "$iniArg -b 127.0.0.1:910$i"
            WorkingDirectory = $app
        }
    }
    $defs += [pscustomobject]@{
        Name             = 'queue'
        FilePath         = $php
        Arguments        = "$artisan queue:work --tries=3 --max-time=3600"
        WorkingDirectory = $app
    }
    $defs += [pscustomobject]@{
        Name             = 'scheduler'
        FilePath         = $php
        Arguments        = "$artisan schedule:work"
        WorkingDirectory = $app
    }
    return $defs
}

function Set-ChildEnvironment {
    param([string]$Root, [string]$DataDir)
    $env:ST_ROOT = $Root
    $env:PHP_FCGI_MAX_REQUESTS = '0'
    $env:XDG_DATA_HOME = "$DataDir\caddy"
    $env:XDG_CONFIG_HOME = "$DataDir\caddy"
    $env:PATH = "$DataDir\ookla;$Root\php;$env:PATH"
}

function Start-Child {
    param($Definition, [string]$LogDir)
    return Start-Process -FilePath $Definition.FilePath -ArgumentList $Definition.Arguments `
        -WorkingDirectory $Definition.WorkingDirectory -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $LogDir "$($Definition.Name).log") `
        -RedirectStandardError (Join-Path $LogDir "$($Definition.Name).err.log")
}

function Invoke-SupervisorTick {
    param([hashtable]$Running, [object[]]$Definitions, [string]$LogDir, [int]$RestartDelaySeconds = 5)

    foreach ($def in $Definitions) {
        $entry = $Running[$def.Name]
        if ($entry -and -not $entry.Process.HasExited) { continue }
        if ($entry) {
            if (-not $entry.ExitedAt) { $entry.ExitedAt = Get-Date }
            if (((Get-Date) - $entry.ExitedAt).TotalSeconds -lt $RestartDelaySeconds) { continue }
        }
        $Running[$def.Name] = @{ Process = Start-Child -Definition $def -LogDir $LogDir; ExitedAt = $null }
    }
}

function Stop-AllChildren {
    param([hashtable]$Running)
    foreach ($entry in $Running.Values) {
        if (-not $entry.Process.HasExited) {
            & taskkill.exe /T /F /PID $entry.Process.Id 2>&1 | Out-Null
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $Root = [IO.Path]::GetFullPath($Root)
    $logDir = Join-Path $DataDir 'logs'
    New-Item -ItemType Directory -Force $logDir | Out-Null

    Update-AppUrl -EnvPath (Join-Path $DataDir '.env')
    Set-ChildEnvironment -Root $Root -DataDir $DataDir

    $definitions = Get-ProcessDefinitions -Root $Root -DataDir $DataDir
    $running = @{}
    try {
        while ($true) {
            Invoke-SupervisorTick -Running $running -Definitions $definitions -LogDir $logDir
            Start-Sleep -Seconds 2
        }
    } finally {
        Stop-AllChildren -Running $running
    }
}
