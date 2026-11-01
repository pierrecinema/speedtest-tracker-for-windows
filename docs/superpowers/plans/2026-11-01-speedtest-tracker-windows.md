# Speedtest Tracker für Windows: Umsetzungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein Setup-Assistent installiert Speedtest Tracker v1.15.1 nativ als Windows-Dienst auf Windows 10/11, ohne Docker und ohne Änderung am Anwendungscode.

**Architecture:** Alles Neue liegt in `windows/`. Ein Build-Skript erzeugt ein Stage-Verzeichnis (PHP, Caddy, WinSW, Anwendung), Inno Setup packt es. WinSW startet `supervisor.ps1`, das Caddy, drei `php-cgi`, `queue:work` und `schedule:work` überwacht. Daten liegen in `C:\ProgramData\SpeedtestTracker` und werden per Link eingebunden.

**Tech Stack:** PHP 8.4 NTS x64, Laravel 13 (unverändert), Caddy 2, WinSW 2, Inno Setup 6, PowerShell 5.1 (Laufzeit, auf Windows 10/11 vorhanden), Pester 5 (Tests), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-01-speedtest-tracker-windows-design.md`

## Global Constraints

- Keine Änderung unter `app/`, `config/`, `routes/`, `resources/`, `database/`. Muss doch eine sein, wird sie in `windows/README.md` aufgeführt.
- Laufzeit-Skripte müssen unter Windows PowerShell 5.1 laufen, nicht nur unter PowerShell 7.
- Programm: `C:\Program Files\Speedtest Tracker`. Daten: `C:\ProgramData\SpeedtestTracker`.
- Vorgaben: Port `8765`, `SPEEDTEST_SCHEDULE=30 * * * *`, `APP_LOCALE=de_DE`, `APP_TIMEZONE=UTC`, `DISPLAY_TIMEZONE=Europe/Zurich`, `DB_CONNECTION=sqlite`, `APP_ENV=production`.
- Dienstname `SpeedtestTracker`, Konto LocalSystem, Start automatisch.
- Ookla-CLI 1.2.0 wird nicht mitgeliefert. Der Installer lädt sie von `https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip`, prüft den SHA256-Wert und zeigt keine Lizenzabfrage.
- Firewall-Regel `Speedtest Tracker` eingehend, TCP, nur gewählter Port, `RemoteAddress LocalSubnet`.
- Es gelangen keine Tokens oder Passwörter ins Repository.
- Der Branch `1.x` bleibt unverändert. Alle Arbeit liegt im Branch `windows`.

## Review Focus

- Ookla-Download scheitert oder Prüfsumme stimmt nicht: Die Installation bricht mit klarer Meldung ab und hinterlässt keinen laufenden Dienst.
- Gewählter Port ist belegt: Der Installer meldet das vor dem Dienststart, statt einen Dienst ohne Web-Oberfläche zu hinterlassen.
- Installation über bestehende Version: `.env`, `APP_KEY`, Datenbank und API-Tokens bleiben erhalten, Migrationen laufen.
- Leerzeichen im Pfad (`C:\Program Files`): Caddyfile, WinSW-XML und PHP-Aufrufe funktionieren mit Anführungszeichen.
- Dienst stoppt oder PC fährt mitten in einer Messung herunter: Keine PHP-Prozesse bleiben zurück, und nach dem nächsten Start laufen geplante Messungen wieder.

---

## Dateien

```
windows/
  README.md                  Bauen, Aufbau, Abweichungen vom Original
  versions.json              Gepinnte Versionen, URLs, SHA256
  build/build.ps1            Erzeugt windows/build/out/stage
  runtime/php.ini
  runtime/Caddyfile.tpl
  runtime/supervisor.ps1     Überwacht Teilprozesse
  runtime/SpeedtestTracker.xml  WinSW-Konfiguration
  installer/provision.ps1    Schritte bei Installation und Deinstallation
  installer/setup.iss        Inno-Setup-Skript
  tests/*.Tests.ps1          Pester-Tests
.github/workflows/windows-release.yml
```

## Task 1: Reproduzierbares Stage-Verzeichnis

**Files:**
- Create: `windows/versions.json`, `windows/build/build.ps1`, `windows/runtime/php.ini`, `windows/tests/build.Tests.ps1`
- Modify: `.gitignore` (`windows/build/out/`)

**Interfaces:**
- Produces: `build.ps1 [-OutDir <path>]` erzeugt `<OutDir>/stage` mit `php\`, `caddy\caddy.exe`, `winsw\SpeedtestTracker.exe`, `vc_redist.x64.exe`, `cacert.pem`, `app\` (Anwendung ohne `.env`, ohne `tests/`, `docker/`, `.git`).
- Produces: `versions.json` mit Schlüsseln `php`, `caddy`, `winsw`, `vcredist`, `cacert`, `ookla`, jeweils `{ version, url, sha256 }`.

- [ ] **Step 1: Failing Test schreiben** in `build.Tests.ps1`: Alle Einträge in `versions.json` haben `https://`-URL und 64-stelliges `sha256`. `php -m` aus der Stage enthält `bcmath, curl, gd, intl, mbstring, openssl, pdo_mysql, pdo_pgsql, pdo_sqlite, sqlite3, zip`. `php artisan --version` gibt `Laravel Framework 13` aus. `app\.env` existiert nicht, `app\public\build\manifest.json` existiert.
- [ ] **Step 2: Test ausführen.** Run: `Invoke-Pester windows/tests/build.Tests.ps1`. Expected: FAIL, weil `versions.json` fehlt.
- [ ] **Step 3: `versions.json` anlegen.** Aktuelle PHP-8.4-NTS-Version (vs17, x64) von der offiziellen PHP-Downloadseite, Caddy 2 Windows amd64, WinSW 2.x x64, `vc_redist.x64` von Microsoft, `cacert.pem` von curl.se, Ookla 1.2.0. SHA256 jeweils durch Herunterladen ermitteln.
- [ ] **Step 4: `php.ini` schreiben.** Erweiterungen wie in Step 1, `curl.cainfo` und `openssl.cafile` relativ über `${ST_ROOT}\cacert.pem`, `variables_order=EGPCS`, `opcache` an, `memory_limit=512M`.
- [ ] **Step 5: `build.ps1` schreiben.** Download mit Prüfsumme, Abbruch bei Abweichung, `composer install --no-dev --optimize-autoloader` und `npm ci && npm run build` mit Werkzeugen aus `windows/build/out/tools`. Composer und PHP werden nicht systemweit installiert.
- [ ] **Step 6: Build und Test ausführen.** Expected: PASS.
- [ ] **Step 7: Testsuite des Originals auf Windows laufen lassen.** Run: `php artisan test` mit Dev-Abhängigkeiten in einem getrennten Ordner. Expected: Fehlschläge sind nur solche, die die Linux-Umgebung voraussetzen. Abweichungen in `windows/README.md` notieren.
- [ ] **Step 8: Commit.** `git commit -m "windows: reproducible stage build"`

## Task 2: Laufzeit und Dienst-Überwachung

**Files:**
- Create: `windows/runtime/Caddyfile.tpl`, `windows/runtime/supervisor.ps1`, `windows/runtime/SpeedtestTracker.xml`, `windows/tests/supervisor.Tests.ps1`

**Interfaces:**
- Consumes: Stage aus Task 1.
- Produces: `Get-ProcessDefinitions -Root <string> -DataDir <string> -> [pscustomobject[]]` mit `Name, FilePath, Arguments, WorkingDirectory`. Namen: `caddy`, `php-cgi-1` bis `php-cgi-3`, `queue`, `scheduler`.
- Produces: `supervisor.ps1 -Root <string> -DataDir <string>` läuft im Vordergrund, startet beendete Prozesse nach 5 Sekunden neu, Logs in `<DataDir>\logs\<name>.log`.
- Umgebung der Kindprozesse: `ST_ROOT=<Root>`, `PHP_FCGI_MAX_REQUESTS=0`, `PATH` beginnt mit `<DataDir>\ookla` und `<Root>\php`.

- [ ] **Step 1: Failing Tests schreiben:** `Get-ProcessDefinitions` liefert genau sechs Einträge. `php-cgi` nutzt `-b 127.0.0.1:9101` bis `9103`. Mit `-Root 'C:\Program Files\Speedtest Tracker'` stehen Pfade in `Arguments` in Anführungszeichen. `queue` nutzt `artisan queue:work --tries=3 --max-time=3600`, `scheduler` nutzt `artisan schedule:work`. Ein Test startet einen Dummy-Prozess, beendet ihn und erwartet einen Neustart.
- [ ] **Step 2: Test ausführen.** Expected: FAIL.
- [ ] **Step 3: `supervisor.ps1` umsetzen.** Prozessliste per Dot-Source testbar, Hauptschleife läuft nur bei direktem Aufruf.
- [ ] **Step 4: `Caddyfile.tpl` schreiben.** `:{{PORT}}`, `root * "{{ROOT}}\app\public"`, `php_fastcgi 127.0.0.1:9101 127.0.0.1:9102 127.0.0.1:9103`, `file_server`, Log in `{{DATA}}\logs`.
- [ ] **Step 5: `SpeedtestTracker.xml` schreiben.** Startet `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\..\runtime\supervisor.ps1"`, `startmode` Automatic, `delayedAutoStart`, `onfailure restart`, `stoptimeout 30sec`, damit WinSW den ganzen Prozessbaum beendet.
- [ ] **Step 6: Tests ausführen.** Expected: PASS.
- [ ] **Step 7: Smoke-Test im Vordergrund.** Stage mit Test-`DataDir` starten und `curl.exe http://127.0.0.1:8765/api/healthcheck` aufrufen. Expected: HTTP 200. Beim Beenden bleiben keine `php-cgi`- oder `php`-Prozesse zurück.
- [ ] **Step 8: Commit.** `git commit -m "windows: runtime supervisor and service config"`

## Task 3: Einrichtung bei Installation

**Files:**
- Create: `windows/installer/provision.ps1`, `windows/tests/provision.Tests.ps1`

**Interfaces:**
- Consumes: `versions.json`, Stage, `Caddyfile.tpl`.
- Produces: `provision.ps1 -Action Install -Root <path> -DataDir <path> -Port <int> -Schedule <string>` und `-Action Uninstall [-RemoveData]`. Exit-Code 0 bei Erfolg, sonst 1 mit Meldung in `<DataDir>\logs\install.log`.
- Produces (per Dot-Source testbar): `Write-EnvFile -Path -Port -Schedule -AppUrl`, `New-AppKey`, `Test-PortFree -Port`, `Install-OoklaCli -Dest -Url -Sha256`, `Get-PrimaryIPv4 -> string`, `Update-AppUrl -EnvPath -Port`.
- IP-Erkennung: Niemand gibt die Adresse von Hand ein. `Get-PrimaryIPv4` nimmt die IPv4-Adresse der Netzwerkkarte mit der Standardroute. `supervisor.ps1` ruft beim Start `Update-AppUrl` auf, damit `APP_URL` auch nach einem DHCP-Wechsel stimmt. Caddy lauscht auf allen Adressen. Ohne Netzwerk bleibt der alte Wert stehen.

- [ ] **Step 1: Failing Tests schreiben:**
  - `Write-EnvFile` legt beim ersten Mal alle Vorgaben aus den Global Constraints an, dazu `APP_KEY=base64:...` und `DB_DATABASE=<DataDir>\database.sqlite`.
  - Ein zweiter Aufruf behält `APP_KEY`, von Hand geänderte Werte und unbekannte Zeilen. Nur `APP_URL` ändert sich bei neuem Port. Werte mit Leerzeichen, wie der Zeitplan, stehen in Anführungszeichen.
  - `Test-PortFree` gibt `$false` zurück, wenn ein `TcpListener` den Port belegt.
  - `Install-OoklaCli` wirft bei falscher Prüfsumme und hinterlässt keine `speedtest.exe`.
- [ ] **Step 2: Tests ausführen.** Expected: FAIL.
- [ ] **Step 3: Funktionen umsetzen.** Downloads mit `[Net.ServicePointManager]::SecurityProtocol` auf TLS 1.2, sonst scheitern sie unter Windows 10 mit PowerShell 5.1.
- [ ] **Step 4: Ablauf von `-Action Install` umsetzen, in dieser Reihenfolge:** Dienst stoppen, falls vorhanden. Ookla laden. Port prüfen, außer er gehört dem eigenen Dienst. Ordner anlegen. `.env` schreiben. Storage-Struktur nach `<DataDir>\storage` kopieren, wenn sie fehlt. Datei-Link `app\.env` und Junction `app\storage` setzen. Datenbank anlegen, wenn sie fehlt. `artisan migrate --force` ausführen. `Caddyfile` aus der Vorlage schreiben. Firewall-Regel neu setzen. Dienst installieren, falls nötig, und starten. Schlägt ein Schritt vor dem Dienststart fehl, wird der Dienst nicht gestartet.
- [ ] **Step 5: `-Action Uninstall` umsetzen.** Dienst stoppen und entfernen, Firewall-Regel und Links löschen, `DataDir` nur mit `-RemoveData` entfernen.
- [ ] **Step 6: Tests ausführen.** Expected: PASS.
- [ ] **Step 7: Commit.** `git commit -m "windows: install and uninstall provisioning"`

## Task 4: Setup-Assistent und Release-Workflow

**Files:**
- Create: `windows/installer/setup.iss`, `.github/workflows/windows-release.yml`, `windows/README.md`

**Interfaces:**
- Consumes: Stage, `provision.ps1`.
- Produces: `windows/build/out/SpeedtestTracker-Setup-<version>.exe`. `<version>` ist `1.15.1-win.<n>`.

- [ ] **Step 1: `setup.iss` schreiben.** `ArchitecturesAllowed=x64compatible`, `PrivilegesRequired=admin`, `MinVersion=10.0`, feste `AppId`, Installationsordner fest. Eine Seite für Port und Zeitplan. Vorbelegung bei Update aus `.env`. `vc_redist.x64.exe /install /quiet /norestart` ausführen. Danach `provision.ps1 -Action Install`, bei Exit-Code ungleich 0 Meldung mit Pfad zu `install.log`. Abschlussseite öffnet `http://localhost:<Port>`. Deinstallation fragt nach dem Löschen der Daten, Vorgabe behalten.
- [ ] **Step 2: Workflow schreiben.** Läuft auf `windows-latest`, ausgelöst durch Tags `v*-win.*`: Pester-Tests, `build.ps1`, Inno Setup kompilieren, `.exe` an ein GitHub-Release hängen.
- [ ] **Step 3: `windows/README.md` schreiben.** Bauen, Aufbau, Update vom Original (`git merge` von `upstream`-Tag in `windows`, neuer Tag), Abweichungen vom Original.
- [ ] **Step 4: Prüfen.** Tag `v1.15.1-win.1` pushen. Expected: Workflow grün, Release enthält die `.exe`.
- [ ] **Step 5: Commit.** `git commit -m "windows: installer and release workflow"`

## Task 5: Echter Durchlauf auf Windows 11

**Files:** keine neuen. Gefundene Fehler werden in der zuständigen Datei behoben, jeweils mit Pester-Test.

- [ ] **Step 1: Installieren.** Release-`.exe` auf diesem PC ausführen. Expected: Dienst `SpeedtestTracker` läuft, `http://localhost:8765` zeigt die Anmeldung auf Deutsch.
- [ ] **Step 2: Vergleich mit dem Original.** Menüs und Einstellungsseiten gegen den Tracker auf `192.168.1.201:8765` prüfen. Expected: gleich, abgesehen von Version und Sprache.
- [ ] **Step 3: Messung.** Von Hand und per Zeitplan. Expected: Ergebnis mit Status `completed`, trotz fehlgeschlagenem Ping.
- [ ] **Step 4: Abruf aus dem Heimnetz.** Von einem anderen Gerät mit Token `GET /api/v1/results/latest`. Expected: Felder gleich wie beim Tracker auf .201.
- [ ] **Step 5: Benachrichtigung und HTTPS.** Eine Test-Benachrichtigung auslösen. Expected: kein Zertifikatsfehler.
- [ ] **Step 6: Neustart ohne Anmeldung.** Expected: Dienst läuft, nächste Messung erfolgt.
- [ ] **Step 7: Stopp mitten in einer Messung.** Expected: keine Prozesse bleiben zurück, nach dem Start gehen die Messungen weiter.
- [ ] **Step 8: Update.** Neue `-win.2`-Version über die alte installieren. Expected: Messwerte, Token und Einstellungen bleiben.
- [ ] **Step 9: Fehlerfälle.** Belegter Port und blockierter Ookla-Download. Expected: klare Meldung, kein halb laufender Dienst.
- [ ] **Step 10: Deinstallation.** Expected: Dienst und Firewall-Regel weg, Daten bleiben außer bei ausdrücklichem Löschen.

## Task 6: openHAB anbinden

**Files:** keine im Repository. Änderungen nur auf dem openHAB-Server.

Der Tracker läuft auf dem Desktop-PC `192.168.1.212`. Die Installation und den echten Durchlauf aus Task 5 macht der Besitzer dort selbst, das Token kommt aus der Web-Oberfläche auf .212.

- [ ] **Step 1: Bestehende Kanäle lesen.** Zustandspfade von `http:url:Speedtest_Tracker` per openHAB-API auslesen und dasselbe Muster verwenden.
- [ ] **Step 2: API-Token erzeugen.** Nur mit Leserecht, in der Web-Oberfläche. Das Token nicht im Chat oder Repository wiederholen.
- [ ] **Step 3: Thing anlegen.** `http:url:Speedtest_Tracker_Desktop`, `refresh=300`, `timeout=5000`, neun Kanäle wie beim Vorbild.
- [ ] **Step 4: Items verbinden.** Vier bestehende Items verknüpfen, fünf neue anlegen: `DesktopPC_Speedtest_Jitter`, `_Paketverlust`, `_ISP`, `_Server`, `_Zeitpunkt`.
- [ ] **Step 5: Zeitplan abgleichen.** Mit dem Zeitplan des Trackers auf .201 vergleichen. Überschneiden sie sich, den Wert in der Oberfläche ändern.
- [ ] **Step 6: Prüfen.** Nach dem nächsten Abruf: Thing `ONLINE`, Items mit Werten. Bei ausgeschaltetem PC: Thing `OFFLINE`, Werte bleiben stehen.
- [ ] **Step 7: Widget.** Das bestehende Main-UI-Widget der beiden anderen Tracker suchen und für die `DesktopPC_Speedtest_*`-Items gleich aufbauen. Expected: gleiches Aussehen, Werte vom Desktop-PC.
