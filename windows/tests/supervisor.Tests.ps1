BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime\supervisor.ps1') -Root 'C:\x' -DataDir 'C:\y'
    $script:SpaceRoot = 'C:\Program Files\Speedtest Tracker'
    $script:SpaceData = 'C:\Program Data\SpeedtestTracker'
    $script:Defs = Get-ProcessDefinitions -Root $SpaceRoot -DataDir $SpaceData
}

Describe 'Get-ProcessDefinitions' {
    It 'defines exactly the six processes' {
        $Defs.Name | Should -Be @('caddy', 'php-cgi-1', 'php-cgi-2', 'php-cgi-3', 'queue', 'scheduler')
    }

    It 'binds <name> to port <port>' -ForEach @(
        @{ name = 'php-cgi-1'; port = 9101 }
        @{ name = 'php-cgi-2'; port = 9102 }
        @{ name = 'php-cgi-3'; port = 9103 }
    ) {
        ($Defs | Where-Object Name -eq $name).Arguments | Should -Match "-b 127\.0\.0\.1:$port"
    }

    It 'quotes paths that contain spaces' {
        ($Defs | Where-Object Name -eq 'queue').Arguments | Should -Match ([regex]::Escape("`"$SpaceRoot\app\artisan`""))
        ($Defs | Where-Object Name -eq 'caddy').Arguments | Should -Match ([regex]::Escape("`"$SpaceData\Caddyfile`""))
    }

    It 'runs the queue worker with retries and a recycle limit' {
        ($Defs | Where-Object Name -eq 'queue').Arguments | Should -Match 'queue:work --tries=3 --max-time=3600'
    }

    It 'runs the scheduler' {
        ($Defs | Where-Object Name -eq 'scheduler').Arguments | Should -Match 'schedule:work'
    }

    It 'runs artisan from the application directory' {
        ($Defs | Where-Object Name -eq 'scheduler').WorkingDirectory | Should -Be "$SpaceRoot\app"
    }
}

Describe 'Set-ChildEnvironment' {
    It 'puts the Ookla CLI first on PATH so speedtest resolves without code changes' {
        $old = $env:PATH
        try {
            Set-ChildEnvironment -Root $SpaceRoot -DataDir $SpaceData
            $env:PATH.Split(';')[0] | Should -Be "$SpaceData\ookla"
            $env:ST_ROOT | Should -Be $SpaceRoot
            $env:PHP_FCGI_MAX_REQUESTS | Should -Be '0'
        } finally {
            $env:PATH = $old
        }
    }
}

Describe 'Invoke-SupervisorTick' {
    It 'starts a missing process and restarts it after it exits' {
        $logDir = Join-Path $TestDrive 'logs'
        New-Item -ItemType Directory $logDir | Out-Null
        $def = [pscustomobject]@{ Name = 'dummy'; FilePath = 'cmd.exe'; Arguments = '/c exit 0'; WorkingDirectory = $TestDrive }
        $running = @{}

        Invoke-SupervisorTick -Running $running -Definitions @($def) -LogDir $logDir -RestartDelaySeconds 0
        $first = $running['dummy'].Process.Id
        $running['dummy'].Process.WaitForExit()
        Invoke-SupervisorTick -Running $running -Definitions @($def) -LogDir $logDir -RestartDelaySeconds 0

        $running['dummy'].Process.Id | Should -Not -Be $first
        Join-Path $logDir 'dummy.log' | Should -Exist
    }

    It 'waits for the restart delay before starting again' {
        $logDir = Join-Path $TestDrive 'logs2'
        New-Item -ItemType Directory $logDir | Out-Null
        $def = [pscustomobject]@{ Name = 'dummy'; FilePath = 'cmd.exe'; Arguments = '/c exit 0'; WorkingDirectory = $TestDrive }
        $running = @{}

        Invoke-SupervisorTick -Running $running -Definitions @($def) -LogDir $logDir -RestartDelaySeconds 60
        $first = $running['dummy'].Process.Id
        $running['dummy'].Process.WaitForExit()
        Invoke-SupervisorTick -Running $running -Definitions @($def) -LogDir $logDir -RestartDelaySeconds 60

        $running['dummy'].Process.Id | Should -Be $first
    }
}

Describe 'Stop-AllChildren' {
    It 'leaves no child running' {
        $logDir = Join-Path $TestDrive 'logs3'
        New-Item -ItemType Directory $logDir | Out-Null
        $def = [pscustomobject]@{ Name = 'sleeper'; FilePath = 'cmd.exe'; Arguments = '/c ping -n 30 127.0.0.1'; WorkingDirectory = $TestDrive }
        $running = @{}
        Invoke-SupervisorTick -Running $running -Definitions @($def) -LogDir $logDir -RestartDelaySeconds 0
        $proc = $running['sleeper'].Process

        Stop-AllChildren -Running $running

        $proc.WaitForExit(5000) | Should -BeTrue
    }
}

Describe 'Caddyfile template and service config' {
    BeforeAll {
        $script:RuntimeDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime'
    }

    It 'renders with a quoted web root and all three PHP backends' {
        $out = Join-Path $TestDrive 'Caddyfile'
        Write-Caddyfile -TemplatePath (Join-Path $RuntimeDir 'Caddyfile.tpl') -Path $out -Port 8765 -Root $SpaceRoot -DataDir $SpaceData
        $text = Get-Content $out -Raw
        $text | Should -Match ':8765 \{'
        $text | Should -Match 'root \* "C:/Program Files/Speedtest Tracker/app/public"'
        $text | Should -Match 'php_fastcgi 127\.0\.0\.1:9101 127\.0\.0\.1:9102 127\.0\.0\.1:9103'
        $text | Should -Not -Match '\{\{'
    }

    It 'starts automatically and restarts on failure' {
        [xml]$xml = Get-Content (Join-Path $RuntimeDir 'SpeedtestTracker.xml') -Raw
        $xml.service.id | Should -Be 'SpeedtestTracker'
        $xml.service.startmode | Should -Be 'Automatic'
        $xml.service.delayedAutoStart | Should -Be 'true'
        $xml.service.onfailure.action | Should -Be 'restart'
        $xml.service.arguments | Should -Match 'supervisor\.ps1'
    }
}
