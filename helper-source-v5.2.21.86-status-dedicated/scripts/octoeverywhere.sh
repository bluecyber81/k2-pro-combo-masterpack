#!/bin/sh
# octoeverywhere.sh - guarded official OctoEverywhere installer/status helper.

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

OFFICIAL_INSTALL="bash <(curl -s https://octoeverywhere.com/install.sh)"
CONF_CANDIDATES="/mnt/UDISK/printer_data/config/octoeverywhere.conf /usr/data/printer_data/config/octoeverywhere.conf /root/octoeverywhere/octoeverywhere.conf"

has_octoeverywhere() {
    pgrep -f -i "octoeverywhere" >/dev/null 2>&1 && return 0
    [ -e /etc/init.d/octoeverywhere ] && return 0
    [ -e /etc/rc.d/S99octoeverywhere ] && return 0
    [ -d /root/octoeverywhere ] && return 0
    [ -d /mnt/UDISK/octoeverywhere ] && return 0
    return 1
}

status_octoeverywhere() {
    echo ""
    echo "OctoEverywhere status"
    if has_octoeverywhere; then
        log_success "OctoEverywhere traces found."
    else
        log_info "OctoEverywhere is not installed on this printer."
    fi
    echo "Processes:"
    ps w | grep -i "octoeverywhere" | grep -v grep || echo "  none"
    echo "Files/services:"
    for item in /etc/init.d/octoeverywhere /etc/rc.d/S99octoeverywhere /root/octoeverywhere /mnt/UDISK/octoeverywhere; do
        [ -e "$item" ] && echo "  $item"
    done
    for conf in $CONF_CANDIDATES; do
        if [ -f "$conf" ]; then
            echo "Config: $conf"
            grep -E "^(frontend_port|printer_name|moonraker_port)" "$conf" 2>/dev/null | sed 's/^/  /'
        fi
    done
    echo ""
}

install_octoeverywhere() {
    echo ""
    printf "%b\n" "${YELLOW}OctoEverywhere is cloud remote access for Klipper/Moonraker.${NC}"
    echo "Official installer command:"
    echo "  $OFFICIAL_INSTALL"
    echo ""
    echo "This helper does not hide that installer behind an automatic silent install."
    echo "It will start the official installer only after an explicit confirmation."
    echo ""
    if ! command -v bash >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        log_error "bash and curl are required. Entware/system tools must be available first."
        return 1
    fi
    if [ ! -t 0 ]; then
        log_error "Interactive TTY required for the official OctoEverywhere installer."
        return 1
    fi
    printf "Type INSTALL OCTOEVERYWHERE to start the official installer, or press Enter to cancel: "
    read phrase
    if [ "$phrase" != "INSTALL OCTOEVERYWHERE" ]; then
        log_info "Cancelled."
        return 0
    fi
    bash -c "$OFFICIAL_INSTALL"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        mark_installed octoeverywhere
        log_success "OctoEverywhere installer finished."
    else
        log_error "OctoEverywhere installer returned $rc."
    fi
    return "$rc"
}

remove_octoeverywhere() {
    echo ""
    status_octoeverywhere
    printf "%b\n" "${YELLOW}WARNING: OctoEverywhere removal depends on the official install location.${NC}"
    printf "Try known uninstall scripts if present? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    rc=0
    found=0
    for script in /root/octoeverywhere/uninstall.sh /mnt/UDISK/octoeverywhere/uninstall.sh /usr/data/octoeverywhere/uninstall.sh; do
        if [ -x "$script" ]; then
            found=1
            "$script" || rc=$?
        fi
    done
    if [ "$found" -eq 0 ]; then
        log_warn "No known OctoEverywhere uninstall script found."
        echo "Manual check may be required in /root/octoeverywhere, /mnt/UDISK/octoeverywhere and /etc/init.d."
    else
        mark_removed octoeverywhere
    fi
    return "$rc"
}

case "$1" in
    install) install_octoeverywhere ;;
    status)  status_octoeverywhere ;;
    remove)  remove_octoeverywhere ;;
    *)       echo "Usage: $0 [install|status|remove]" ;;
esac
