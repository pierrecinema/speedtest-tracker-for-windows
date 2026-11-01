# Speedtest Tracker for Windows

Fork von [alexjustesen/speedtest-tracker](https://github.com/alexjustesen/speedtest-tracker), der ohne Docker auf Windows 10 und 11 läuft. Menüs, Aussehen und Funktionen sind gleich wie beim Original.

## Installieren

`SpeedtestTracker-Setup-<version>.exe` aus den [Releases](https://github.com/pierrecinema/speedtest-tracker-for-windows/releases) herunterladen und starten. Der Installer ist nicht signiert, Windows zeigt deshalb beim Start eine Warnung.

Danach läuft der Dienst `SpeedtestTracker` im Hintergrund und startet mit Windows. Die Web-Oberfläche ist unter `http://localhost:8765` und im lokalen Netz unter der Adresse des PCs erreichbar. Die Anmeldedaten beim ersten Start sind die des Originals. Ändere das Passwort sofort, weil die Oberfläche im Heimnetz erreichbar ist.

Eine neue Version installiert man, indem man den neuen Installer über die alte Installation laufen lässt. Einstellungen und Messwerte bleiben erhalten.

## Aufbau

- Programm: `C:\Program Files\Speedtest Tracker`
- Daten: `C:\ProgramData\SpeedtestTracker` (`.env`, Datenbank, Logs), nur für Administratoren lesbar
- WinSW startet `runtime/supervisor.ps1`. Das Skript überwacht Caddy, drei `php-cgi`, `queue:work` und `schedule:work`.
- `.env` und `storage` sind per Link ins Programmverzeichnis eingebunden.
- `APP_URL` folgt bei jedem Dienststart der aktuellen IP-Adresse.
- Die Ookla-CLI lädt der Installer direkt von Ookla, die Prüfsumme steht in `versions.json`.

## Abweichungen vom Original

- Am Anwendungscode ist nichts geändert.
- Die Ping-Prüfung vor einer Messung schlägt unter Windows fehl, weil `spatie/ping` Linux-Schalter nutzt. Das Original fällt dann selbst auf die HTTP-Prüfung zurück.
- Vorgaben in `.env`: `APP_LOCALE=de_DE`, `DISPLAY_TIMEZONE=Europe/Zurich`, `SPEEDTEST_SCHEDULE="30 * * * *"`.

## Bauen

```powershell
./windows/build/build.ps1
```

Tests laufen mit Pester 5 oder neuer:

```powershell
Invoke-Pester windows/tests/*.Tests.ps1
```

Der Workflow `.github/workflows/windows-release.yml` baut den Installer, testet Installation, Update und Deinstallation auf einem echten Windows und veröffentlicht bei einem Tag `v<version>-win.<n>` ein Release.

## Neue Version des Originals übernehmen

```bash
git fetch upstream --tags
git merge v<neue-version>
git tag v<neue-version>-win.1
git push origin windows --tags
```
