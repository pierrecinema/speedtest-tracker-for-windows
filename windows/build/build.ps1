# Builds windows/build/out/stage: everything the installer ships.
param(
    [string]$OutDir = (Join-Path $PSScriptRoot 'out')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$winDir = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $winDir -Parent
$cache = Join-Path $OutDir 'cache'
$stage = Join-Path $OutDir 'stage'
$versions = Get-Content (Join-Path $winDir 'versions.json') -Raw | ConvertFrom-Json

function Get-Pinned([string]$Key, [string]$FileName) {
    $entry = $versions.$Key
    $path = Join-Path $cache $FileName
    if (-not (Test-Path $path)) {
        Invoke-WebRequest -Uri $entry.url -OutFile $path -UseBasicParsing
    }
    $actual = (Get-FileHash $path -Algorithm SHA256).Hash
    if ($actual -ne $entry.sha256.ToUpper()) {
        Remove-Item $path -Force
        throw "Checksum mismatch for $Key"
    }
    return $path
}

function Invoke-Native([string]$FilePath, [string[]]$Arguments) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

New-Item -ItemType Directory -Force $cache | Out-Null
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
$env:ST_ROOT = $stage

$phpDir = Join-Path $stage 'php'
Expand-Archive (Get-Pinned 'php' 'php.zip') $phpDir
Copy-Item (Join-Path $winDir 'runtime\php.ini') (Join-Path $phpDir 'php.ini')

$caddyDir = Join-Path $stage 'caddy'
Expand-Archive (Get-Pinned 'caddy' 'caddy.zip') $caddyDir

$winswDir = New-Item -ItemType Directory -Force (Join-Path $stage 'winsw')
Copy-Item (Get-Pinned 'winsw' 'WinSW-x64.exe') (Join-Path $winswDir 'SpeedtestTracker.exe')
Copy-Item (Join-Path $winDir 'runtime\SpeedtestTracker.xml') $winswDir

$runtimeDir = New-Item -ItemType Directory -Force (Join-Path $stage 'runtime')
Copy-Item (Join-Path $winDir 'runtime\*') $runtimeDir -Include '*.ps1', '*.tpl'
Copy-Item (Join-Path $winDir 'installer\provision.ps1') (New-Item -ItemType Directory -Force (Join-Path $stage 'installer'))
Copy-Item (Join-Path $winDir 'versions.json') $stage

Copy-Item (Get-Pinned 'vcredist' 'vc_redist.x64.exe') $stage
Copy-Item (Get-Pinned 'cacert' 'cacert.pem') $stage

$appDir = New-Item -ItemType Directory -Force (Join-Path $stage 'app')
$archive = Join-Path $cache 'app.tar'
Invoke-Native 'git' @('-C', $repoRoot, 'archive', '--format=tar', '-o', $archive, 'HEAD')
Invoke-Native 'tar' @('-xf', $archive, '-C', $appDir)
Remove-Item $archive -Force
foreach ($name in '.codex', '.devcontainer', '.github', 'docker', 'docs', 'tests', 'windows', 'compose.yaml', '.env.ci', '.env.example') {
    $target = Join-Path $appDir $name
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
}

$php = Join-Path $phpDir 'php.exe'
$composer = Get-Pinned 'composer' 'composer.phar'
Push-Location $appDir
try {
    Invoke-Native $php @('-c', (Join-Path $phpDir 'php.ini'), $composer, 'install', '--no-dev', '--optimize-autoloader', '--no-interaction', '--no-progress', '--ignore-platform-req=ext-pcntl', '--ignore-platform-req=ext-posix')
    Invoke-Native 'npm' @('ci', '--no-audit', '--no-fund')
    Invoke-Native 'npm' @('run', 'build')
    Remove-Item 'node_modules' -Recurse -Force
} finally {
    Pop-Location
}
