# 🐇 Speedtest Tracker for Windows

Dieser Fork von [alexjustesen/speedtest-tracker](https://github.com/alexjustesen/speedtest-tracker) läuft ohne Docker direkt auf Windows 10 und 11. Menüs, Aussehen und Funktionen sind gleich wie beim Original.

Speedtest Tracker is a self-hosted application that monitors the performance and uptime of your internet connection.

![Dashboard](.github/screenshots/dashboard.png)

## Features

- **Automated Tests**: Schedule regular speed tests to monitor your internet connection's performance over time.
- **Detailed Metrics**: Capture download and upload speeds, ping, packet loss and more.
- **Historical Data**: View historical data and trends to identify patterns and issues with your internet connection.
- **Notifications**: Receive notifications when your internet performance drops below a certain threshold.
- **Multi-Language Support**: Available in multiple languages with community translations via [Crowdin](https://crowdin.com/project/speedtest-tracker).

## Getting Started

1. `SpeedtestTracker-Setup-<version>.exe` aus den [Releases](https://github.com/pierrecinema/speedtest-tracker-for-windows/releases) herunterladen.
2. Datei starten und dem Assistenten folgen. Der Installer ist nicht signiert, Windows zeigt deshalb eine Warnung. Unter „Weitere Informationen“ lässt er sich trotzdem starten.
3. `http://localhost:8765` öffnen, mit den Standarddaten des Originals anmelden und das Passwort sofort ändern.

Alles Nötige kommt mit, Docker oder PHP müssen nicht installiert sein. Der Tracker läuft als Windows-Dienst im Hintergrund, startet mit Windows und ist im lokalen Netz über die IP-Adresse des PCs erreichbar. Ist der PC aus oder im Schlafmodus, wird nicht gemessen.

Weitere Informationen:

- [Windows-Anleitung](windows/README.md): Aufbau, Update, Bauen des Installers
- [Konfiguration](https://docs.speedtest-tracker.dev/getting-started/environment-variables): Die Einstellungen stehen in `C:\ProgramData\SpeedtestTracker\.env`.
- [Benachrichtigungen](https://docs.speedtest-tracker.dev/settings/notifications)
- [Häufige Fragen](https://docs.speedtest-tracker.dev/help/faqs)

## Translations

Speedtest Tracker supports multiple languages thanks to our community translators!

**Request a new language**: Visit our [Crowdin project](https://crowdin.com/project/speedtest-tracker) and request a new language directly in crowdin.

**Help translate**: Join our [Crowdin project](https://crowdin.com/project/speedtest-tracker) to contribute translations in your language. All translation levels are welcome!
