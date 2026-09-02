#!/bin/bash

# ============================================================
# deploy.sh
# ============================================================
#
# Matterbridge + Portainer + Mosquitto + Ambientika MQTT Bridge
#
# Dieses Script verwaltet:
#
#   - Docker Macvlan Netzwerk
#   - Matterbridge
#   - Portainer
#   - Mosquitto MQTT Broker
#   - Ambientika MQTT Bridge
#   - Ambientika Git Repository
#   - lokales Ambientika Docker Image
#   - Docker Compose Stack
#
# Konfiguration:
#
#   .env
#   config.yaml
#
#
# ============================================================
# VERWENDUNG
# ============================================================
#
#   ./deploy.sh
#   ./deploy.sh start
#   ./deploy.sh stop
#   ./deploy.sh restart
#   ./deploy.sh status
#   ./deploy.sh update
#   ./deploy.sh pull
#   ./deploy.sh network
#   ./deploy.sh config
#   ./deploy.sh image
#   ./deploy.sh logs
#   ./deploy.sh remove
#
#
# Dry-Run:
#
#   ./deploy.sh --dry-run
#   ./deploy.sh start --dry-run
#   ./deploy.sh update --dry-run
#   ./deploy.sh network --dry-run
#
# ============================================================


set -euo pipefail


# ============================================================
# FARBEN
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'


# ============================================================
# DATEIEN
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/.env"
COMPOSE_FILE="${SCRIPT_DIR}/compose.yml"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"


# ============================================================
# STANDARDWERTE
# ============================================================

DRY_RUN=false
COMMAND="start"


# ============================================================
# AUSGABEFUNKTIONEN
# ============================================================

info() {

    echo -e "${BLUE}[INFO]${NC} $1"

}


success() {

    echo -e "${GREEN}[ OK ]${NC} $1"

}


warning() {

    echo -e "${YELLOW}[WARNUNG]${NC} $1"

}


error() {

    echo -e "${RED}[FEHLER]${NC} $1" >&2

}


die() {

    error "$1"

    exit 1

}


# ============================================================
# HILFE
# ============================================================

show_help() {

    echo
    echo "============================================================"
    echo " Matterbridge / Portainer / MQTT / Ambientika"
    echo "============================================================"
    echo

    echo "Verwendung:"
    echo
    echo "  ./deploy.sh"
    echo "      Stack prüfen und starten"
    echo

    echo "Befehle:"
    echo
    echo "  start"
    echo "      Netzwerk, Image und Stack prüfen/starten"
    echo

    echo "  stop"
    echo "      Stack stoppen"
    echo

    echo "  restart"
    echo "      Stack neu starten"
    echo

    echo "  status"
    echo "      Container- und Netzwerkstatus"
    echo

    echo "  update"
    echo "      Repository aktualisieren, Image bauen und Stack aktualisieren"
    echo

    echo "  pull"
    echo "      Docker Images herunterladen"
    echo

    echo "  image"
    echo "      Status des Ambientika Images anzeigen"
    echo

    echo "  network"
    echo "      Macvlan prüfen und ggf. korrigieren"
    echo

    echo "  config"
    echo "      Aufgelöste Compose-Konfiguration anzeigen"
    echo

    echo "  logs"
    echo "      Ambientika Bridge Logs anzeigen"
    echo

    echo "  remove"
    echo "      Compose Stack entfernen"
    echo

    echo "Dry-Run:"
    echo
    echo "  ./deploy.sh --dry-run"
    echo "  ./deploy.sh start --dry-run"
    echo "  ./deploy.sh update --dry-run"
    echo "  ./deploy.sh network --dry-run"
    echo

}


# ============================================================
# ARGUMENTE
# ============================================================

parse_arguments() {

    for ARG in "$@"; do

        case "${ARG}" in

            --dry-run)

                DRY_RUN=true

                ;;

            start)

                COMMAND="start"

                ;;

            stop)

                COMMAND="stop"

                ;;

            restart)

                COMMAND="restart"

                ;;

            status)

                COMMAND="status"

                ;;

            update)

                COMMAND="update"

                ;;

            pull)

                COMMAND="pull"

                ;;

            image)

                COMMAND="image"

                ;;

            network)

                COMMAND="network"

                ;;

            config)

                COMMAND="config"

                ;;

            logs)

                COMMAND="logs"

                ;;

            remove)

                COMMAND="remove"

                ;;

            -h|--help)

                show_help

                exit 0

                ;;

            *)

                die "Unbekanntes Argument: ${ARG}"

                ;;

        esac

    done

}


# ============================================================
# ROOT PRÜFEN
# ============================================================

check_root() {

    if [[ "${EUID}" -ne 0 ]]; then

        die "Dieses Script muss als root ausgeführt werden."

    fi

}


# ============================================================
# DOCKER PRÜFEN
# ============================================================

check_docker() {

    if ! command -v docker >/dev/null 2>&1; then

        die "Docker wurde nicht gefunden."

    fi


    if ! docker info >/dev/null 2>&1; then

        die "Docker Daemon ist nicht erreichbar."

    fi


    success "Docker ist verfügbar."

}


# ============================================================
# GIT PRÜFEN
# ============================================================

check_git() {

    if ! command -v git >/dev/null 2>&1; then

        die "Git wurde nicht gefunden.

Git wird benötigt, um die Ambientika MQTT Bridge
aus dem offiziellen Repository zu laden."

    fi


    success "Git ist verfügbar."

}


# ============================================================
# DATEIEN PRÜFEN
# ============================================================

check_files() {

    [[ -f "${ENV_FILE}" ]] \
        || die ".env wurde nicht gefunden:
${ENV_FILE}"


    [[ -f "${COMPOSE_FILE}" ]] \
        || die "compose.yml wurde nicht gefunden:
${COMPOSE_FILE}"


    [[ -f "${CONFIG_FILE}" ]] \
        || die "config.yaml wurde nicht gefunden:
${CONFIG_FILE}"


    success "Konfigurationsdateien gefunden."

}


# ============================================================
# ENV EINLESEN
# ============================================================

load_env() {

    info "Lese .env ein..."


    set -a

    # shellcheck disable=SC1090
    source "${ENV_FILE}"

    set +a


    success ".env geladen."

}


# ============================================================
# ERFORDERLICHE VARIABLEN
# ============================================================

check_variables() {

    local REQUIRED_VARS=(

        TZ

        MACVLAN_NETWORK
        MACVLAN_PARENT
        MACVLAN_SUBNET
        MACVLAN_GATEWAY

        MATTERBRIDGE_IP
        MATTERBRIDGE_DATA

        PORTAINER_DATA
        PORTAINER_HTTP_PORT
        PORTAINER_HTTPS_PORT

        MQTT_DATA
        MQTT_PORT
        MQTT_USER
        MQTT_PASSWORD

        AMBIENTIKA_DATA
        AMBIENTIKA_REPOSITORY
        AMBIENTIKA_BRANCH
        AMBIENTIKA_IMAGE

        AMBIENTIKA_USER
        AMBIENTIKA_PASS

        MQTT_HOST

    )


    for VAR in "${REQUIRED_VARS[@]}"; do

        if [[ -z "${!VAR:-}" ]]; then

            die "Variable '${VAR}' fehlt in der .env."

        fi

    done


    success "Alle benötigten Variablen vorhanden."

}


# ============================================================
# IPv4 VALIDIERUNG
# ============================================================

valid_ipv4() {

    local IP="$1"


    if [[ ! "${IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then

        return 1

    fi


    IFS='.' read -r A B C D <<< "${IP}"


    for OCTET in "${A}" "${B}" "${C}" "${D}"; do

        if (( OCTET < 0 || OCTET > 255 )); then

            return 1

        fi

    done


    return 0

}


# ============================================================
# CIDR VALIDIERUNG
# ============================================================

valid_cidr() {

    local CIDR="$1"

    local IP
    local PREFIX


    if [[ ! "${CIDR}" =~ ^([^/]+)/([0-9]{1,2})$ ]]; then

        return 1

    fi


    IP="${BASH_REMATCH[1]}"
    PREFIX="${BASH_REMATCH[2]}"


    valid_ipv4 "${IP}" || return 1


    if (( PREFIX < 0 || PREFIX > 32 )); then

        return 1

    fi


    return 0

}


# ============================================================
# IPv4 -> INTEGER
# ============================================================

ip_to_int() {

    local IP="$1"


    IFS='.' read -r A B C D <<< "${IP}"


    echo $((
        (A << 24) +
        (B << 16) +
        (C << 8) +
        D
    ))

}


# ============================================================
# IP IM SUBNETZ?
# ============================================================

ip_in_subnet() {

    local IP="$1"
    local CIDR="$2"

    local NETWORK_IP
    local PREFIX


    IFS='/' read -r NETWORK_IP PREFIX <<< "${CIDR}"


    local IP_INT
    local NETWORK_INT
    local MASK


    IP_INT=$(ip_to_int "${IP}")

    NETWORK_INT=$(ip_to_int "${NETWORK_IP}")


    if (( PREFIX == 0 )); then

        MASK=0

    else

        MASK=$(
            (
                (0xFFFFFFFF << (32 - PREFIX)) &
                0xFFFFFFFF
            )
        )

    fi


    if (( (IP_INT & MASK) == (NETWORK_INT & MASK) )); then

        return 0

    fi


    return 1

}


# ============================================================
# IP-KONFIGURATION PRÜFEN
# ============================================================

validate_ip_configuration() {

    info "Prüfe IP-Konfiguration..."


    if ! valid_cidr "${MACVLAN_SUBNET}"; then

        die "Ungültiges MACVLAN_SUBNET:
${MACVLAN_SUBNET}"

    fi


    if ! valid_ipv4 "${MACVLAN_GATEWAY}"; then

        die "Ungültiges MACVLAN_GATEWAY:
${MACVLAN_GATEWAY}"

    fi


    if ! valid_ipv4 "${MATTERBRIDGE_IP}"; then

        die "Ungültige MATTERBRIDGE_IP:
${MATTERBRIDGE_IP}"

    fi


    if ! ip_in_subnet \
        "${MATTERBRIDGE_IP}" \
        "${MACVLAN_SUBNET}"; then

        die "MATTERBRIDGE_IP liegt nicht im MACVLAN_SUBNET."

    fi


    if ! ip_in_subnet \
        "${MACVLAN_GATEWAY}" \
        "${MACVLAN_SUBNET}"; then

        die "MACVLAN_GATEWAY liegt nicht im MACVLAN_SUBNET."

    fi


    success "IP-Konfiguration ist korrekt."

}


# ============================================================
# PARENT INTERFACE
# ============================================================

check_parent_interface() {

    info "Prüfe Parent-Interface '${MACVLAN_PARENT}'..."


    if ! ip link show "${MACVLAN_PARENT}" >/dev/null 2>&1; then

        die "Netzwerkinterface '${MACVLAN_PARENT}' existiert nicht."

    fi


    success "Parent-Interface vorhanden."

}


# ============================================================
# VERZEICHNISSE ERSTELLEN
# ============================================================

create_directories() {

    info "Prüfe Datenverzeichnisse..."


    # --------------------------------------------------------
    # Matterbridge
    # --------------------------------------------------------

    mkdir -p "${MATTERBRIDGE_DATA}"


    # --------------------------------------------------------
    # Portainer
    # --------------------------------------------------------

    mkdir -p "${PORTAINER_DATA}"


    # --------------------------------------------------------
    # Mosquitto
    # --------------------------------------------------------

    mkdir -p "${MQTT_DATA}/config"
    mkdir -p "${MQTT_DATA}/data"
    mkdir -p "${MQTT_DATA}/log"


    # --------------------------------------------------------
    # Ambientika
    # --------------------------------------------------------

    mkdir -p "${AMBIENTIKA_DATA}"


    success "Datenverzeichnisse vorhanden."

}


# ============================================================
# MOSQUITTO KONFIGURATION
# ============================================================

configure_mosquitto() {

    local CONFIG_DIR="${MQTT_DATA}/config"
    local CONFIG_FILE="${CONFIG_DIR}/mosquitto.conf"
    local PASSWD_FILE="${CONFIG_DIR}/passwd"


    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Mosquitto-Konfiguration würde erstellt."

        return 0

    fi


    # --------------------------------------------------------
    # Mosquitto Konfiguration
    # --------------------------------------------------------

    if [[ ! -f "${CONFIG_FILE}" ]]; then

        info "Erstelle Mosquitto-Konfiguration..."


        cat > "${CONFIG_FILE}" <<EOF
# ============================================================
# Eclipse Mosquitto
# ============================================================

# MQTT Listener
listener 1883

# Keine anonymen Verbindungen
allow_anonymous false

# Benutzer-/Passwortdatei
password_file /mosquitto/config/passwd

# Persistente MQTT-Daten
persistence true
persistence_location /mosquitto/data/

# Logdatei
log_dest file /mosquitto/log/mosquitto.log
EOF


        success "Mosquitto-Konfiguration erstellt."

    fi


    # --------------------------------------------------------
    # MQTT Benutzer anlegen/aktualisieren
    # --------------------------------------------------------

    info "Konfiguriere MQTT-Benutzer '${MQTT_USER}'..."


    docker run --rm \
        -v "${CONFIG_DIR}:/mosquitto/config" \
        eclipse-mosquitto:2 \
        mosquitto_passwd \
        -b \
        -c \
        /mosquitto/config/passwd \
        "${MQTT_USER}" \
        "${MQTT_PASSWORD}"


    chmod 600 "${PASSWD_FILE}"


    success "MQTT-Benutzer wurde eingerichtet."

}


# ============================================================
# AMBIENTIKA SOURCE REPOSITORY
# ============================================================

prepare_ambientika_source() {

    local SOURCE_DIR="${AMBIENTIKA_DATA}/source"


    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Ambientika Repository würde geprüft."

        echo
        echo "Repository:"
        echo "  ${AMBIENTIKA_REPOSITORY}"
        echo

        echo "Branch:"
        echo "  ${AMBIENTIKA_BRANCH}"
        echo

        echo "Ziel:"
        echo "  ${SOURCE_DIR}"
        echo

        return 0

    fi


    # --------------------------------------------------------
    # Repository existiert noch nicht
    # --------------------------------------------------------

    if [[ ! -d "${SOURCE_DIR}/.git" ]]; then

        info "Ambientika MQTT Bridge Repository nicht vorhanden."

        info "Klone offizielles Repository..."


        rm -rf "${SOURCE_DIR}"


        git clone \
            --branch "${AMBIENTIKA_BRANCH}" \
            --depth 1 \
            "${AMBIENTIKA_REPOSITORY}" \
            "${SOURCE_DIR}"


        success "Ambientika Repository wurde geklont."

        return 0

    fi


    # --------------------------------------------------------
    # Repository existiert
    # --------------------------------------------------------

    if [[ "${AMBIENTIKA_AUTO_UPDATE}" != "true" ]]; then

        info "Automatische Repository-Aktualisierung deaktiviert."

        return 0

    fi


    info "Aktualisiere Ambientika Repository..."


    git -C "${SOURCE_DIR}" fetch \
        --depth 1 \
        origin \
        "${AMBIENTIKA_BRANCH}"


    git -C "${SOURCE_DIR}" reset \
        --hard \
        "origin/${AMBIENTIKA_BRANCH}"


    success "Ambientika Repository wurde aktualisiert."

}


# ============================================================
# AMBIENTIKA SOURCE PRÜFEN
# ============================================================

check_ambientika_source() {

    local SOURCE_DIR="${AMBIENTIKA_DATA}/source"


    [[ -f "${SOURCE_DIR}/Dockerfile" ]] \
        || die "Ambientika Dockerfile fehlt:
${SOURCE_DIR}/Dockerfile"


    [[ -f "${SOURCE_DIR}/bridge.py" ]] \
        || die "Ambientika bridge.py fehlt:
${SOURCE_DIR}/bridge.py"


    [[ -f "${SOURCE_DIR}/requirements.txt" ]] \
        || die "Ambientika requirements.txt fehlt:
${SOURCE_DIR}/requirements.txt"


    success "Ambientika Source-Code ist vollständig."

}


# ============================================================
# AMBIENTIKA IMAGE PRÜFEN
# ============================================================

ambientika_image_exists() {

    docker image inspect \
        "${AMBIENTIKA_IMAGE}" >/dev/null 2>&1

}


# ============================================================
# AMBIENTIKA IMAGE BAUEN
# ============================================================

build_ambientika_image() {

    local SOURCE_DIR="${AMBIENTIKA_DATA}/source"


    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Ambientika Docker Image würde gebaut."

        echo
        echo "docker compose build ambientika-bridge"
        echo

        return 0

    fi


    info "Prüfe Ambientika Docker Image..."


    if ambientika_image_exists; then

        success "Ambientika Image existiert bereits:"
        echo "  ${AMBIENTIKA_IMAGE}"

    else

        warning "Ambientika Image existiert noch nicht."

    fi


    info "Baue Ambientika MQTT Bridge..."


    compose build \
        --pull \
        ambientika-bridge


    success "Ambientika MQTT Bridge Image wurde gebaut."

}


# ============================================================
# MACVLAN ERSTELLEN
# ============================================================

create_macvlan() {

    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Macvlan würde erstellt werden."

        echo
        echo "docker network create \\"
        echo "  --driver macvlan \\"
        echo "  --subnet=${MACVLAN_SUBNET} \\"
        echo "  --gateway=${MACVLAN_GATEWAY} \\"
        echo "  --opt parent=${MACVLAN_PARENT} \\"
        echo "  ${MACVLAN_NETWORK}"
        echo

        return 0

    fi


    info "Erstelle Macvlan '${MACVLAN_NETWORK}'..."


    docker network create \
        --driver macvlan \
        --subnet="${MACVLAN_SUBNET}" \
        --gateway="${MACVLAN_GATEWAY}" \
        --opt parent="${MACVLAN_PARENT}" \
        "${MACVLAN_NETWORK}"


    success "Macvlan wurde erstellt."

}


# ============================================================
# VERWENDETE CONTAINER DES MACVLANS
# ============================================================

get_macvlan_containers() {

    docker network inspect \
        "${MACVLAN_NETWORK}" \
        --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}'

}


# ============================================================
# STACK STOPPEN
# ============================================================

stop_stack_for_network_change() {

    info "Stoppe Compose Stack..."


    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Stack würde gestoppt werden."

        return 0

    fi


    if compose ps -q >/dev/null 2>&1; then

        compose down

    fi


    success "Compose Stack wurde gestoppt."

}


# ============================================================
# MACVLAN LÖSCHEN
# ============================================================

remove_macvlan() {

    info "Entferne altes Macvlan..."


    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Macvlan würde entfernt werden."

        return 0

    fi


    docker network rm \
        "${MACVLAN_NETWORK}"


    success "Altes Macvlan wurde entfernt."

}


# ============================================================
# MACVLAN PRÜFEN
# ============================================================

check_macvlan() {

    echo
    echo "============================================================"
    echo " MACVLAN PRÜFUNG"
    echo "============================================================"
    echo


    validate_ip_configuration

    check_parent_interface


    # --------------------------------------------------------
    # Netzwerk existiert nicht
    # --------------------------------------------------------

    if ! docker network inspect \
        "${MACVLAN_NETWORK}" >/dev/null 2>&1; then

        warning "Macvlan '${MACVLAN_NETWORK}' existiert nicht."

        create_macvlan

        return 0

    fi


    # --------------------------------------------------------
    # Aktuelle Konfiguration
    # --------------------------------------------------------

    local CURRENT_DRIVER
    local CURRENT_SUBNET
    local CURRENT_GATEWAY
    local CURRENT_PARENT


    CURRENT_DRIVER=$(
        docker network inspect "${MACVLAN_NETWORK}" \
            --format '{{.Driver}}'
    )


    CURRENT_SUBNET=$(
        docker network inspect "${MACVLAN_NETWORK}" \
            --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
    )


    CURRENT_GATEWAY=$(
        docker network inspect "${MACVLAN_NETWORK}" \
            --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
    )


    CURRENT_PARENT=$(
        docker network inspect "${MACVLAN_NETWORK}" \
            --format '{{index .Options "parent"}}'
    )


    echo
    echo "Aktuelle Konfiguration:"
    echo
    echo "  Netzwerk : ${MACVLAN_NETWORK}"
    echo "  Driver   : ${CURRENT_DRIVER}"
    echo "  Subnetz  : ${CURRENT_SUBNET}"
    echo "  Gateway  : ${CURRENT_GATEWAY}"
    echo "  Parent   : ${CURRENT_PARENT}"
    echo


    # --------------------------------------------------------
    # Unterschiede
    # --------------------------------------------------------

    local NEEDS_RECREATE=false


    if [[ "${CURRENT_DRIVER}" != "macvlan" ]]; then

        warning "Driver stimmt nicht."

        NEEDS_RECREATE=true

    fi


    if [[ "${CURRENT_SUBNET}" != "${MACVLAN_SUBNET}" ]]; then

        warning "Subnetz stimmt nicht."

        NEEDS_RECREATE=true

    fi


    if [[ "${CURRENT_GATEWAY}" != "${MACVLAN_GATEWAY}" ]]; then

        warning "Gateway stimmt nicht."

        NEEDS_RECREATE=true

    fi


    if [[ "${CURRENT_PARENT}" != "${MACVLAN_PARENT}" ]]; then

        warning "Parent-Interface stimmt nicht."

        NEEDS_RECREATE=true

    fi


    # --------------------------------------------------------
    # Alles korrekt
    # --------------------------------------------------------

    if [[ "${NEEDS_RECREATE}" == "false" ]]; then

        success "Macvlan ist korrekt konfiguriert."

        return 0

    fi


    # --------------------------------------------------------
    # Dry-Run
    # --------------------------------------------------------

    if [[ "${DRY_RUN}" == "true" ]]; then

        warning "DRY-RUN: Macvlan müsste geändert werden."

        return 0

    fi


    # --------------------------------------------------------
    # Container prüfen
    # --------------------------------------------------------

    local CONTAINERS

    CONTAINERS=$(get_macvlan_containers)


    if [[ -n "${CONTAINERS}" ]]; then

        warning "Folgende Container verwenden das Macvlan:"
        echo
        echo "${CONTAINERS}"
        echo

    fi


    # --------------------------------------------------------
    # Stack stoppen
    # --------------------------------------------------------

    stop_stack_for_network_change


    # --------------------------------------------------------
    # Prüfen, ob Netzwerk frei ist
    # --------------------------------------------------------

    if docker network inspect \
        "${MACVLAN_NETWORK}" >/dev/null 2>&1; then

        CONTAINERS=$(get_macvlan_containers)


        if [[ -n "${CONTAINERS}" ]]; then

            die "Macvlan wird weiterhin von Containern verwendet."

        fi

    fi


    # --------------------------------------------------------
    # Netzwerk entfernen
    # --------------------------------------------------------

    remove_macvlan


    # --------------------------------------------------------
    # Netzwerk neu erstellen
    # --------------------------------------------------------

    create_macvlan


    success "Macvlan wurde aktualisiert."

}


# ============================================================
# COMPOSE WRAPPER
# ============================================================

compose() {

    docker compose \
        --env-file "${ENV_FILE}" \
        -f "${COMPOSE_FILE}" \
        -p "${COMPOSE_PROJECT_NAME}" \
        "$@"

}


# ============================================================
# COMPOSE KONFIGURATION PRÜFEN
# ============================================================

check_compose() {

    info "Prüfe Compose-Konfiguration..."


    compose config >/dev/null


    success "Compose-Konfiguration ist gültig."

}


# ============================================================
# START
# ============================================================

start_stack() {

    echo
    echo "============================================================"
    echo " START"
    echo "============================================================"
    echo


    validate_ip_configuration

    create_directories

    configure_mosquitto

    prepare_ambientika_source

    check_ambientika_source

    check_macvlan

    check_compose


    # --------------------------------------------------------
    # Ambientika Image fehlt?
    # --------------------------------------------------------

    if ! ambientika_image_exists; then

        build_ambientika_image

    fi


    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Stack würde gestartet werden."

        return 0

    fi


    info "Starte Compose Stack..."


    compose up -d


    success "Matterbridge + Portainer + Mosquitto + Ambientika Bridge wurden gestartet."

}


# ============================================================
# STOP
# ============================================================

stop_stack() {

    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Stack würde gestoppt werden."

        return 0

    fi


    info "Stoppe Stack..."


    compose stop


    success "Stack gestoppt."

}


# ============================================================
# RESTART
# ============================================================

restart_stack() {

    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Stack würde neu gestartet werden."

        return 0

    fi


    info "Starte Stack neu..."


    compose restart


    success "Stack neu gestartet."

}


# ============================================================
# PULL
# ============================================================

pull_images() {

    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Docker Images würden heruntergeladen."

        return 0

    fi


    info "Lade Docker Images..."


    compose pull


    success "Docker Images wurden heruntergeladen."

}


# ============================================================
# UPDATE
# ============================================================

update_stack() {

    echo
    echo "============================================================"
    echo " UPDATE"
    echo "============================================================"
    echo


    validate_ip_configuration

    create_directories

    configure_mosquitto

    prepare_ambientika_source

    check_ambientika_source

    check_macvlan

    check_compose


    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Ambientika Image würde neu gebaut."

        info "Dry-Run: Container würden anschließend aktualisiert."

        return 0

    fi


    # --------------------------------------------------------
    # Alle normalen Images aktualisieren
    # --------------------------------------------------------

    info "Lade Docker Images..."


    compose pull \
        matterbridge \
        portainer \
        mosquitto


    # --------------------------------------------------------
    # Ambientika Image neu bauen
    #
    # Dadurch wird der aktuelle Git-Stand in das Image
    # übernommen.
    # --------------------------------------------------------

    build_ambientika_image


    # --------------------------------------------------------
    # Container aktualisieren
    # --------------------------------------------------------

    info "Aktualisiere Container..."


    compose up -d \
        --force-recreate


    success "Update abgeschlossen."

}


# ============================================================
# STATUS
# ============================================================

show_status() {

    echo
    echo "============================================================"
    echo " CONTAINER STATUS"
    echo "============================================================"
    echo


    compose ps


    echo
    echo "============================================================"
    echo " AMBIENTIKA IMAGE"
    echo "============================================================"
    echo


    if ambientika_image_exists; then

        docker image inspect \
            "${AMBIENTIKA_IMAGE}" \
            --format '
Repository: {{.RepoTags}}
ID:         {{.Id}}
Created:    {{.Created}}
Size:       {{.Size}}
'

    else

        warning "Ambientika Image existiert nicht."

    fi


    echo
    echo "============================================================"
    echo " MACVLAN STATUS"
    echo "============================================================"
    echo


    if docker network inspect \
        "${MACVLAN_NETWORK}" >/dev/null 2>&1; then


        docker network inspect \
            "${MACVLAN_NETWORK}" \
            --format '
Name:    {{.Name}}
Driver:  {{.Driver}}
Subnet:  {{range .IPAM.Config}}{{.Subnet}}{{end}}
Gateway: {{range .IPAM.Config}}{{.Gateway}}{{end}}
Parent:  {{index .Options "parent"}}
'


        echo
        echo "Verbundene Container:"
        echo


        docker network inspect \
            "${MACVLAN_NETWORK}" \
            --format \
            '{{range .Containers}}  {{.Name}} -> {{.IPv4Address}}{{"\n"}}{{end}}'


    else

        warning "Macvlan '${MACVLAN_NETWORK}' existiert nicht."

    fi


    echo
    echo "============================================================"
    echo " MQTT STATUS"
    echo "============================================================"
    echo


    if docker network inspect \
        "${COMPOSE_PROJECT_NAME}_mqtt_net" >/dev/null 2>&1; then

        docker network inspect \
            "${COMPOSE_PROJECT_NAME}_mqtt_net" \
            --format \
            '{{range .Containers}}  {{.Name}}{{"\n"}}{{end}}'

    else

        warning "MQTT Docker-Netzwerk existiert nicht."

    fi

}


# ============================================================
# IMAGE
# ============================================================

show_image_status() {

    echo
    echo "============================================================"
    echo " AMBIENTIKA IMAGE"
    echo "============================================================"
    echo


    if ! ambientika_image_exists; then

        warning "Image '${AMBIENTIKA_IMAGE}' existiert nicht."

        echo
        echo "Zum Erstellen:"
        echo
        echo "  ./deploy.sh start"
        echo
        return 0

    fi


    docker image inspect \
        "${AMBIENTIKA_IMAGE}" \
        --format '
Repository: {{.RepoTags}}
ID:         {{.Id}}
Created:    {{.Created}}
Size:       {{.Size}}
'


    echo
    success "Ambientika Image ist vorhanden."
    echo

}


# ============================================================
# LOGS
# ============================================================

show_logs() {

    compose logs \
        -f \
        --tail=200 \
        ambientika-bridge

}


# ============================================================
# CONFIG
# ============================================================

show_compose_config() {

    check_compose

    compose config

}


# ============================================================
# REMOVE
# ============================================================

remove_stack() {

    if [[ "${DRY_RUN}" == "true" ]]; then

        info "Dry-Run: Stack würde entfernt werden."

        return 0

    fi


    warning "Die Container des Compose Stacks werden entfernt."

    echo
    echo "Die Datenverzeichnisse bleiben erhalten:"
    echo
    echo "  ${MATTERBRIDGE_DATA}"
    echo "  ${PORTAINER_DATA}"
    echo "  ${MQTT_DATA}"
    echo "  ${AMBIENTIKA_DATA}"
    echo


    read -r -p \
        "Fortfahren? [j/N]: " ANSWER


    if [[ ! "${ANSWER}" =~ ^[JjYy]$ ]]; then

        info "Abgebrochen."

        return 0

    fi


    compose down


    success "Compose Stack wurde entfernt."

}


# ============================================================
# GLOBALER DRY-RUN
# ============================================================

run_global_dry_run() {

    echo
    echo "============================================================"
    echo " DRY RUN"
    echo "============================================================"
    echo


    echo "Macvlan:"
    echo "  Netzwerk : ${MACVLAN_NETWORK}"
    echo "  Parent   : ${MACVLAN_PARENT}"
    echo "  Subnetz  : ${MACVLAN_SUBNET}"
    echo "  Gateway  : ${MACVLAN_GATEWAY}"
    echo


    echo "Matterbridge:"
    echo "  IP       : ${MATTERBRIDGE_IP}"
    echo "  Daten    : ${MATTERBRIDGE_DATA}"
    echo


    echo "Portainer:"
    echo "  Daten    : ${PORTAINER_DATA}"
    echo "  HTTP     : ${PORTAINER_HTTP_PORT}"
    echo "  HTTPS    : ${PORTAINER_HTTPS_PORT}"
    echo


    echo "Mosquitto:"
    echo "  Daten    : ${MQTT_DATA}"
    echo "  Port     : ${MQTT_PORT}"
    echo "  Benutzer : ${MQTT_USER}"
    echo


    echo "Ambientika:"
    echo "  Daten    : ${AMBIENTIKA_DATA}"
    echo "  Repository:"
    echo "    ${AMBIENTIKA_REPOSITORY}"
    echo "  Branch   : ${AMBIENTIKA_BRANCH}"
    echo "  Image    : ${AMBIENTIKA_IMAGE}"
    echo


    validate_ip_configuration

    check_parent_interface

    create_directories

    configure_mosquitto

    prepare_ambientika_source

    check_ambientika_source

    check_macvlan

    check_compose


    echo
    success "Dry-Run abgeschlossen."
    echo
    info "Es wurden keine Container gestartet oder gestoppt."
    echo

}


# ============================================================
# HAUPTPROGRAMM
# ============================================================

main() {

    parse_arguments "$@"


    # --------------------------------------------------------
    # Grundlegende Prüfungen
    # --------------------------------------------------------

    check_root

    check_files

    check_docker

    load_env

    check_variables


    # --------------------------------------------------------
    # Globaler Dry-Run
    # --------------------------------------------------------

    if [[ "${DRY_RUN}" == "true" && "$#" -eq 1 ]]; then

        check_git

        run_global_dry_run

        exit 0

    fi


    # --------------------------------------------------------
    # Git nur für Ambientika-relevante Operationen
    # --------------------------------------------------------

    case "${COMMAND}" in

        start|update|image)

            check_git

            ;;

    esac


    # --------------------------------------------------------
    # Befehl ausführen
    # --------------------------------------------------------

    case "${COMMAND}" in

        start)

            start_stack

            ;;

        stop)

            stop_stack

            ;;

        restart)

            restart_stack

            ;;

        status)

            show_status

            ;;

        update)

            update_stack

            ;;

        pull)

            check_compose

            pull_images

            ;;

        image)

            show_image_status

            ;;

        network)

            check_macvlan

            ;;

        config)

            show_compose_config

            ;;

        logs)

            show_logs

            ;;

        remove)

            remove_stack

            ;;

        *)

            die "Unbekannter Befehl: ${COMMAND}"

            ;;

    esac

}


# ============================================================
# SCRIPT STARTEN
# ============================================================

main "$@"
