BeforeAll {
    $script:WinDir = Split-Path $PSScriptRoot -Parent
    . (Join-Path $WinDir 'installer\provision.ps1') -Action Load
}

Describe 'New-AppKey' {
    It 'creates a Laravel base64 key of 32 bytes' {
        $key = New-AppKey
        $key | Should -Match '^base64:'
        [Convert]::FromBase64String($key.Substring(7)).Length | Should -Be 32
    }
}

Describe 'Write-EnvFile' {
    BeforeEach {
        $script:EnvPath = Join-Path $TestDrive '.env'
        Remove-Item $EnvPath -ErrorAction SilentlyContinue
    }

    It 'writes <key> on first install' -ForEach @(
        @{ key = 'APP_ENV'; value = 'production' }
        @{ key = 'APP_LOCALE'; value = 'de_DE' }
        @{ key = 'APP_TIMEZONE'; value = 'UTC' }
        @{ key = 'DISPLAY_TIMEZONE'; value = 'Europe/Zurich' }
        @{ key = 'DB_CONNECTION'; value = 'sqlite' }
        @{ key = 'SPEEDTEST_SCHEDULE'; value = '30 * * * *' }
        @{ key = 'ST_PORT'; value = '8765' }
    ) {
        Write-EnvFile -Path $EnvPath -Port 8765 -Schedule '30 * * * *' -AppUrl 'http://192.0.2.1:8765'
        Get-EnvValue -Path $EnvPath -Key $key | Should -Be $value
    }

    It 'quotes values containing spaces' {
        Write-EnvFile -Path $EnvPath -Port 8765 -Schedule '30 * * * *' -AppUrl 'http://192.0.2.1:8765'
        (Get-Content $EnvPath) | Should -Contain 'SPEEDTEST_SCHEDULE="30 * * * *"'
    }

    It 'stores the database beside the env file' {
        Write-EnvFile -Path $EnvPath -Port 8765 -Schedule '30 * * * *' -AppUrl 'http://192.0.2.1:8765'
        Get-EnvValue -Path $EnvPath -Key 'DB_DATABASE' | Should -Be (Join-Path $TestDrive 'database.sqlite')
    }

    It 'keeps the key, manual edits and unknown lines on a second run' {
        Write-EnvFile -Path $EnvPath -Port 8765 -Schedule '30 * * * *' -AppUrl 'http://192.0.2.1:8765'
        $key = Get-EnvValue -Path $EnvPath -Key 'APP_KEY'
        Set-EnvValue -Path $EnvPath -Key 'APP_LOCALE' -Value 'en'
        Add-Content $EnvPath 'CUSTOM_THING=yes'

        Write-EnvFile -Path $EnvPath -Port 9000 -Schedule '0 * * * *' -AppUrl 'http://192.0.2.1:9000'

        Get-EnvValue -Path $EnvPath -Key 'APP_KEY' | Should -Be $key
        Get-EnvValue -Path $EnvPath -Key 'APP_LOCALE' | Should -Be 'en'
        Get-EnvValue -Path $EnvPath -Key 'CUSTOM_THING' | Should -Be 'yes'
        Get-EnvValue -Path $EnvPath -Key 'SPEEDTEST_SCHEDULE' | Should -Be '30 * * * *'
        Get-EnvValue -Path $EnvPath -Key 'ST_PORT' | Should -Be '8765'
    }
}

Describe 'Update-AppUrl' {
    BeforeEach {
        $script:EnvPath = Join-Path $TestDrive '.env'
        Remove-Item $EnvPath -ErrorAction SilentlyContinue
        Write-EnvFile -Path $EnvPath -Port 8765 -Schedule '30 * * * *' -AppUrl 'http://192.0.2.1:8765'
    }

    It 'follows a changed address' {
        Update-AppUrl -EnvPath $EnvPath -IPv4 '192.168.1.212'
        Get-EnvValue -Path $EnvPath -Key 'APP_URL' | Should -Be 'http://192.168.1.212:8765'
    }

    It 'keeps the old value without a network' {
        Mock Get-PrimaryIPv4 { $null }
        Update-AppUrl -EnvPath $EnvPath
        Get-EnvValue -Path $EnvPath -Key 'APP_URL' | Should -Be 'http://192.0.2.1:8765'
    }
}

Describe 'Get-PrimaryIPv4' {
    It 'returns an IPv4 address or nothing' {
        $ip = Get-PrimaryIPv4
        if ($ip) { $ip | Should -Match '^\d+\.\d+\.\d+\.\d+$' }
    }
}

Describe 'Test-PortFree' {
    It 'reports a free port as free' {
        $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $probe.Start()
        $port = $probe.LocalEndpoint.Port
        $probe.Stop()
        Test-PortFree -Port $port | Should -BeTrue
    }

    It 'reports a listening port as busy' {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, 0)
        $listener.Start()
        try {
            Test-PortFree -Port $listener.LocalEndpoint.Port | Should -BeFalse
        } finally {
            $listener.Stop()
        }
    }
}

Describe 'Install-OoklaCli' {
    BeforeAll {
        $src = Join-Path $TestDrive 'src'
        New-Item -ItemType Directory $src | Out-Null
        Set-Content (Join-Path $src 'speedtest.exe') 'fake'
        $script:Zip = Join-Path $TestDrive 'cli.zip'
        Compress-Archive (Join-Path $src '*') $Zip
        $script:ZipUrl = ([Uri]$Zip).AbsoluteUri
        $script:ZipHash = (Get-FileHash $Zip -Algorithm SHA256).Hash
    }

    It 'installs the CLI when the checksum matches' {
        $dest = Join-Path $TestDrive 'ok'
        Install-OoklaCli -Dest $dest -Url $ZipUrl -Sha256 $ZipHash -Version '1.2.0'
        Join-Path $dest 'speedtest.exe' | Should -Exist
    }

    It 'fails and leaves nothing behind on a wrong checksum' {
        $dest = Join-Path $TestDrive 'bad'
        { Install-OoklaCli -Dest $dest -Url $ZipUrl -Sha256 ('0' * 64) -Version '1.2.0' } | Should -Throw '*checksum*'
        Join-Path $dest 'speedtest.exe' | Should -Not -Exist
    }

    It 'fails with a clear message when the download fails' {
        $dest = Join-Path $TestDrive 'gone'
        $missing = ([Uri](Join-Path $TestDrive 'missing.zip')).AbsoluteUri
        { Install-OoklaCli -Dest $dest -Url $missing -Sha256 $ZipHash -Version '1.2.0' } | Should -Throw '*Ookla*'
    }

    It 'skips the download when the version is already installed' {
        $dest = Join-Path $TestDrive 'again'
        Install-OoklaCli -Dest $dest -Url $ZipUrl -Sha256 $ZipHash -Version '1.2.0'
        $missing = ([Uri](Join-Path $TestDrive 'missing.zip')).AbsoluteUri
        { Install-OoklaCli -Dest $dest -Url $missing -Sha256 $ZipHash -Version '1.2.0' } | Should -Not -Throw
    }
}

Describe 'Set-DataLinks' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive "root $(Get-Random)"
        $script:Data = Join-Path $TestDrive "data $(Get-Random)"
        New-Item -ItemType Directory (Join-Path $Root 'app\storage\framework\views') -Force | Out-Null
        Set-Content (Join-Path $Root 'app\storage\framework\skeleton.txt') 'x'
        New-Item -ItemType Directory $Data | Out-Null
        Set-Content (Join-Path $Data '.env') 'A=1'
        $script:CanLink = $true
        try {
            New-Item -ItemType SymbolicLink -Path (Join-Path $TestDrive "probe$(Get-Random)") -Target (Join-Path $Data '.env') -ErrorAction Stop | Out-Null
        } catch {
            $script:CanLink = $false
        }
    }

    It 'moves storage to the data folder and links it' {
        if (-not $CanLink) { Set-ItResult -Skipped -Because 'symbolic links need elevation here'; return }
        Set-DataLinks -Root $Root -DataDir $Data
        Join-Path $Data 'storage\framework\skeleton.txt' | Should -Exist
        (Get-Content (Join-Path $Root 'app\.env')) | Should -Be 'A=1'
        Set-Content (Join-Path $Root 'app\storage\written.txt') 'y'
        Join-Path $Data 'storage\written.txt' | Should -Exist
    }

    It 'keeps existing data when an update replaced the app folder' {
        if (-not $CanLink) { Set-ItResult -Skipped -Because 'symbolic links need elevation here'; return }
        New-Item -ItemType Directory (Join-Path $Data 'storage') | Out-Null
        Set-Content (Join-Path $Data 'storage\old.txt') 'keep'
        Set-DataLinks -Root $Root -DataDir $Data
        Set-DataLinks -Root $Root -DataDir $Data
        Join-Path $Root 'app\storage\old.txt' | Should -Exist
        Join-Path $Data 'storage\old.txt' | Should -Exist
    }
}

Describe 'Invoke-Install failure handling' {
    It 'does not start the service when the port is busy' {
        Mock Stop-TrackerService {}
        Mock Install-OoklaCli {}
        Mock Test-PortFree { $false }
        Mock Start-TrackerService {}
        { Invoke-Install -Root 'C:\none' -DataDir (Join-Path $TestDrive 'd1') -Port 8765 -Schedule '30 * * * *' -Versions ([pscustomobject]@{ ookla = @{ url = 'x'; sha256 = 'y'; version = 'z' } }) } | Should -Throw '*8765*'
        Should -Invoke Start-TrackerService -Times 0
    }

    It 'does not start the service when the Ookla download fails' {
        Mock Stop-TrackerService {}
        Mock Install-OoklaCli { throw 'Ookla download failed' }
        Mock Start-TrackerService {}
        { Invoke-Install -Root 'C:\none' -DataDir (Join-Path $TestDrive 'd2') -Port 8765 -Schedule '30 * * * *' -Versions ([pscustomobject]@{ ookla = @{ url = 'x'; sha256 = 'y'; version = 'z' } }) } | Should -Throw '*Ookla*'
        Should -Invoke Start-TrackerService -Times 0
    }
}
