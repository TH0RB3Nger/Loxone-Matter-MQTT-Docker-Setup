# Ambientika / Matterbridge / MQTT Deployment

Docker-Deployment für eine Synology NAS mit:

- Matterbridge
- Portainer CE
- Eclipse Mosquitto MQTT Broker
- Ambientika MQTT Bridge
- automatischer Verwaltung eines Docker-Macvlan-Netzwerks
- automatischem Klonen und Aktualisieren der Ambientika MQTT Bridge
- automatischem Build des lokalen Ambientika-Docker-Images
- Radon-Schutz / NeuraCell-X
- Taupunktsteuerung

---

# Inhaltsverzeichnis

- [Projektübersicht](#projektübersicht)
- [Architektur](#architektur)
- [Datenfluss](#datenfluss)
- [Projektstruktur](#projektstruktur)
- [Persistente Datenstruktur](#persistente-datenstruktur)
- [Netzwerkstruktur](#netzwerkstruktur)
- [Konfigurationsstruktur](#konfigurationsstruktur)
- [Voraussetzungen](#voraussetzungen)
- [Installation](#installation)
- [.env konfigurieren](#env-konfigurieren)
- [config.yaml konfigurieren](#configyaml-konfigurieren)
- [deploy.sh vorbereiten](#deploysh-vorbereiten)
- [Erster Start](#erster-start)
- [deploy.sh Befehle](#deploysh-befehle)
- [Dry-Run](#dry-run)
- [Docker-Dienste](#docker-dienste)
- [Matterbridge](#matterbridge)
- [Portainer](#portainer)
- [Mosquitto MQTT](#mosquitto-mqtt)
- [Ambientika MQTT Bridge](#ambientika-mqtt-bridge)
- [Radon-Schutz / NeuraCell-X](#radon-schutz--neuracell-x)
- [Taupunktsteuerung](#taupunktsteuerung)
- [Updates](#updates)
- [Status und Logs](#status-und-logs)
- [Backup](#backup)
- [Entfernen des Stacks](#entfernen-des-stacks)
- [Fehlerdiagnose](#fehlerdiagnose)

---

# Projektübersicht

Dieses Projekt stellt einen Docker-Compose-Stack bereit, der mehrere Dienste auf einer Synology NAS zusammen betreibt.

Die zentrale Steuerung erfolgt über `deploy.sh`.

Das Skript übernimmt unter anderem:

1. Prüfung der Voraussetzungen
2. Laden und Validieren der `.env`
3. Prüfung der IP-Konfiguration
4. Prüfung des Parent-Netzwerkinterfaces
5. Erstellung der persistenten Datenverzeichnisse
6. Erstellung der Mosquitto-Konfiguration
7. Einrichtung des MQTT-Benutzers
8. Klonen bzw. Aktualisieren des Ambientika Git-Repositories
9. Prüfung des Ambientika Source-Codes
10. Erstellung bzw. Prüfung des Docker-Macvlan
11. Validierung der Docker-Compose-Konfiguration
12. Build des lokalen Ambientika Docker-Images
13. Start und Aktualisierung des Docker-Stacks

---

# Architektur

```text
                              HEIMNETZ / LAN
                         192.168.x.0/24
                                  │
                                  │
                  ┌───────────────┴───────────────┐
                  │                               │
                  │         Synology NAS          │
                  │                               │
                  │          Docker Host          │
                  │                               │
                  └───────────────┬───────────────┘
                                  │
                  ┌───────────────┴────────────────┐
                  │                                │
                  │       Docker-Netzwerke         │
                  │                                │
          ┌───────▼────────────┐          ┌────────▼───────────┐
          │    Macvlan         │          │     mqtt_net       │
          │                    │          │     intern         │
          │ matter_macvlan     │          │                     │
          └────────┬───────────┘          └────────┬────────────┘
                   │                               │
                   │                               │
          ┌────────▼───────────┐          ┌────────▼─────────────┐
          │   Matterbridge     │          │      Mosquitto       │
          │                    │          │                      │
          │ eigene LAN-IP      │          └────────▲─────────────┘
          └────────────────────┘                   │
                                                   │ MQTT
                                                   │
                                          ┌────────┴─────────────┐
                                          │ Ambientika MQTT      │
                                          │ Bridge               │
                                          └────────▲─────────────┘
                                                   │
                                                   │ HTTPS / API
                                                   │
                                          ┌────────┴─────────────┐
                                          │   Ambientika Cloud   │
                                          └──────────────────────┘


          ┌─────────────────────────────────────────────┐
          │                  Portainer                  │
          │                                             │
          │  Zugriff auf Docker über docker.sock        │
          └─────────────────────────────────────────────┘
```

---

# Datenfluss

## Ambientika

```text
Ambientika Cloud
      │
      │ HTTPS / API
      ▼
Ambientika MQTT Bridge
      │
      │ MQTT
      ▼
Mosquitto MQTT Broker
      │
      ├──────────────────────► Loxone
      │
      └──────────────────────► Home Assistant
                               MQTT Discovery
```

Die Ambientika Bridge verbindet sich intern mit dem Docker-Hostname:

```text
mosquitto:1883
```

Für externe MQTT-Clients wird der MQTT-Port auf der Synology veröffentlicht.

---

# Projektstruktur

```text
ambientika-matterbridge/
│
├── .env
│   │
│   ├── Zeitzone
│   ├── Compose-Projektname
│   ├── Macvlan-Konfiguration
│   ├── Matterbridge-IP
│   ├── Datenpfade
│   ├── Portainer-Ports
│   ├── MQTT-Zugangsdaten
│   ├── Ambientika Repository
│   ├── Ambientika Image
│   └── Ambientika Zugangsdaten
│
├── compose.yml
│   │
│   ├── matterbridge
│   ├── portainer
│   ├── mosquitto
│   └── ambientika-bridge
│
├── config.yaml
│   │
│   ├── ambientika
│   ├── mqtt
│   ├── bridge
│   ├── neuracell
│   └── dewpoint
│
├── deploy.sh
│   │
│   ├── Systemprüfungen
│   ├── .env Validierung
│   ├── IP Validierung
│   ├── Verzeichnisverwaltung
│   ├── Mosquitto Einrichtung
│   ├── Git Repository Verwaltung
│   ├── Docker Image Build
│   ├── Macvlan Verwaltung
│   └── Compose Stack Verwaltung
│
└── README.md
    │
    └── Installation und technische Dokumentation
```

---

# Persistente Datenstruktur

Die tatsächlichen Pfade werden in `.env` definiert.

Beispiel:

```text
/volume1/docker/
│
├── matterbridge/
│   │
│   └── Persistente Matterbridge-Daten
│
├── portainer/
│   │
│   └── Portainer-Daten
│
├── mosquitto/
│   │
│   ├── config/
│   │   ├── mosquitto.conf
│   │   └── passwd
│   │
│   ├── data/
│   │   └── Persistente MQTT-Daten
│   │
│   └── log/
│       └── mosquitto.log
│
└── ambientika-mqtt-bridge/
    │
    └── source/
        │
        ├── Dockerfile
        ├── bridge.py
        ├── requirements.txt
        └── weiterer Source-Code
```

Die Verzeichnisse werden beim Start automatisch durch `deploy.sh` erstellt.

---

# Netzwerkstruktur

## Matterbridge Macvlan

Matterbridge verwendet ein externes Docker-Macvlan.

```text
LAN
│
├── Router / Gateway
│
├── Synology NAS
│
└── Matterbridge Container
    │
    └── eigene IP-Adresse im LAN
```

Beispiel:

```env
MACVLAN_NETWORK=matter_macvlan
MACVLAN_PARENT=ovs_eth0
MACVLAN_SUBNET=192.168.178.0/24
MACVLAN_GATEWAY=192.168.178.1

MATTERBRIDGE_IP=192.168.178.242
```

Die Matterbridge-IP muss innerhalb des definierten Subnetzes liegen.

Das `deploy.sh` prüft:

- gültiges CIDR-Format
- gültige Gateway-IP
- gültige Matterbridge-IP
- Matterbridge-IP innerhalb des Subnetzes
- Gateway innerhalb des Subnetzes
- Existenz des Parent-Interfaces

---

## Internes MQTT-Netzwerk

Mosquitto und die Ambientika Bridge verwenden ein internes Docker-Bridge-Netzwerk:

```text
mqtt_net

┌─────────────────────┐
│      Mosquitto      │
│                     │
│ Hostname: mosquitto │
└──────────▲──────────┘
           │
           │ MQTT
           │
┌──────────┴──────────┐
│ Ambientika Bridge   │
└─────────────────────┘
```

Dieses Netzwerk wird durch Docker Compose verwaltet.

---

# Konfigurationsstruktur

Die Konfiguration ist bewusst in mehrere Bereiche getrennt.

```text
                     deploy.sh
                         │
                         │ liest
                         ▼
                       .env
                         │
             ┌───────────┼────────────┐
             │           │            │
             ▼           ▼            ▼
         Netzwerk      Pfade      Zugangsdaten
             │           │            │
             └───────────┼────────────┘
                         │
                         ▼
                    compose.yml
                         │
          ┌──────────────┼───────────────┐
          │              │               │
          ▼              ▼               ▼
    Matterbridge     Portainer       Mosquitto
                                          │
                                          ▼
                                  Ambientika Bridge
                                          │
                                          │ verwendet
                                          ▼
                                     config.yaml
                                          │
                  ┌───────────────────────┼───────────────────────┐
                  │                       │                       │
                  ▼                       ▼                       ▼
             Cloud / MQTT            Radon-Schutz         Taupunktsteuerung
```

## `.env`

Enthält:

- Docker-/Host-Konfiguration
- Pfade
- Netzwerk
- Ports
- Zugangsdaten
- Git-Repository
- Image-Namen

## `compose.yml`

Definiert:

- Docker-Container
- Images
- Volumes
- Ports
- Docker-Netzwerke
- Abhängigkeiten

## `config.yaml`

Definiert die funktionale Konfiguration der Ambientika MQTT Bridge.

---

# Voraussetzungen

Auf der Synology müssen verfügbar sein:

- Container Manager / Docker
- Docker Compose über `docker compose`
- Git
- Bash
- Zugriff als `root`

Das Deployment-Skript muss als `root` ausgeführt werden.

Prüfen:

```bash
docker --version
docker compose version
git --version
```

---

# Installation

## 1. Projektverzeichnis erstellen

Beispiel:

```bash
mkdir -p /volume1/docker/ambientika-deployment
cd /volume1/docker/ambientika-deployment
```

Folgende Dateien in dieses Verzeichnis kopieren:

```text
.env
compose.yml
config.yaml
deploy.sh
README.md
```

---

# .env konfigurieren

Die `.env` enthält die Infrastrukturkonfiguration.

Wichtige Bereiche:

## Zeitzone

```env
TZ=Europe/Berlin
```

## Compose-Projekt

```env
COMPOSE_PROJECT_NAME=matterbridge
```

## Macvlan

```env
MACVLAN_NETWORK=matter_macvlan
MACVLAN_PARENT=ovs_eth0
MACVLAN_SUBNET=192.168.178.0/24
MACVLAN_GATEWAY=192.168.178.1
```

`MACVLAN_PARENT` muss dem tatsächlich verwendeten Netzwerkinterface der Synology entsprechen.

Mögliche Beispiele:

```text
eth0
ovs_eth0
bond0
```

## Matterbridge

```env
MATTERBRIDGE_IP=192.168.178.242
MATTERBRIDGE_DATA=/volume1/docker/matterbridge
```

Die IP-Adresse sollte im Heimnetz frei sein.

## Portainer

```env
PORTAINER_DATA=/volume1/docker/portainer
PORTAINER_HTTP_PORT=9000
PORTAINER_HTTPS_PORT=9443
```

## Mosquitto

```env
MQTT_DATA=/volume1/docker/mosquitto
MQTT_PORT=1883

MQTT_USER=loxone
MQTT_PASSWORD=EIN_SICHERES_PASSWORT
```

Das Passwort muss vor dem ersten Start geändert werden.

## Ambientika Repository

```env
AMBIENTIKA_DATA=/volume1/docker/ambientika-mqtt-bridge

AMBIENTIKA_REPOSITORY=https://github.com/ambientika-eu/ambientika-mqtt-bridge.git
AMBIENTIKA_BRANCH=main

AMBIENTIKA_IMAGE=ambientika-mqtt-bridge:latest
```

## Ambientika Zugangsdaten

```env
AMBIENTIKA_USER=DEINE_AMBIENTIKA_EMAIL
AMBIENTIKA_PASS=DEIN_AMBIENTIKA_PASSWORT
```

## Internes MQTT

```env
MQTT_HOST=mosquitto
```

Innerhalb des Docker-Netzwerks ist `mosquitto` der korrekte Hostname.

## Automatische Repository-Aktualisierung

```env
AMBIENTIKA_AUTO_UPDATE=true
```

Mögliche Werte:

```text
true
false
```

Bei `true` wird das Ambientika Repository bei Start und Update aktualisiert.

---

# config.yaml konfigurieren

Die `config.yaml` enthält die eigentliche Funktionskonfiguration der Ambientika Bridge.

---

## Ambientika Cloud

```yaml
ambientika:

  username: ""
  password: ""

  host: "https://app.ambientika.eu:4521"
```

Benutzername und Passwort bleiben in dieser Datei leer, da die Zugangsdaten über `.env` als Environment-Variablen übergeben werden.

---

## MQTT

```yaml
mqtt:

  host: "mosquitto"
  port: 1883

  username: ""
  password: ""

  tls: false
```

Die Zugangsdaten werden ebenfalls über `.env` an den Container übergeben.

---

## Bridge

```yaml
bridge:

  topic_prefix: "ambientika"

  discovery_prefix: "homeassistant"

  enable_discovery: true

  poll_interval: 30

  availability_failure_threshold: 3

  log_level: "INFO"
```

### `topic_prefix`

Präfix für die Ambientika MQTT Topics.

Beispiel:

```text
ambientika/DEVICE123/state
```

### `discovery_prefix`

Home-Assistant-MQTT-Discovery-Präfix.

Standard:

```text
homeassistant
```

### `enable_discovery`

```yaml
true
```

Aktiviert die Veröffentlichung von Home-Assistant-Discovery-Topics.

### `poll_interval`

Abfrageintervall der Ambientika Cloud in Sekunden.

Beispiel:

```yaml
poll_interval: 30
```

### `availability_failure_threshold`

Anzahl aufeinanderfolgender fehlgeschlagener Abfragen, bevor Geräte als offline markiert werden.

### `log_level`

Mögliche Werte:

```text
DEBUG
INFO
WARNING
ERROR
```

---

# deploy.sh vorbereiten

Das Skript ausführbar machen:

```bash
chmod +x deploy.sh
```

Da das Skript als `root` ausgeführt werden muss:

```bash
sudo ./deploy.sh
```

Alternativ direkt in einer Root-Shell:

```bash
./deploy.sh
```

---

# Erster Start

Vor dem ersten Start empfiehlt sich ein Dry-Run:

```bash
sudo ./deploy.sh --dry-run
```

Dabei werden:

- Konfigurationsdateien geprüft
- Docker geprüft
- Git geprüft
- `.env` geladen
- Variablen geprüft
- IP-Konfiguration geprüft
- Parent-Interface geprüft
- Datenverzeichnisse geprüft
- Mosquitto-Konfiguration vorbereitet
- Ambientika Repository geprüft
- Ambientika Source-Code geprüft
- Macvlan geprüft
- Compose-Konfiguration geprüft

Anschließend starten:

```bash
sudo ./deploy.sh
```

oder:

```bash
sudo ./deploy.sh start
```

---

# deploy.sh Befehle

## Start

```bash
sudo ./deploy.sh
```

oder:

```bash
sudo ./deploy.sh start
```

Führt die vollständige Startprüfung durch und startet den Stack.

---

## Stop

```bash
sudo ./deploy.sh stop
```

Stoppt die Container.

---

## Restart

```bash
sudo ./deploy.sh restart
```

Startet die vorhandenen Container neu.

---

## Status

```bash
sudo ./deploy.sh status
```

Zeigt:

- Compose-Containerstatus
- Ambientika Docker Image
- Macvlan-Konfiguration
- mit dem Macvlan verbundene Container
- internes MQTT-Netzwerk

---

## Update

```bash
sudo ./deploy.sh update
```

Das Update:

1. prüft die Konfiguration
2. aktualisiert das Ambientika Repository
3. lädt die normalen Docker Images
4. baut das Ambientika Image neu
5. erstellt die Container neu

---

## Pull

```bash
sudo ./deploy.sh pull
```

Lädt aktuelle Docker Images herunter.

---

## Ambientika Image

```bash
sudo ./deploy.sh image
```

Zeigt Informationen über das lokale Ambientika Docker Image.

---

## Macvlan prüfen

```bash
sudo ./deploy.sh network
```

Prüft:

- Driver
- Subnetz
- Gateway
- Parent-Interface

Falls die Konfiguration nicht mit `.env` übereinstimmt, wird das Netzwerk nach Prüfung neu erstellt.

---

## Compose-Konfiguration anzeigen

```bash
sudo ./deploy.sh config
```

Zeigt die aufgelöste Docker-Compose-Konfiguration.

---

## Ambientika Logs

```bash
sudo ./deploy.sh logs
```

Zeigt die letzten Logs der Ambientika Bridge und folgt neuen Einträgen.

Beenden:

```text
CTRL + C
```

---

## Stack entfernen

```bash
sudo ./deploy.sh remove
```

Entfernt die Container des Compose-Stacks.

Die persistenten Datenverzeichnisse bleiben erhalten.

---

## Hilfe

```bash
./deploy.sh --help
```

---

# Dry-Run

## Globaler Dry-Run

```bash
sudo ./deploy.sh --dry-run
```

Zeigt die geplante Konfiguration und führt die Prüfungen durch.

## Start Dry-Run

```bash
sudo ./deploy.sh start --dry-run
```

## Update Dry-Run

```bash
sudo ./deploy.sh update --dry-run
```

## Netzwerk Dry-Run

```bash
sudo ./deploy.sh network --dry-run
```

---

# Docker-Dienste

Der Stack besteht aus vier Diensten.

```text
Docker Compose
│
├── matterbridge
│
├── portainer
│
├── mosquitto
│
└── ambientika-bridge
```

---

# Matterbridge

Matterbridge läuft in einem externen Macvlan.

Eigenschaften:

- eigene IP-Adresse im LAN
- keine Portweiterleitung über die Synology notwendig
- persistente Daten
- automatischer Neustart

Netzwerk:

```text
matter_net
    │
    └── externes Macvlan
```

---

# Portainer

Portainer läuft direkt auf dem Docker-Host mit Portweiterleitungen.

Standardmäßig:

```text
HTTP  -> Port 9000
HTTPS -> Port 9443
```

Die Ports können über `.env` geändert werden.

Portainer verwendet:

```text
/var/run/docker.sock
```

für die Verwaltung der Docker-Engine.

---

# Mosquitto MQTT

Mosquitto ist der zentrale MQTT Broker.

## Intern

```text
Ambientika Bridge
      │
      │ MQTT
      ▼
mosquitto:1883
```

## Extern

```text
Loxone
   │
   │ MQTT
   ▼
Synology-IP:1883
   │
   ▼
Mosquitto Container
```

Die Mosquitto-Konfiguration wird durch `deploy.sh` erstellt.

Die erzeugte Konfiguration enthält:

```text
listener 1883

allow_anonymous false

password_file /mosquitto/config/passwd

persistence true

persistence_location /mosquitto/data/

log_dest file /mosquitto/log/mosquitto.log
```

Der MQTT-Benutzer wird aus folgenden `.env` Variablen erstellt:

```env
MQTT_USER=...
MQTT_PASSWORD=...
```

---

# Ambientika MQTT Bridge

Die Ambientika Bridge wird nicht als fertiges Docker Image verwendet.

Stattdessen:

```text
Git Repository
      │
      ▼
Ambientika Source-Code
      │
      ▼
Docker Build
      │
      ▼
lokales Docker Image
      │
      ▼
Ambientika Bridge Container
```

Der Source-Code wird unter folgendem Pfad gespeichert:

```text
${AMBIENTIKA_DATA}/source
```

Das Repository wird beim ersten Start geklont.

Bei aktivierter Option:

```env
AMBIENTIKA_AUTO_UPDATE=true
```

wird das Repository bei der entsprechenden Deployment-Prüfung aktualisiert.

Das Skript erwartet im Source-Verzeichnis:

```text
Dockerfile
bridge.py
requirements.txt
```

---

# Radon-Schutz / NeuraCell-X

Der Bereich `neuracell` in `config.yaml` implementiert die Radon-Schutzlogik.

```yaml
neuracell:

  neuracell_enabled: true

  radon_topic: "ambientika/radon/value"

  radon_alarm_topic: "ambientika/radon/alarm"

  radon_threshold: 300

  radon_hysteresis: 50

  radon_protection_fan: "Low"

  radon_source: "signal"
```

Die vorgesehene Priorität ist:

```text
Radonalarm
    │
    ▼
alle Geräte
    │
    ▼
Intake / Zuluft
    │
    ▼
Fan Low / Stufe 1
```

Nach Ende des Alarms soll der vorherige Zustand wiederhergestellt werden.

## Radonquellen

### MQTT Signal

```yaml
radon_source: "signal"
```

Der Radonwert oder Alarm kommt über MQTT.

### Direktes Gerät

```yaml
radon_source: "device"
```

Die Bridge liest einen Ambientika-Radonsensor direkt aus der Ambientika Cloud.

Hierfür wird die Seriennummer benötigt:

```yaml
radon_device_serial: ""
```

---

## Radon-Hysterese

Beispiel:

```yaml
radon_threshold: 300
radon_hysteresis: 50
```

Logik:

```text
Alarm EIN:
>= 300 Bq/m³

Alarm AUS:
<= 250 Bq/m³
```

Dadurch wird ein ständiges Umschalten im Grenzbereich verhindert.

---

# Taupunktsteuerung

Die Taupunktsteuerung befindet sich im Bereich:

```yaml
dewpoint:
```

Beispiel:

```yaml
dewpoint:

  dewpoint_enabled: true

  dewpoint_source: "signal"

  dewpoint_block_topic: "ambientika/dewpoint/block"

  dewpoint_block_devices: ""
```

Die Taupunktsteuerung blockiert Lüftung bei ungünstigen Feuchtigkeitsbedingungen.

Die vorgesehene Priorität ist:

```text
Radonschutz
    │
    │ höchste Priorität
    ▼
Taupunktsteuerung
    │
    ▼
normale Lüftungssteuerung
```

---

## Taupunktquellen

### Signal

```yaml
dewpoint_source: "signal"
```

Ein externes MQTT-Signal blockiert die Lüftung.

### Computed

```yaml
dewpoint_source: "computed"
```

Der Taupunkt wird aus vier MQTT-Werten berechnet:

```text
Innentemperatur
Innenfeuchtigkeit
Außentemperatur
Außenfeuchtigkeit
```

Die entsprechenden Topics:

```yaml
dewpoint_indoor_temp_topic:
dewpoint_indoor_humidity_topic:

dewpoint_outdoor_temp_topic:
dewpoint_outdoor_humidity_topic:
```

### Device

```yaml
dewpoint_source: "device"
```

Die Taupunktinformation wird direkt aus einem Ambientika TPS-Gerät gelesen.

---

# Updates

## Vollständiges Update

Empfohlen:

```bash
sudo ./deploy.sh update
```

Dabei werden:

```text
Ambientika Repository
        │
        ▼
aktualisieren
        │
        ▼
Docker Images
        │
        ▼
aktualisieren
        │
        ▼
Ambientika Image
        │
        ▼
neu bauen
        │
        ▼
Container
        │
        ▼
neu erstellen
```

---

# Status und Logs

## Stack Status

```bash
sudo ./deploy.sh status
```

## Ambientika Logs

```bash
sudo ./deploy.sh logs
```

## Direkter Compose Status

```bash
docker compose \
  --env-file .env \
  -f compose.yml \
  -p matterbridge \
  ps
```

---

# Backup

Für ein Backup sollten mindestens die persistenten Datenverzeichnisse gesichert werden.

```text
MATTERBRIDGE_DATA

PORTAINER_DATA

MQTT_DATA

AMBIENTIKA_DATA
```

Besonders wichtig sind:

```text
Mosquitto/config/
Mosquitto/data/

Matterbridge Daten

Portainer Daten
```

Die Konfigurationsdateien des Projekts sollten ebenfalls gesichert werden:

```text
.env
compose.yml
config.yaml
deploy.sh
README.md
```

Die `.env` enthält Zugangsdaten und sollte nicht öffentlich in ein Git-Repository hochgeladen werden.

Empfohlene `.gitignore`:

```gitignore
.env
```

---

# Entfernen des Stacks

```bash
sudo ./deploy.sh remove
```

Das Skript fragt vor dem Entfernen nach einer Bestätigung.

Entfernt werden die Compose-Container.

Die persistenten Daten bleiben erhalten.

---

# Fehlerdiagnose

## Docker nicht gefunden

Prüfen:

```bash
docker --version
```

Der Docker-/Container-Manager muss installiert und der Docker-Daemon erreichbar sein.

---

## Git nicht gefunden

Prüfen:

```bash
git --version
```

Git wird für das Ambientika Repository benötigt.

---

## Script muss als root ausgeführt werden

Beispiel:

```bash
sudo ./deploy.sh
```

---

## Parent-Interface existiert nicht

Prüfen:

```bash
ip link
```

Anschließend:

```env
MACVLAN_PARENT=...
```

anpassen.

---

## Matterbridge-IP liegt nicht im Subnetz

Beispiel:

```env
MACVLAN_SUBNET=192.168.178.0/24
MATTERBRIDGE_IP=192.168.178.242
```

Die Matterbridge-IP muss zum Subnetz passen.

---

## Macvlan-Konfiguration ist falsch

Prüfen:

```bash
sudo ./deploy.sh network
```

Das Skript vergleicht:

```text
Driver
Subnetz
Gateway
Parent-Interface
```

mit den Werten aus `.env`.

---

## Ambientika Image fehlt

Prüfen:

```bash
sudo ./deploy.sh image
```

Erstellen:

```bash
sudo ./deploy.sh start
```

---

## Ambientika Bridge Logs

```bash
sudo ./deploy.sh logs
```

Für eine ausführlichere Diagnose kann der Log-Level in `config.yaml` auf `DEBUG` gesetzt werden:

```yaml
bridge:
  log_level: "DEBUG"
```

---

# Kurzreferenz

```bash
# Hilfe
./deploy.sh --help

# Prüfung ohne produktive Änderungen
sudo ./deploy.sh --dry-run

# Start
sudo ./deploy.sh start

# Stop
sudo ./deploy.sh stop

# Neustart
sudo ./deploy.sh restart

# Status
sudo ./deploy.sh status

# Update
sudo ./deploy.sh update

# Images herunterladen
sudo ./deploy.sh pull

# Ambientika Image prüfen
sudo ./deploy.sh image

# Macvlan prüfen
sudo ./deploy.sh network

# Compose-Konfiguration anzeigen
sudo ./deploy.sh config

# Ambientika Logs
sudo ./deploy.sh logs

# Stack entfernen
sudo ./deploy.sh remove
```

---

# Zusammenfassung

Die Projektstruktur trennt bewusst:

```text
.env
    │
    └── Infrastruktur / Zugangsdaten / Pfade

compose.yml
    │
    └── Docker Container / Netzwerke / Volumes

config.yaml
    │
    └── Funktion der Ambientika Bridge

deploy.sh
    │
    └── Installation / Prüfung / Update / Betrieb
```

Dadurch können Infrastruktur, Docker-Konfiguration und die eigentliche Funktionslogik unabhängig voneinander verwaltet werden.
