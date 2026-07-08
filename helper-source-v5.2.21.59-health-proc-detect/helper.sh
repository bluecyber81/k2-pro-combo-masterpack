#!/bin/sh
# Creality K2 Pro Combo Helper Script - health proc detect v5.2.21.59 - firmware aware
# Based on sw3defy K2 Plus helper; adapted with K2 Pro Combo guards.

SCRIPT_DIR=/mnt/UDISK/helper-script
SCRIPTS_DIR=$SCRIPT_DIR/scripts
FILES_DIR=$SCRIPT_DIR/files
PRINTER_DATA=/mnt/UDISK/printer_data
CONFIG_DIR=$PRINTER_DATA/config
LOGS_DIR=$PRINTER_DATA/logs

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; WHITE='\033[1;37m'; BLUE='\033[1;34m'; NC='\033[0m'
PRINTER_COMPAT_OK=0

print_header() {
    clear
    echo ""
    printf "%b\n" "${WHITE}======================================================${NC}"
    printf "%b\n" "${WHITE}   Creality K2 Pro Combo Helper - v5.2.21.59-health-proc-detect${NC}"
    printf "%b\n" "${WHITE}======================================================${NC}"
    printf "%b\n" "${CYAN}   Normal layout: Status | Install | Wartung | Spoolman${NC}"
    printf "%b\n" "${WHITE}======================================================${NC}"
    echo ""
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        printf "%b\n" "${RED}ERROR: This script must be run as root.${NC}"
        exit 1
    fi
}

check_printer() {
    if [ ! -f "$CONFIG_DIR/printer.cfg" ]; then
        printf "%b\n" "${RED}ERROR: printer.cfg not found at $CONFIG_DIR/printer.cfg${NC}"
        exit 1
    fi

    MODEL="$(/usr/bin/get_sn_mac.sh model 2>/dev/null)"
    BOARD="$(/usr/bin/get_sn_mac.sh board 2>/dev/null)"
    FW_VERSION="$(fw_printenv version 2>/dev/null | cut -d= -f2)"

    printf "%b\n" "${CYAN}Detected:${NC} model=${MODEL:-unknown} board=${BOARD:-unknown} firmware=${FW_VERSION:-unknown}"
    compat_ok=1

    # From CR0CN200400C10 V1.1.5.5 firmware: F012=K2Pro, F008=K2Plus.
    if [ "x$MODEL" != "xF012" ]; then
        printf "%b\n" "${YELLOW}WARN: Firmware mapping says K2 Pro should report model F012.${NC}"
        printf "%b\n" "${YELLOW}      Your printer reports model '${MODEL:-unknown}'. Run option 1 before installing anything.${NC}"
        compat_ok=0
    fi
    if [ "x$BOARD" != "xCR0CN200400C10" ]; then
        printf "%b\n" "${YELLOW}WARN: Expected K2 Pro board CR0CN200400C10, got '${BOARD:-unknown}'.${NC}"
        compat_ok=0
    fi

    if grep -RqsE "Printer_size:[[:space:]]*300[\*x]300[\*x]300" "$CONFIG_DIR/printer.cfg" "$CONFIG_DIR/printer_params.cfg" 2>/dev/null; then
        :
    else
        printf "%b\n" "${YELLOW}WARN: K2 Pro 300*300*300 was not detected in printer.cfg/printer_params.cfg.${NC}"
        printf "%b\n" "${YELLOW}      Run option 1 and review the report before installing anything.${NC}"
        compat_ok=0
    fi

    PRINTER_COMPAT_OK=$compat_ok
    if [ "$PRINTER_COMPAT_OK" != "1" ]; then
        printf "%b\n" "${RED}Install options are blocked until K2 Pro model, board, and 300x300x300 size are confirmed.${NC}"
        printf "%b\n" "${YELLOW}Safe actions remain available: Preflight, Backup, Restore/Remove, Restart, Logs.${NC}"
    fi
}

confirm_install() {
    echo ""
    printf "  This will install %s. Continue? [y/n]: " "$1"
    read confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]
}

confirm_action() {
    echo ""
    printf "  %s Continue? [y/n]: " "$1"
    read confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]
}

is_feature_marked() {
    feature="$1"
    [ -f "$SCRIPT_DIR/.installed" ] && grep -q "^$feature$" "$SCRIPT_DIR/.installed"
}

EXPERT_UNLOCK_FILE=$SCRIPT_DIR/.expert_unlock_k2pro
EXPERT_PHRASE="ICH VERSTEHE K2 PRO RISIKO"

not_use_notice() {
    echo ""
    printf "%b\n" "${RED}NICHT BENUTZEN / GESPERRT für K2 Pro Combo:${NC} $1"
    echo "Das Modul bleibt im Paket, damit nichts fehlt, wird aber normal NICHT gestartet."
    echo "Grund: Es kann K2-Pro-Bewegung, Leveling, CFS/BOX-Verhalten, Display oder gespeicherte Offsets beschädigen."
    echo ""
    printf "%b\n" "${YELLOW}Expert-Test ist nur möglich, wenn diese Datei existiert:${NC} $EXPERT_UNLOCK_FILE"
    echo "Unlock-Datei erstellen: touch $EXPERT_UNLOCK_FILE"
    echo "Unlock wieder sperren: rm -f $EXPERT_UNLOCK_FILE"
    return 0
}

expert_status() {
    echo ""
    printf "%b\n" "${WHITE}Expert-Unlock Status${NC}"
    if [ -f "$EXPERT_UNLOCK_FILE" ]; then
        printf "%b\n" "${RED}AKTIV:${NC} $EXPERT_UNLOCK_FILE existiert. Risiko-Module können nach Zusatzabfrage gestartet werden."
    else
        printf "%b\n" "${GREEN}GESPERRT:${NC} Risiko-Module werden nicht gestartet."
    fi
    echo ""
    echo "Zum bewussten Testen nach Backup:"
    echo "  touch $EXPERT_UNLOCK_FILE"
    echo "Zum wieder Sperren:"
    echo "  rm -f $EXPERT_UNLOCK_FILE"
    echo ""
    echo "Vor jedem Risiko-Modul musst du zusätzlich exakt schreiben:"
    echo "  $EXPERT_PHRASE"
}

has_backup() {
    ls /mnt/UDISK/printer_data/backups/k2pro_helper/*.tar.gz >/dev/null 2>&1
}

require_k2pro_compatible() {
    if [ "$PRINTER_COMPAT_OK" != "1" ]; then
        echo ""
        printf "%b\n" "${RED}ABBRUCH:${NC} K2 Pro compatibility was not confirmed."
        echo "Bitte zuerst Menüpunkt 1 ausführen und den Report prüfen."
        return 1
    fi
    return 0
}

require_backup() {
    if ! has_backup; then
        echo ""
        printf "%b\n" "${RED}ABBRUCH:${NC} Kein Backup gefunden in /mnt/UDISK/printer_data/backups/k2pro_helper"
        echo "Bitte zuerst Menüpunkt 2 ausführen."
        return 1
    fi
    return 0
}

run_install() {
    feature="$1"
    script="$2"
    marker="$3"
    require_k2pro_compatible || return 1
    if [ -n "$marker" ] && is_feature_marked "$marker"; then
        printf "%b\n" "${CYAN}Hinweis:${NC} $feature ist bereits installiert/markiert; Backup-Pflicht wird für Reparatur übersprungen."
    else
        require_backup || return 1
    fi
    confirm_install "$feature" && sh "$script" install
}

run_m600_bridge() {
    require_k2pro_compatible || return 1
    require_backup || return 1
    echo ""
    printf "%b\n" "${WHITE}M600 fuer K2 Pro Combo${NC}"
    echo "Mit CFS/Box installiert diese Version eine Pause/Park-Bridge."
    echo "Sie sendet keine direkten BOX_LOAD_MATERIAL, BOX_EXTRUDE_MATERIAL,"
    echo "_CFS_LOAD oder _CFS_UNLOAD Befehle."
    echo ""
    echo "Materialbewegung bleibt Creality/CFS, Display oder Slicer-Workflow."
    confirm_install "M600 CFS Bridge / M600 Support" && K2PRO_ALLOW_CFS_M600=1 sh "$SCRIPTS_DIR/m600.sh" install
}

run_nozzle_recover() {
    if confirm_action "Nozzle-AI Kamera kontrolliert aus/an schalten."; then
        sh "$SCRIPTS_DIR/nozzle_camera_recover.sh" recover
    else
        printf "%b\n" "${YELLOW}Nicht gestartet.${NC}"
    fi
}

run_nozzle_standby() {
    if confirm_action "Nozzle-AI Kamera in Standby/off setzen."; then
        sh "$SCRIPTS_DIR/nozzle_camera_recover.sh" standby
    else
        printf "%b\n" "${YELLOW}Nicht gestartet.${NC}"
    fi
}

run_kamp_install() {
    require_k2pro_compatible || return 1
    if [ -d "$CONFIG_DIR/KAMP" ] || grep -qs "KAMP/KAMP_Settings.cfg" "$CONFIG_DIR/printer.cfg" 2>/dev/null; then
        printf "%b\n" "${CYAN}Hinweis:${NC} KAMP-K2 ist bereits vorhanden. Diese Auswahl ist nur Reparatur/Neuinstallation."
        require_backup || return 1
        confirm_install "KAMP-K2 Adaptive Mesh repair/reinstall" && K2PRO_ALLOW_DANGEROUS_MODULES=1 sh "$SCRIPTS_DIR/kamp.sh" install
    else
        printf "%b\n" "${YELLOW}Hinweis:${NC} KAMP-K2 ist noch nicht aktiv erkannt. Neuinstallation bleibt Expert-Test."
        expert_confirm_run "KAMP-K2 Adaptive Mesh" "KAMP greift in Mesh/Purge/START-Workflow ein. Nur installieren, wenn du KAMP bewusst testen willst." "$SCRIPTS_DIR/kamp.sh"
    fi
}

m600_cfs_notice() {
    echo ""
    printf "%b\n" "${YELLOW}M600 ist hier kein CFS-Load/Unload-Ersatz.${NC}"
    echo "Beim K2 Pro Combo mit CFS/Box installiert diese Version eine Pause/Park-Bridge,"
    echo "damit Slicer-M600 sauber pausiert. Das eigentliche Materialhandling bleibt"
    echo "bei Creality/CFS, Display oder Slicer-Toolchange."
    echo ""
    run_m600_bridge
}

expert_confirm_run() {
    feature="$1"
    reason="$2"
    script="$3"

    require_k2pro_compatible || return 1

    if [ ! -f "$EXPERT_UNLOCK_FILE" ]; then
        not_use_notice "$feature - $reason"
        return 0
    fi

    if ! has_backup; then
        echo ""
        printf "%b\n" "${RED}ABBRUCH:${NC} Kein Backup gefunden in /mnt/UDISK/printer_data/backups/k2pro_helper"
        echo "Bitte zuerst Menüpunkt 2 ausführen."
        return 1
    fi

    echo ""
    printf "%b\n" "${RED}EXPERT-MODUS: $feature${NC}"
    echo "$reason"
    echo ""
    echo "Mindestregeln:"
    echo "  - Nur ein Modul testen, dann Klipper neu starten und Logs prüfen."
    echo "  - Druckkopf in sicherer Höhe halten, kein Druck direkt starten."
    echo "  - Bei Fehler sofort Restore/Remove nutzen."
    echo ""
    printf "Zum Start exakt eingeben: %s\n> " "$EXPERT_PHRASE"
    read phrase
    if [ "$phrase" != "$EXPERT_PHRASE" ]; then
        printf "%b\n" "${YELLOW}Nicht gestartet.${NC}"
        return 0
    fi
    K2PRO_ALLOW_DANGEROUS_MODULES=1 sh "$script" install
}

recommended_notice() {
    printf "%b\n" "${CYAN}Aktueller Stand:${NC} K2 Pro Combo, Firmware-Checks, CFS, Kamera, KAMP-K2, Timelapse-Recover, Fluidd/Mainsail, CFS-DB-Guard, Entware und lokale Backups sind sauber sortiert."
    printf "%b\n" "${YELLOW}Hinweis:${NC} Creality Klipper/Moonraker-Core nicht blind ueber Web-Update ersetzen."
}

main_menu() {
    print_header
    recommended_notice
    echo ""
    printf "%b\n" "  ${WHITE}Hauptmenue${NC}"
    printf "%b\n" "    ${YELLOW}1)${NC} ${GREEN}Erststart / Reihenfolge${NC}"
    printf "%b\n" "    ${YELLOW}2)${NC} ${GREEN}Status & Gesundheit${NC}"
    printf "%b\n" "    ${YELLOW}3)${NC} ${GREEN}Installieren / Reparieren${NC}"
    printf "%b\n" "    ${YELLOW}4)${NC} ${GREEN}Wartung, Logs & Neustart${NC}"
    printf "%b\n" "    ${YELLOW}5)${NC} ${GREEN}Wiederherstellen / Entfernen${NC}"
    printf "%b\n" "    ${YELLOW}6)${NC} ${CYAN}Erweitert / Tests${NC}"
    echo ""
    printf "%b\n" "    ${YELLOW}0)${NC} ${RED}Exit${NC}"
    echo ""
    printf "  \033[0;32mEnter choice:\033[0m "
    read choice
    case "$choice" in
        1) first_run_menu ;;
        2) status_menu ;;
        3) install_menu ;;
        4) maintenance_menu ;;
        5) remove_menu; main_menu; return ;;
        6) advanced_menu ;;
        0) echo ""; echo "Goodbye!"; echo ""; exit 0 ;;
        *) printf "%b\n" "${RED}Invalid choice.${NC}"; sleep 1; main_menu; return ;;
    esac
}

first_run_menu() {
    print_header
    printf "%b\n" "  ${WHITE}[Erststart / empfohlene Reihenfolge]${NC}"
    echo ""
    printf "%b\n" "  ${CYAN}Beim ersten Mal von oben nach unten ausfuehren:${NC}"
    printf "%b\n" "    ${YELLOW}1)${NC} ${GREEN}Drucker-Eignung pruefen${NC}       ${WHITE}(Modell, Board, 300x300x300, Firmware)${NC}"
    printf "%b\n" "    ${YELLOW}2)${NC} ${GREEN}Backup erstellen${NC}              ${WHITE}(Pflicht vor neuen Aenderungen)${NC}"
    printf "%b\n" "    ${YELLOW}3)${NC} ${GREEN}Installiertes anzeigen${NC}        ${WHITE}(was ist schon aktiv?)${NC}"
    printf "%b\n" "    ${YELLOW}4)${NC} ${GREEN}Kompletter Healthcheck${NC}        ${WHITE}(Klipper, Moonraker, CFS, Kamera, Speicher)${NC}"
    printf "%b\n" "    ${YELLOW}5)${NC} ${GREEN}CFS/BOX Diagnose${NC}             ${WHITE}(wichtig beim Combo)${NC}"
    printf "%b\n" "    ${YELLOW}6)${NC} ${GREEN}Kamera testen${NC}"
    printf "%b\n" "    ${YELLOW}7)${NC} ${GREEN}Nozzle-AI USB/UVC Diagnose${NC} ${WHITE}(read-only; fuer Kamera/AI-Fehlersuche)${NC}"
    printf "%b\n" "    ${YELLOW}8)${NC} ${GREEN}Fluidd/Mainsail testen${NC}"
    printf "%b\n" "    ${YELLOW}9)${NC} ${GREEN}Firmware/System pruefen${NC}"
    printf "%b\n" "   ${YELLOW}10)${NC} ${GREEN}Menue-Eignung auditieren${NC}     ${WHITE}(was passt zum K2 Pro?)${NC}"
    printf "%b\n" "   ${YELLOW}11)${NC} ${GREEN}Abhaengigkeiten pruefen${NC}      ${WHITE}(Tools, Services, Ports)${NC}"
    printf "%b\n" "   ${YELLOW}12)${NC} ${GREEN}Deep Datei-/Script-Audit${NC}    ${WHITE}(Configs, Logs, Rechte)${NC}"
    printf "%b\n" "   ${YELLOW}13)${NC} ${GREEN}Spoolman CFS Status${NC}"
    printf "%b\n" "   ${YELLOW}14)${NC} ${GREEN}Spoolman CFS Slot-Map Wizard${NC}"
    echo ""
    printf "%b\n" "  ${YELLOW}Nicht als Erststart installieren:${NC} Z-Offset-Makros, HelixScreen. M600-Bridge nur wenn Slicer-M600 gebraucht wird."
    printf "%b\n" "  ${YELLOW}KAMP-K2:${NC} auf deinem Drucker getestet; Reparatur/erneut installieren im Install-Menue."
    echo ""
    printf "%b\n" "    ${YELLOW}0)${NC} ${RED}Zurueck${NC}"
    echo ""
    printf "  ${GREEN}Enter choice:${NC} "
    read choice
    case "$choice" in
        1) handle_choice 1 ;;
        2) handle_choice 2 ;;
        3) handle_choice 3 ;;
        4) handle_choice 30 ;;
        5) handle_choice 29 ;;
        6) handle_choice 28 ;;
        7) handle_choice 48 ;;
        8) handle_choice 33 ;;
        9) handle_choice 34 ;;
        10) handle_choice 32 ;;
        11) handle_choice 40 ;;
        12) handle_choice 45 ;;
        13) handle_choice 52 ;;
        14) handle_choice 51 ;;
        0) main_menu; return ;;
        *) printf "%b\n" "${RED}Invalid choice.${NC}"; sleep 1; first_run_menu; return ;;
    esac
}

status_menu() {
    print_header
    printf "%b\n" "  ${WHITE}[Status & Gesundheit]${NC}"
    echo ""
    printf "%b\n" "    ${YELLOW}1)${NC} ${GREEN}Installierte Module + Uebersicht${NC}"
    printf "%b\n" "    ${YELLOW}2)${NC} ${GREEN}Kompletter Healthcheck${NC}"
    printf "%b\n" "    ${YELLOW}3)${NC} ${GREEN}Firmware/System Healthcheck${NC}"
    printf "%b\n" "    ${YELLOW}4)${NC} ${GREEN}K2 Pro Preflight Report${NC}"
    printf "%b\n" "    ${YELLOW}5)${NC} ${GREEN}CFS/BOX Diagnose${NC}"
    printf "%b\n" "    ${YELLOW}6)${NC} ${GREEN}Kamera Healthcheck${NC}"
    printf "%b\n" "    ${YELLOW}7)${NC} ${GREEN}Nozzle-AI USB/UVC Diagnose${NC} ${WHITE}(read-only)${NC}"
    printf "%b\n" "    ${YELLOW}8)${NC} ${GREEN}Fluidd/Mainsail Healthcheck${NC}"
    printf "%b\n" "    ${YELLOW}9)${NC} ${GREEN}CFS Material-DB Guard Status${NC}"
    printf "%b\n" "   ${YELLOW}10)${NC} ${GREEN}CFS Protokoll-/Slot-Report${NC} ${WHITE}(read-only)${NC}"
    printf "%b\n" "   ${YELLOW}11)${NC} ${GREEN}Timelapse Recover Status${NC}"
    printf "%b\n" "   ${YELLOW}12)${NC} ${GREEN}Entware Status${NC}"
    printf "%b\n" "   ${YELLOW}13)${NC} ${GREEN}Abhaengigkeiten pruefen${NC}"
    printf "%b\n" "   ${YELLOW}14)${NC} ${GREEN}Deep Datei-/Script-Audit${NC}"
    printf "%b\n" "   ${YELLOW}15)${NC} ${GREEN}Spoolman CFS Status${NC}"
    printf "%b\n" "    ${YELLOW}0)${NC} ${RED}Zurueck${NC}"
    echo ""
    printf "  ${GREEN}Enter choice:${NC} "
    read choice
    case "$choice" in
        1) handle_choice 3 ;;
        2) handle_choice 30 ;;
        3) handle_choice 34 ;;
        4) handle_choice 1 ;;
        5) handle_choice 29 ;;
        6) handle_choice 28 ;;
        7) handle_choice 48 ;;
        8) handle_choice 33 ;;
        9) handle_choice 43 ;;
        10) handle_choice 44 ;;
        11) handle_choice 46 ;;
        12) handle_choice 47 ;;
        13) handle_choice 40 ;;
        14) handle_choice 45 ;;
        15) handle_choice 52 ;;
        0) main_menu; return ;;
        *) printf "%b\n" "${RED}Invalid choice.${NC}"; sleep 1; status_menu; return ;;
    esac
}

install_menu() {
    print_header
    printf "%b\n" "  ${WHITE}[Installieren / Reparieren]${NC}"
    printf "%b\n" "  ${CYAN}Empfohlenes ist oben, optionale Tests unten. Bereits installierte Module koennen hier repariert werden.${NC}"
    echo ""
    printf "%b\n" "  ${WHITE}Basis / Web / Kamera${NC}"
    printf "%b\n" "    ${YELLOW}1)${NC} ${GREEN}Moonraker Erweiterungen${NC} ${WHITE}(Update-Manager, Metadaten, Spoolman/Mainsail-Basis)${NC}"
    printf "%b\n" "    ${YELLOW}2)${NC} ${GREEN}Fluidd aktualisieren / reparieren${NC}"
    printf "%b\n" "    ${YELLOW}3)${NC} ${GREEN}Mainsail installieren / reparieren${NC}"
    printf "%b\n" "    ${YELLOW}4)${NC} ${GREEN}Kamera WebRTC/go2rtc${NC}"
    printf "%b\n" "    ${YELLOW}5)${NC} ${GREEN}Creality Timelapse Recover${NC}"
    echo ""
    printf "%b\n" "  ${WHITE}Druck- und CFS-Helfer${NC}"
    printf "%b\n" "    ${YELLOW}6)${NC} ${GREEN}CFS Material-DB Guard${NC} ${WHITE}(Profile nach Neustart erhalten)${NC}"
    printf "%b\n" "    ${YELLOW}7)${NC} ${YELLOW}KAMP-K2 Adaptive Mesh${NC} ${WHITE}(Reparatur; Neuinstallation nur Expert)${NC}"
    printf "%b\n" "    ${YELLOW}8)${NC} ${GREEN}Fans Control Macros${NC}"
    printf "%b\n" "    ${YELLOW}9)${NC} ${GREEN}Useful Macros${NC}"
    printf "%b\n" "   ${YELLOW}10)${NC} ${GREEN}Improved Shapers${NC}"
    echo ""
    printf "%b\n" "  ${WHITE}Optional / Hinweise${NC}"
    printf "%b\n" "   ${YELLOW}11)${NC} ${GREEN}Entware Package Manager${NC}"
    printf "%b\n" "   ${YELLOW}12)${NC} ${YELLOW}Moonraker Timelapse${NC} ${WHITE}(optional; Creality Recover ist Standard)${NC}"
    printf "%b\n" "   ${YELLOW}13)${NC} ${GREEN}M600 CFS Bridge / M600 Support${NC}"
    printf "%b\n" "   ${YELLOW}14)${NC} ${GREEN}Git Backup lokal${NC} ${WHITE}(Konfig-Snapshots ohne Cloud)${NC}"
    printf "%b\n" "   ${YELLOW}15)${NC} ${GREEN}Spoolman CFS Sync Dienst${NC}"
    printf "%b\n" "   ${YELLOW}16)${NC} ${GREEN}Spoolman CFS Slot-Map Wizard${NC}"
    printf "%b\n" "    ${YELLOW}0)${NC} ${RED}Zurueck${NC}"
    echo ""
    printf "  ${GREEN}Enter choice:${NC} "
    read choice
    case "$choice" in
        1) handle_choice 4 ;;
        2) handle_choice 9 ;;
        3) handle_choice 10 ;;
        4) handle_choice 12 ;;
        5) handle_choice 37 ;;
        6) handle_choice 41 ;;
        7) handle_choice 18 ;;
        8) handle_choice 5 ;;
        9) handle_choice 6 ;;
        10) handle_choice 8 ;;
        11) handle_choice 15 ;;
        12) handle_choice 11 ;;
        13) handle_choice 7 ;;
        14) handle_choice 16 ;;
        15) handle_choice 50 ;;
        16) handle_choice 51 ;;
        0) main_menu; return ;;
        *) printf "%b\n" "${RED}Invalid choice.${NC}"; sleep 1; install_menu; return ;;
    esac
}

maintenance_menu() {
    print_header
    printf "%b\n" "  ${WHITE}[Wartung, Logs & Neustart]${NC}"
    echo ""
    printf "%b\n" "    ${YELLOW}1)${NC} ${GREEN}Backup erstellen${NC}"
    printf "%b\n" "    ${YELLOW}2)${NC} ${GREEN}Klipper neu starten${NC}"
    printf "%b\n" "    ${YELLOW}3)${NC} ${GREEN}Moonraker neu starten${NC}"
    printf "%b\n" "    ${YELLOW}4)${NC} ${GREEN}Nginx neu starten${NC}"
    printf "%b\n" "    ${YELLOW}5)${NC} ${GREEN}Kamera-Bridge neu starten${NC}"
    printf "%b\n" "    ${YELLOW}6)${NC} ${GREEN}Klipper Log anzeigen${NC}"
    printf "%b\n" "    ${YELLOW}7)${NC} ${GREEN}Moonraker Log anzeigen${NC}"
    printf "%b\n" "    ${YELLOW}8)${NC} ${GREEN}G-Code Preview Queue reparieren${NC}"
    printf "%b\n" "    ${YELLOW}9)${NC} ${GREEN}CFS Command/Log Scan${NC}"
    printf "%b\n" "   ${YELLOW}10)${NC} ${GREEN}CFS Material-DB reparieren${NC}"
    printf "%b\n" "   ${YELLOW}11)${NC} ${GREEN}CFS Protokoll-/Slot-Report${NC} ${WHITE}(read-only)${NC}"
    printf "%b\n" "   ${YELLOW}12)${NC} ${GREEN}Deep Datei-/Script-Audit${NC} ${WHITE}(read-only)${NC}"
    printf "%b\n" "   ${YELLOW}13)${NC} ${GREEN}Spoolman CFS Status${NC}"
    printf "%b\n" "   ${YELLOW}14)${NC} ${GREEN}Spoolman CFS Slot-Map Wizard${NC}"
    printf "%b\n" "   ${YELLOW}15)${NC} ${GREEN}Spoolman CFS Sync einmal ausfuehren${NC}"
    printf "%b\n" "   ${YELLOW}16)${NC} ${GREEN}Spoolman CFS Dienst neu starten${NC}"
    printf "%b\n" "   ${YELLOW}17)${NC} ${YELLOW}Nozzle-AI Power-Recover${NC}"
    printf "%b\n" "   ${YELLOW}18)${NC} ${YELLOW}Nozzle-AI Standby/off${NC}"
    printf "%b\n" "    ${YELLOW}0)${NC} ${RED}Zurueck${NC}"
    echo ""
    printf "  ${GREEN}Enter choice:${NC} "
    read choice
    case "$choice" in
        1) handle_choice 2 ;;
        2) handle_choice 22 ;;
        3) handle_choice 23 ;;
        4) handle_choice 24 ;;
        5) handle_choice 31 ;;
        6) handle_choice 25 ;;
        7) handle_choice 26 ;;
        8) handle_choice 35 ;;
        9) handle_choice 36 ;;
        10) handle_choice 42 ;;
        11) handle_choice 44 ;;
        12) handle_choice 45 ;;
        13) handle_choice 52 ;;
        14) handle_choice 51 ;;
        15) handle_choice 53 ;;
        16) handle_choice 54 ;;
        17) handle_choice 58 ;;
        18) handle_choice 59 ;;
        0) main_menu; return ;;
        *) printf "%b\n" "${RED}Invalid choice.${NC}"; sleep 1; maintenance_menu; return ;;
    esac
}

advanced_menu() {
    print_header
    printf "%b\n" "  ${WHITE}[Erweitert / Tests]${NC}"
    echo ""
    printf "%b\n" "    ${YELLOW}1)${NC} ${GREEN}K2 Pro Menue-Audit${NC}"
    printf "%b\n" "    ${YELLOW}2)${NC} ${CYAN}Expert-Unlock Status${NC}"
    printf "%b\n" "    ${YELLOW}3)${NC} ${GREEN}Nicht installierte Module pruefen${NC}"
    printf "%b\n" "    ${YELLOW}4)${NC} ${GREEN}Abhaengigkeiten pruefen${NC} ${WHITE}(nur lesen)${NC}"
    printf "%b\n" "    ${YELLOW}5)${NC} ${GREEN}HelixScreen pruefen${NC} ${WHITE}(nur lesen)${NC}"
    printf "%b\n" "    ${YELLOW}6)${NC} ${GREEN}Nozzle-AI USB/UVC Diagnose${NC} ${WHITE}(read-only; Log/Hotplug/Video-Nodes)${NC}"
    printf "%b\n" "    ${YELLOW}7)${NC} ${RED}Z-Offset Macros${NC} ${WHITE}(weiter gesperrt)${NC}"
    printf "%b\n" "    ${YELLOW}8)${NC} ${RED}HelixScreen installieren/testen${NC} ${WHITE}(weiter gesperrt)${NC}"
    printf "%b\n" "    ${YELLOW}9)${NC} ${YELLOW}M600 CFS Bridge / M600 Support${NC}"
    printf "%b\n" "    ${YELLOW}10)${NC} ${CYAN}OctoEverywhere offizieller Installer${NC} ${WHITE}(Cloud/Remote, fragt extra)${NC}"
    printf "%b\n" "    ${YELLOW}11)${NC} ${GREEN}Mobileraker Setup-Hilfe${NC} ${WHITE}(App lokal, Companion besser auf Raspi)${NC}"
    printf "%b\n" "    ${YELLOW}12)${NC} ${GREEN}Git Backup lokal${NC} ${WHITE}(Snapshot/Reparatur)${NC}"
    printf "%b\n" "    ${YELLOW}13)${NC} ${GREEN}Spoolman CFS Status${NC}"
    printf "%b\n" "    ${YELLOW}14)${NC} ${GREEN}Spoolman CFS Slot-Map Wizard${NC}"
    printf "%b\n" "    ${YELLOW}15)${NC} ${GREEN}Spoolman CFS Sync einmal ausfuehren${NC}"
    printf "%b\n" "    ${YELLOW}16)${NC} ${YELLOW}Nozzle-AI Power-Recover${NC}"
    printf "%b\n" "    ${YELLOW}17)${NC} ${YELLOW}Nozzle-AI Standby/off${NC}"
    printf "%b\n" "    ${YELLOW}0)${NC} ${RED}Zurueck${NC}"
    echo ""
    printf "  ${GREEN}Enter choice:${NC} "
    read choice
    case "$choice" in
        1) handle_choice 32 ;;
        2) handle_choice 27 ;;
        3) handle_choice 38 ;;
        4) handle_choice 40 ;;
        5) handle_choice 39 ;;
        6) handle_choice 48 ;;
        7) handle_choice 17 ;;
        8) handle_choice 19 ;;
        9) handle_choice 7 ;;
        10) handle_choice 13 ;;
        11) handle_choice 14 ;;
        12) handle_choice 16 ;;
        13) handle_choice 52 ;;
        14) handle_choice 51 ;;
        15) handle_choice 53 ;;
        16) handle_choice 58 ;;
        17) handle_choice 59 ;;
        0) main_menu; return ;;
        *) printf "%b\n" "${RED}Invalid choice.${NC}"; sleep 1; advanced_menu; return ;;
    esac
}

handle_choice() {
    case "$1" in
        1)  sh "$SCRIPTS_DIR/preflight_k2pro.sh" ;;
        2)  sh "$SCRIPTS_DIR/backup.sh" backup ;;
        3)  sh "$SCRIPTS_DIR/system.sh" installed_status ;;
        4)  run_install "Moonraker Extensions" "$SCRIPTS_DIR/moonraker.sh" "moonraker_extensions" ;;
        5)  run_install "Fans Control Macros" "$SCRIPTS_DIR/fans.sh" "fans_control_macros" ;;
        6)  run_install "Useful Macros" "$SCRIPTS_DIR/useful_macros.sh" "useful_macros" ;;
        7)  m600_cfs_notice ;;
        8)  run_install "Improved Shapers" "$SCRIPTS_DIR/shapers.sh" "improved_shapers" ;;
        9)  run_install "Fluidd" "$SCRIPTS_DIR/fluidd.sh" "fluidd_updated" ;;
        10) run_install "Mainsail" "$SCRIPTS_DIR/mainsail.sh" "mainsail" ;;
        11) run_install "Moonraker Timelapse" "$SCRIPTS_DIR/timelapse.sh" "moonraker_timelapse" ;;
        12) run_install "Camera Support" "$SCRIPTS_DIR/camera.sh" "camera_support" ;;
        13) sh "$SCRIPTS_DIR/octoeverywhere.sh" install ;;
        14) sh "$SCRIPTS_DIR/mobileraker.sh" install ;;
        15) run_install "Entware" "$SCRIPTS_DIR/entware.sh" "entware" ;;
        16) run_install "Git Backup lokal" "$SCRIPTS_DIR/git_backup.sh" "git_backup" ;;
        17) expert_confirm_run "Save Z-Offset Macros" "Z-offset macros speichern Offsets dauerhaft und können Nozzle/Bett gefährden." "$SCRIPTS_DIR/z_offset.sh" ;;
        18) run_kamp_install ;;
        19) expert_confirm_run "HelixScreen" "HelixScreen ersetzt/uebernimmt den Stock-Touchscreen; erst Status/Audit pruefen." "$SCRIPTS_DIR/helixscreen.sh" install ;;
        27) expert_status ;;
        20) remove_menu; main_menu; return ;;
        21) sh "$SCRIPTS_DIR/backup.sh" restore ;;
        22) sh "$SCRIPTS_DIR/system.sh" restart_klipper ;;
        23) sh "$SCRIPTS_DIR/system.sh" restart_moonraker ;;
        24) sh "$SCRIPTS_DIR/system.sh" restart_nginx ;;
        25) tail -80 "$LOGS_DIR/klippy.log" 2>/dev/null || echo "Klipper log not found: $LOGS_DIR/klippy.log" ;;
        26) tail -80 "$LOGS_DIR/moonraker.log" 2>/dev/null || echo "Moonraker log not found: $LOGS_DIR/moonraker.log" ;;
        28) sh "$SCRIPTS_DIR/health.sh" camera ;;
        29) sh "$SCRIPTS_DIR/health.sh" cfs ;;
        30) sh "$SCRIPTS_DIR/health.sh" all ;;
        31) sh "$SCRIPTS_DIR/system.sh" restart_camera ;;
        32) sh "$SCRIPTS_DIR/menu_audit_k2pro.sh" ;;
        33) sh "$SCRIPTS_DIR/health.sh" frontends ;;
        34) sh "$SCRIPTS_DIR/health.sh" firmware ;;
        35) sh "$SCRIPTS_DIR/system.sh" fix_moonraker_queue && sh "$SCRIPTS_DIR/system.sh" restart_moonraker force ;;
        36) sh "$SCRIPTS_DIR/cfs_safety_scan.sh" ;;
        37) run_install "Creality Timelapse Recover" "$SCRIPTS_DIR/creality_timelapse_recover.sh" "creality_timelapse_recover" ;;
        38) sh "$SCRIPTS_DIR/uninstalled_audit_k2pro.sh" ;;
        39) sh "$SCRIPTS_DIR/helixscreen.sh" status ;;
        40) sh "$SCRIPTS_DIR/dependency_audit_k2pro.sh" ;;
        41) run_install "CFS Material-DB Guard" "$SCRIPTS_DIR/cfs_db_guard.sh" "cfs_db_guard" ;;
        42) require_k2pro_compatible && sh "$SCRIPTS_DIR/cfs_db_guard.sh" repair ;;
        43) sh "$SCRIPTS_DIR/cfs_db_guard.sh" status ;;
        44) sh "$SCRIPTS_DIR/cfs_protocol_report.sh" ;;
        45) sh "$SCRIPTS_DIR/deep_file_audit_k2pro.sh" ;;
        46) sh "$SCRIPTS_DIR/creality_timelapse_recover.sh" status ;;
        47) sh "$SCRIPTS_DIR/entware.sh" status ;;
        48) sh "$SCRIPTS_DIR/nozzle_camera_recover.sh" diagnose ;;
        50) run_install "Spoolman CFS Sync" "$SCRIPTS_DIR/spoolman_cfs.sh" "spoolman_cfs_sync" ;;
        51) sh "$SCRIPTS_DIR/spoolman_cfs.sh" wizard ;;
        52) sh "$SCRIPTS_DIR/spoolman_cfs.sh" status ;;
        53) sh "$SCRIPTS_DIR/spoolman_cfs.sh" once ;;
        54) sh "$SCRIPTS_DIR/spoolman_cfs.sh" restart ;;
        55) sh "$SCRIPTS_DIR/spoolman_cfs.sh" enable ;;
        56) sh "$SCRIPTS_DIR/spoolman_cfs.sh" disable ;;
        58) run_nozzle_recover ;;
        59) run_nozzle_standby ;;
        63) sh "$SCRIPTS_DIR/spoolman_cfs.sh" list ;;
        0)  echo ""; echo "Goodbye!"; echo ""; exit 0 ;;
        *)  printf "%b\n" "${RED}Invalid choice.${NC}"; sleep 1 ;;
    esac
    echo ""
    printf "Press Enter to return to main menu..."
    read dummy
    main_menu
}

remove_menu() {
    print_header
    printf "%b\n" "  ${WHITE}[Wiederherstellen / Entfernen]${NC}"
    printf "%b\n" "  ${CYAN}Erst Backup/Restore, dann einzelne Module. Entfernen ist bewusst getrennt von Installation.${NC}"
    echo ""
    printf "%b\n" "    ${YELLOW}1)${NC}  ${GREEN}Backup wiederherstellen${NC}"
    echo ""
    printf "%b\n" "  ${WHITE}Module entfernen${NC}"
    printf "%b\n" "    ${YELLOW}2)${NC}  ${GREEN}Moonraker Extensions${NC}"
    printf "%b\n" "    ${YELLOW}3)${NC}  ${GREEN}Fans Control Macros${NC}"
    printf "%b\n" "    ${YELLOW}4)${NC}  ${GREEN}Useful Macros${NC}"
    printf "%b\n" "    ${YELLOW}5)${NC}  ${RED}Save Z-Offset Macros - war/ist NICHT BENUTZEN${NC}"
    printf "%b\n" "    ${YELLOW}6)${NC}  ${YELLOW}M600 Support${NC} ${WHITE}(nur falls versehentlich installiert)${NC}"
    printf "%b\n" "    ${YELLOW}7)${NC}  ${GREEN}KAMP-K2 Adaptive Mesh${NC}"
    printf "%b\n" "    ${YELLOW}8)${NC}  ${GREEN}Improved Shapers${NC}"
    printf "%b\n" "    ${YELLOW}9)${NC}  ${GREEN}Restore stock Fluidd${NC}"
    printf "%b\n" "   ${YELLOW}10)${NC}  ${GREEN}Mainsail${NC}"
    printf "%b\n" "   ${YELLOW}11)${NC}  ${GREEN}Moonraker Timelapse${NC}"
    printf "%b\n" "   ${YELLOW}12)${NC}  ${GREEN}Camera Support${NC}"
    printf "%b\n" "   ${YELLOW}13)${NC}  ${RED}HelixScreen - war/ist NICHT BENUTZEN${NC}"
    printf "%b\n" "   ${YELLOW}14)${NC}  ${GREEN}Entware Package Manager${NC}"
    printf "%b\n" "   ${YELLOW}15)${NC}  ${GREEN}Creality Timelapse Recover${NC}"
    printf "%b\n" "   ${YELLOW}16)${NC}  ${CYAN}OctoEverywhere${NC}"
    printf "%b\n" "   ${YELLOW}17)${NC}  ${GREEN}Mobileraker Setup-Hilfe${NC}"
    printf "%b\n" "   ${YELLOW}18)${NC}  ${GREEN}Git Backup lokal${NC}"
    printf "%b\n" "   ${YELLOW}19)${NC}  ${GREEN}Spoolman CFS Sync Dienst${NC}"
    printf "%b\n" "    ${YELLOW}0)${NC}  ${RED}Back to main menu${NC}"
    echo ""
    printf "  ${GREEN}Enter choice:${NC} "
    read choice
    case "$choice" in
        1)  sh "$SCRIPTS_DIR/backup.sh" restore ;;
        2)  sh "$SCRIPTS_DIR/moonraker.sh" remove ;;
        3)  sh "$SCRIPTS_DIR/fans.sh" remove ;;
        4)  sh "$SCRIPTS_DIR/useful_macros.sh" remove ;;
        5)  sh "$SCRIPTS_DIR/z_offset.sh" remove ;;
        6)  sh "$SCRIPTS_DIR/m600.sh" remove ;;
        7)  sh "$SCRIPTS_DIR/kamp.sh" remove ;;
        8)  sh "$SCRIPTS_DIR/shapers.sh" remove ;;
        9)  sh "$SCRIPTS_DIR/fluidd.sh" remove ;;
        10) sh "$SCRIPTS_DIR/mainsail.sh" remove ;;
        11) sh "$SCRIPTS_DIR/timelapse.sh" remove ;;
        12) sh "$SCRIPTS_DIR/camera.sh" remove ;;
        13) sh "$SCRIPTS_DIR/helixscreen.sh" remove ;;
        14) sh "$SCRIPTS_DIR/entware.sh" remove ;;
        15) sh "$SCRIPTS_DIR/creality_timelapse_recover.sh" remove ;;
        16) sh "$SCRIPTS_DIR/octoeverywhere.sh" remove ;;
        17) sh "$SCRIPTS_DIR/mobileraker.sh" remove ;;
        18) sh "$SCRIPTS_DIR/git_backup.sh" remove ;;
        19) sh "$SCRIPTS_DIR/spoolman_cfs.sh" remove ;;
        0)  return ;;
        *)  printf "%b\n" "${RED}Invalid choice.${NC}"; sleep 1; remove_menu; return ;;
    esac
    echo ""
    printf "Press Enter to return to Remove menu..."
    read dummy
    remove_menu
}

usage() {
    echo "Usage: $0 [--version|--health|--health-camera|--health-cfs|--health-frontends|--health-firmware|--preflight|--backup|--status|--show-installed|--restart-camera|--nozzle-camera-diagnose|--nozzle-camera-recover|--nozzle-camera-standby|--spoolman-cfs-status|--spoolman-cfs-install|--spoolman-cfs-map-wizard|--spoolman-cfs-list-spools|--spoolman-cfs-map-enable|--spoolman-cfs-map-disable|--spoolman-cfs-sync-once|--spoolman-cfs-restart|--m600-install|--menu-audit|--uninstalled-audit|--dependency-audit|--deep-file-audit|--helixscreen-audit|--cfs-safety-scan|--cfs-protocol-report|--cfs-db-guard|--cfs-db-repair|--cfs-db-guard-status|--fix-moonraker-queue|--timelapse-recover|--timelapse-recover-status|--entware-status|--entware-ensure|--git-backup|--git-backup-status|--octoeverywhere-status|--mobileraker-status|--help]"
    echo ""
    echo "Without arguments this script starts the interactive menu and requires a TTY."
}

run_cli() {
    cli_arg="$(printf "%s" "$1" | tr -d '\r')"
    case "$cli_arg" in
        "")
            return 0
            ;;
        --version|version)
            sed -n '2p' "$SCRIPT_DIR/helper.sh" 2>/dev/null || echo "Creality K2 Pro Combo Helper v5.2.21.59-health-proc-detect"
            exit 0
            ;;
        --health|health)
            sh "$SCRIPTS_DIR/health.sh" all
            exit $?
            ;;
        --health-camera|health-camera)
            sh "$SCRIPTS_DIR/health.sh" camera
            exit $?
            ;;
        --health-cfs|health-cfs)
            sh "$SCRIPTS_DIR/health.sh" cfs
            exit $?
            ;;
        --health-frontends|health-frontends)
            sh "$SCRIPTS_DIR/health.sh" frontends
            exit $?
            ;;
        --health-firmware|health-firmware)
            sh "$SCRIPTS_DIR/health.sh" firmware
            exit $?
            ;;
        --preflight|preflight)
            sh "$SCRIPTS_DIR/preflight_k2pro.sh"
            exit $?
            ;;
        --backup|backup)
            sh "$SCRIPTS_DIR/backup.sh" backup
            exit $?
            ;;
        --show-installed|show-installed)
            sh "$SCRIPTS_DIR/system.sh" show_installed
            exit $?
            ;;
        --status|status|--installed-status|installed-status)
            sh "$SCRIPTS_DIR/system.sh" installed_status
            exit $?
            ;;
        --restart-camera|restart-camera)
            sh "$SCRIPTS_DIR/system.sh" restart_camera
            exit $?
            ;;
        --nozzle-camera-diagnose|nozzle-camera-diagnose|--nozzle-usb-diagnose|nozzle-usb-diagnose)
            sh "$SCRIPTS_DIR/nozzle_camera_recover.sh" diagnose
            exit $?
            ;;
        --nozzle-camera-recover|nozzle-camera-recover|--nozzle-ai-recover|nozzle-ai-recover)
            sh "$SCRIPTS_DIR/nozzle_camera_recover.sh" recover
            exit $?
            ;;
        --nozzle-camera-standby|nozzle-camera-standby|--nozzle-camera-off|nozzle-camera-off)
            sh "$SCRIPTS_DIR/nozzle_camera_recover.sh" standby
            exit $?
            ;;
        --spoolman-cfs-status|spoolman-cfs-status|--spoolman-map-status|spoolman-map-status)
            sh "$SCRIPTS_DIR/spoolman_cfs.sh" status
            exit $?
            ;;
        --spoolman-cfs-install|spoolman-cfs-install)
            check_printer
            run_install "Spoolman CFS Sync" "$SCRIPTS_DIR/spoolman_cfs.sh" "spoolman_cfs_sync"
            exit $?
            ;;
        --spoolman-cfs-map-wizard|spoolman-cfs-map-wizard|--spoolman-map-wizard|spoolman-map-wizard)
            sh "$SCRIPTS_DIR/spoolman_cfs.sh" wizard
            exit $?
            ;;
        --spoolman-cfs-list-spools|spoolman-cfs-list-spools|--spoolman-list-spools|spoolman-list-spools)
            sh "$SCRIPTS_DIR/spoolman_cfs.sh" list
            exit $?
            ;;
        --spoolman-cfs-map-enable|spoolman-cfs-map-enable|--spoolman-map-enable|spoolman-map-enable)
            sh "$SCRIPTS_DIR/spoolman_cfs.sh" enable
            exit $?
            ;;
        --spoolman-cfs-map-disable|spoolman-cfs-map-disable|--spoolman-map-disable|spoolman-map-disable)
            sh "$SCRIPTS_DIR/spoolman_cfs.sh" disable
            exit $?
            ;;
        --spoolman-cfs-sync-once|spoolman-cfs-sync-once|--spoolman-sync-once|spoolman-sync-once)
            sh "$SCRIPTS_DIR/spoolman_cfs.sh" once
            exit $?
            ;;
        --spoolman-cfs-restart|spoolman-cfs-restart)
            sh "$SCRIPTS_DIR/spoolman_cfs.sh" restart
            exit $?
            ;;
        --m600-install|m600-install)
            check_printer
            run_m600_bridge
            exit $?
            ;;
        --menu-audit|menu-audit)
            sh "$SCRIPTS_DIR/menu_audit_k2pro.sh"
            exit $?
            ;;
        --uninstalled-audit|uninstalled-audit)
            sh "$SCRIPTS_DIR/uninstalled_audit_k2pro.sh"
            exit $?
            ;;
        --dependency-audit|dependency-audit)
            sh "$SCRIPTS_DIR/dependency_audit_k2pro.sh"
            exit $?
            ;;
        --deep-file-audit|deep-file-audit|--file-audit|file-audit)
            sh "$SCRIPTS_DIR/deep_file_audit_k2pro.sh"
            exit $?
            ;;
        --helixscreen-audit|helixscreen-audit)
            sh "$SCRIPTS_DIR/helixscreen.sh" status
            exit $?
            ;;
        --cfs-safety-scan|cfs-safety-scan)
            sh "$SCRIPTS_DIR/cfs_safety_scan.sh"
            exit $?
            ;;
        --cfs-protocol-report|cfs-protocol-report|--cfs-protocol|cfs-protocol)
            sh "$SCRIPTS_DIR/cfs_protocol_report.sh"
            exit $?
            ;;
        --cfs-db-guard|cfs-db-guard)
            check_printer
            run_install "CFS Material-DB Guard" "$SCRIPTS_DIR/cfs_db_guard.sh" "cfs_db_guard"
            exit $?
            ;;
        --cfs-db-repair|cfs-db-repair)
            check_printer
            require_k2pro_compatible || exit 1
            sh "$SCRIPTS_DIR/cfs_db_guard.sh" repair
            exit $?
            ;;
        --cfs-db-guard-status|cfs-db-guard-status)
            sh "$SCRIPTS_DIR/cfs_db_guard.sh" status
            exit $?
            ;;
        --fix-moonraker-queue|fix-moonraker-queue)
            sh "$SCRIPTS_DIR/system.sh" fix_moonraker_queue && sh "$SCRIPTS_DIR/system.sh" restart_moonraker force
            exit $?
            ;;
        --timelapse-recover|timelapse-recover)
            sh "$SCRIPTS_DIR/creality_timelapse_recover.sh" once
            exit $?
            ;;
        --timelapse-recover-status|timelapse-recover-status)
            sh "$SCRIPTS_DIR/creality_timelapse_recover.sh" status
            exit $?
            ;;
        --entware-status|entware-status)
            sh "$SCRIPTS_DIR/entware.sh" status
            exit $?
            ;;
        --entware-ensure|entware-ensure)
            sh "$SCRIPTS_DIR/entware.sh" ensure
            exit $?
            ;;
        --git-backup|git-backup)
            check_printer
            run_install "Git Backup lokal" "$SCRIPTS_DIR/git_backup.sh" "git_backup"
            exit $?
            ;;
        --git-backup-status|git-backup-status)
            sh "$SCRIPTS_DIR/git_backup.sh" status
            exit $?
            ;;
        --octoeverywhere-status|octoeverywhere-status)
            sh "$SCRIPTS_DIR/octoeverywhere.sh" status
            exit $?
            ;;
        --mobileraker-status|mobileraker-status)
            sh "$SCRIPTS_DIR/mobileraker.sh" status
            exit $?
            ;;
        --help|-h|help)
            usage
            exit 0
            ;;
        *)
            printf "%b\n" "${RED}ERROR:${NC} Unknown non-interactive argument: $cli_arg"
            usage
            exit 2
            ;;
    esac
}

case "$(printf "%s" "$1" | tr -d '\r')" in
    --help|-h|help)
        usage
        exit 0
        ;;
    --version|version)
        sed -n '2p' "$SCRIPT_DIR/helper.sh" 2>/dev/null || echo "Creality K2 Pro Combo Helper v5.2.21.59-health-proc-detect"
        exit 0
        ;;
esac

check_root
run_cli "$1"

if [ ! -t 0 ]; then
    printf "%b\n" "${RED}ERROR:${NC} Interactive menu requires a TTY."
    usage
    exit 2
fi

check_printer
main_menu
