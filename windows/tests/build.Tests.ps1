BeforeAll {
    $script:WinDir = Split-Path $PSScriptRoot -Parent
    $script:Stage = if ($env:ST_STAGE) { $env:ST_STAGE } else { Join-Path $WinDir 'build\out\stage' }
    $script:Php = Join-Path $Stage 'php\php.exe'
    $script:IniPath = Join-Path $Stage 'php\php.ini'
    $env:ST_ROOT = $Stage
}

Describe 'versions.json' {
    BeforeAll {
        $script:Versions = Get-Content (Join-Path $WinDir 'versions.json') -Raw | ConvertFrom-Json
    }

    It 'pins <_> with an https url and a sha256' -ForEach @('php', 'caddy', 'winsw', 'vcredist', 'cacert', 'composer', 'ookla') {
        $entry = $Versions.$_
        $entry.version | Should -Not -BeNullOrEmpty
        $entry.url | Should -Match '^https://'
        $entry.sha256 | Should -Match '^[0-9a-fA-F]{64}$'
    }

    It 'pins Ookla CLI 1.2.0 from the official host' {
        $Versions.ookla.version | Should -Be '1.2.0'
        $Versions.ookla.url | Should -Be 'https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip'
    }
}

Describe 'stage' {
    It 'contains the runtime tools' -ForEach @('php\php-cgi.exe', 'caddy\caddy.exe', 'winsw\SpeedtestTracker.exe', 'vc_redist.x64.exe', 'cacert.pem') {
        Join-Path $Stage $_ | Should -Exist
    }

    It 'loads PHP extension <_>' -ForEach @('bcmath', 'curl', 'gd', 'intl', 'mbstring', 'openssl', 'pdo_mysql', 'pdo_pgsql', 'pdo_sqlite', 'sqlite3', 'zip') {
        (& $Php -c $IniPath -m) -join "`n" | Should -Match "(?im)^$_$"
    }

    It 'verifies TLS with the bundled CA file' {
        (& $Php -c $IniPath -r 'echo ini_get("curl.cainfo");') | Should -Be (Join-Path $Stage 'cacert.pem')
    }

    It 'boots Laravel 13' {
        Push-Location (Join-Path $Stage 'app')
        try {
            (& $Php -c $IniPath artisan --version) -join ' ' | Should -Match 'Laravel Framework 13\.'
        } finally {
            Pop-Location
        }
    }

    It 'contains built frontend assets' {
        Join-Path $Stage 'app\public\build\manifest.json' | Should -Exist
    }

    It 'contains no <_>' -ForEach @('.env', 'tests', 'docker', '.git', 'node_modules', 'vendor\pestphp') {
        Join-Path $Stage "app\$_" | Should -Not -Exist
    }
}
