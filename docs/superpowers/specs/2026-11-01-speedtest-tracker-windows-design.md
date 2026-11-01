# Speedtest Tracker für Windows: Entwurf

Stand: 2026-11-01. Basis: Original `alexjustesen/speedtest-tracker`, Version v1.15.1 (MIT-Lizenz).

## Absicht

Ein dritter Speedtest Tracker läuft direkt auf einem Windows-PC, ohne Docker. Er misst regelmäßig den Anschluss und zeigt den Verlauf im Browser. Dein openHAB-Server ruft die Werte wie bei den zwei bestehenden Trackern ab und speichert sie. Der Zweck ist Interesse und Monitoring, vorerst nur für dich.

## Ziele

- Ein einziger Setup-Assistent für Windows 10 und 11 (64 Bit) installiert alles. Vorher muss nichts von Hand installiert werden.
- Der Tracker läuft als Windows-Dienst im Hintergrund und startet mit Windows, auch ohne Anmeldung.
- Menüs, Aussehen und Funktionen sind gleich wie beim Original: Zeitplan, Serverauswahl, Benachrichtigungen, Schwellenwerte, API.
- Die API verhält sich genau wie beim Original, damit openHAB die Werte auf dieselbe Weise abrufen kann.
- Eine neue Version wird installiert, indem man den neuen Installer über die alte Installation laufen lässt. Einstellungen und Messwerte bleiben erhalten.

## Nicht-Ziele

- Kein Aufwecken des PCs. Lücken im Verlauf werden in Kauf genommen, verpasste Messungen werden nicht nachgeholt.
- Kein Zugriff von außerhalb des Heimnetzes, kein HTTPS.
- Keine Code-Signatur. Windows warnt beim Start des Installers.
- Keine automatischen Updates und kein Symbol im Infobereich.
- Kein neues Design und keine neuen Funktionen gegenüber dem Original.

## Was als Fehlschlag gilt, auch wenn es technisch läuft

- openHAB bekommt andere Felder oder Werte als von den beiden anderen Trackern.
- Neue Versionen des Originals lassen sich nur mit viel Handarbeit übernehmen.
- Ein Update oder eine Neuinstallation verliert Messwerte oder Einstellungen.
- Du musst nach dem Installer noch PHP, Datenbank oder Ähnliches von Hand einrichten.

## Deine Vorgaben

- Fork im GitHub-Konto `pierrecinema`, möglichst nah am Original.
- Kein Docker.
- Installer bringt fehlende Tools selbst mit.
- Zugriff nur im internen Netz, openHAB ruft die Daten ab.
- PC wird nicht aufgeweckt, Lücken sind in Ordnung.

## Was das Original verlangt (geprüft in v1.15.1)

- PHP 8.3 oder neuer, Laravel 13, Datenbank standardmäßig SQLite. Das Docker-Image nutzt PHP 8.4.
- Warteschlange und Cache liegen in der Datenbank, ein Redis-Server ist also nicht nötig.
- Drei Abläufe müssen dauerhaft laufen: Webserver, Warteschlange (`queue:work`) und Zeitplan (`schedule:work` oder ein Aufruf pro Minute).
- Betriebssystemnahe Aufrufe gibt es nur zwei: `speedtest` wird in `RunSpeedtestJob` und `SelectSpeedtestServerJob` gestartet. Beide übergeben eine Argumentliste und suchen das Programm über den PATH. Wenn `speedtest.exe` im PATH des Dienstes liegt, ist dafür keine Code-Änderung nötig.
- Dazu kommt die Ping-Prüfung vor jeder Messung über `spatie/ping`. Die Bibliothek nutzt Linux-Schalter und schlägt unter Windows fehl. `CheckForInternetConnectionJob` fällt dann von selbst auf eine HTTP-Prüfung zurück, die Messung läuft also trotzdem. Eine Code-Änderung ist dafür nicht nötig.
- openHAB fragt per HTTP mit Bearer-Token ab, alle 300 Sekunden, Zeitüberschreitung 5 Sekunden.

## Aufbau (meine Entscheidungen)

**Repository**
- Fork `pierrecinema/speedtest-tracker`. Forks öffentlicher Repositories sind auf GitHub immer öffentlich, dieser also auch.
- Der Branch `1.x` bleibt unverändert und folgt dem Original. Die Windows-Arbeit liegt im Branch `windows`.
- Alles Neue liegt im Ordner `windows/` (Installer, Dienst-Konfiguration, Build). Anwendungscode wird nur geändert, wenn es nicht anders geht, und jede solche Änderung wird in `windows/README.md` aufgeführt.

**Installer**
- Inno Setup. Der fertige `SpeedtestTracker-Setup-<version>.exe` wird von GitHub Actions gebaut und als Release veröffentlicht.
- Enthalten: PHP (x64, NTS) mit den nötigen Erweiterungen, die benötigten Microsoft-Laufzeitbibliotheken, Webserver, Dienst-Verwaltung, die Anwendung mit installierten Abhängigkeiten und gebauten Oberflächen-Dateien. Für die Nutzung brauchst du also weder Composer noch Node.
- Die Ookla-CLI liegt nicht im Installer, weil ich nicht prüfen konnte, ob sie mitgeliefert werden darf. Der Installer lädt sie still direkt von Ookla, ohne Lizenzabfrage. Wie beim Original übergibt die Anwendung bei jeder Messung `--accept-license` und `--accept-gdpr`, es erscheint also auch später kein Lizenzhinweis.
- Abfragen im Assistenten: Port (Vorgabe 8765, wie bei deinem Tracker auf .201) und Zeitplan.

**Orte**
- Programm: `C:\Program Files\Speedtest Tracker`
- Daten: `C:\ProgramData\SpeedtestTracker` (`.env`, SQLite-Datenbank, Logs, Laravel-Speicher). Die Einstellungen bleiben über die üblichen Namen in `.env` setzbar, also dieselben wie beim Original.
- Bei der Deinstallation fragt der Assistent, ob die Daten gelöscht werden sollen. Vorgabe ist behalten.

**Dienst**
- Ein Windows-Dienst `SpeedtestTracker` startet automatisch und überwacht Webserver, Warteschlange und Zeitplan. Stürzt einer ab, wird er neu gestartet.
- Beim ersten Start werden `APP_KEY` erzeugt und die Datenbank eingerichtet, bei Updates die Migrationen ausgeführt.

**Netzwerk**
- Eingehende Firewall-Regel nur für den gewählten Port und nur fürs lokale Subnetz.

**Vorgaben beim Zeitplan**
- `30 * * * *`, also stündlich zur halben Stunde. Laufen zwei Tracker am selben Anschluss gleichzeitig, verfälschen sie sich gegenseitig. Beim Einrichten gleiche ich das mit dem echten Zeitplan deines Trackers auf .201 ab.

## openHAB

- Neues HTTP-Thing nach dem Muster von `http:url:Speedtest_Tracker`: gleiche Kanäle, gleiche Abfragepfade, Abfrage alle 300 Sekunden, eigenes API-Token.
- Es gibt schon die leeren Items `DesktopPC_Speedtest_Download`, `_Upload`, `_Ping` und `_Healthy`. Diese werden verbunden. Für Jitter, Paketverlust, ISP, Server und Zeitpunkt lege ich neue Items an, gleich wie bei den anderen Trackern.
- Das Token erzeugst du in der Web-Oberfläche oder ich erzeuge es beim Einrichten mit dir. Es landet nur in openHAB, nicht im Repository.
- Ist der PC aus, geht das Thing offline und die Items behalten den letzten Wert. Der Zeitpunkt der Messung zeigt, wie alt er ist.

## Tests

- Testsuite des Originals auf Windows mit dem mitgelieferten PHP.
- Echter Durchlauf auf deinem Windows 11: Installieren, Neustart ohne Anmeldung, Messung per Zeitplan und von Hand, Abruf aus dem Heimnetz, Update über eine ältere Version, Deinstallation.
- Abruf der Werte durch openHAB.
- Windows 10 wird unterstützt, kann hier aber nicht getestet werden. Der Build-Server von GitHub bietet nur Windows Server.

## Risiken

- **Ping-Prüfung:** Vor jeder Messung schlägt der Ping fehl und die HTTP-Prüfung übernimmt. Im Debug-Log steht dann ein Eintrag, sonst merkst du nichts. Der Code der Anwendung bleibt voraussichtlich unverändert.
- **Warteschlange:** Unter Windows setzt PHP ohne `pcntl` keine Job-Zeitlimits durch. Das Limit des Speedtest-Prozesses selbst greift weiter, sollte also genügen. Das prüfe ich im Test.
- **Installer-Warnung:** Antivirus oder SmartScreen können den unsignierten Installer blockieren oder warnen.

## Technische Entscheidungen für den Bau

- Webserver: Caddy mit drei `php-cgi`-Prozessen, weil `php-cgi` unter Windows pro Prozess nur eine Anfrage bearbeitet. `php artisan serve` scheidet aus, weil mehrere Worker unter Windows nicht gehen.
- Dienst: WinSW startet ein PowerShell-Skript, das alle Teilprozesse überwacht.
- Konto des Dienstes: LocalSystem.
- `.env` und `storage` liegen in `ProgramData` und werden per Link ins Programmverzeichnis eingebunden. So bleibt der Anwendungscode unverändert.
- Zeitzone `Europe/Zurich` und Sprache `de_DE` als Vorgabe, in `.env` änderbar.
- Exakte Liste der PHP-Erweiterungen ausgehend vom Dockerfile, plus ein mitgeliefertes CA-Zertifikatsbündel, weil PHP unter Windows sonst keine HTTPS-Ziele prüfen kann.
