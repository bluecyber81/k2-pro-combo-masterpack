#!/bin/sh
# helixscreen.sh - Install/remove HelixScreen on K2 Series printers
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

HELIX_INSTALL=/opt/helixscreen/install.sh
HELIX_INSTALLER_URL=https://raw.githubusercontent.com/prestonbrown/helixscreen/main/scripts/install.sh

exists_or_no() {
    [ -e "$1" ] && echo "yes" || echo "no"
}

cmd_or_no() {
    command -v "$1" >/dev/null 2>&1 && echo "yes" || echo "no"
}

helix_status() {
    echo ""
    echo "HelixScreen K2 Pro Combo audit"
    echo "Safety: read-only only. This does not install, move, heat, flash or restart."
    echo ""
    echo "Upstream state:"
    echo "  HelixScreen now documents Creality K2 Max/K2 Plus/K2 Pro support."
    echo "  Current K2 install source: $HELIX_INSTALLER_URL"
    echo "  It replaces/drives the stock 4.3 inch touchscreen and talks to Moonraker."
    echo ""
    echo "Local printer state:"
    echo "  arch=$(uname -m 2>/dev/null || echo unknown)"
    echo "  kernel=$(uname -r 2>/dev/null || echo unknown)"
    echo "  os=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '\"')"
    echo "  /mnt/UDISK=$(exists_or_no /mnt/UDISK)"
    echo "  printer_data=$(exists_or_no /mnt/UDISK/printer_data)"
    echo "  stock_display_server_running=$(pidof display-server >/dev/null 2>&1 && echo yes || echo no)"
    echo "  helix_service=$(exists_or_no /etc/init.d/S99helixscreen)"
    echo "  helix_install_dir=$(exists_or_no /opt/helixscreen)"
    echo "  helix_config_dir=$(exists_or_no /mnt/UDISK/printer_data/config/helixscreen)"
    echo "  moonraker_7125_listen=$(ss -ltn 2>/dev/null | grep -q ':7125 ' && echo yes || echo no)"
    echo "  fluidd_4408_listen=$(ss -ltn 2>/dev/null | grep -q ':4408 ' && echo yes || echo no)"
    echo "  python3=$(cmd_or_no python3)"
    echo "  wget=$(cmd_or_no wget)"
    echo "  curl=$(cmd_or_no curl)"
    echo "  free_root=$(df -h / 2>/dev/null | awk 'NR==2{print $4}')"
    echo "  free_udisk=$(df -h /mnt/UDISK 2>/dev/null | awk 'NR==2{print $4}')"
    echo ""
    if [ -f /etc/init.d/S99helixscreen ] || [ -d /opt/helixscreen ]; then
        echo "Decision: installed/traces-present"
        echo "Action: inspect logs before changing anything."
    else
        echo "Decision: test-only, keep-off as default"
        echo "Reason: upstream supports K2 Pro, but this printer currently has working stock display, CFS, AI/nozzle-camera and Creality time-lapse workflows."
        echo "Better path: only test HelixScreen after a fresh backup, idle printer, no active print, and a clear restore plan."
    fi
    echo ""
    echo "Recommendation:"
    echo "  Do not install HelixScreen as a normal helper baseline."
    echo "  If you want to try it later, pin a known-good release and expect to re-test camera, CFS, AI flow calibration, time-lapse and touch UI after reboot."
}

guard_dangerous_install() {
    if [ "$K2PRO_ALLOW_DANGEROUS_MODULES" = "1" ]; then
        return 0
    fi
    echo "BLOCKED: HelixScreen is intentionally blocked on K2 Pro Combo by default because it can break the stock Creality touchscreen workflow."
    echo "Use the helper menu Expert-Unlock flow, or override manually only if you understand the risk:"
    echo "  K2PRO_ALLOW_DANGEROUS_MODULES=1 sh $0 install"
    return 1
}

check_helixscreen() {
    [ -f /etc/init.d/S99helixscreen ] && return 0
    return 1
}

install_helixscreen() {
    guard_dangerous_install || return 1

    echo ""
    echo "======================================================"
    echo "  HelixScreen Installation"
    echo "======================================================"
    echo ""
    echo "  HelixScreen requires a reboot after installation."
    echo ""
    echo "  The installer will:"
    echo "    - Install HelixScreen"
    echo "    - Automatically reboot the printer"
    echo ""
    echo "  IMPORTANT:"
    echo "    - The first startup may take longer than normal."
    echo "    - The printer may remain on the Creality logo"
    echo "      for several minutes during the first boot."
    echo "    - Do NOT power off the printer during this process."
    echo "    - If stuck on Creality logo, use wipe_all USB recovery."
    echo ""
    printf "  Continue? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    if check_helixscreen; then
        log_info "HelixScreen is already installed."
        echo ""
        echo "  1) Update HelixScreen"
        echo "  0) Cancel"
        echo ""
        printf "  Enter choice: "
        read subchoice
        case "$subchoice" in
            1)
                log_info "Updating HelixScreen..."
                sh "$HELIX_INSTALL" --update || {
                    log_error "HelixScreen update failed."
                    return 1
                }
                log_success "HelixScreen updated."
                return 0 ;;
            *) log_info "Cancelled."; return 0 ;;
        esac
    fi

    log_info "Downloading and installing HelixScreen..."
    python3 -c "
import urllib.request as u
open('/tmp/install.sh','wb').write(
    u.urlopen(u.Request('$HELIX_INSTALLER_URL',
    headers={'User-Agent':'helixscreen-installer/1.0'}), timeout=30).read()
)
print('Downloaded installer')
"
    if [ ! -s /tmp/install.sh ]; then
        log_error "Failed to download HelixScreen installer."
        rm -f /tmp/install.sh
        return 1
    fi

    sh /tmp/install.sh
    rm -f /tmp/install.sh

    if ! check_helixscreen; then
        log_error "HelixScreen installation failed."
        return 1
    fi

    # Remove update_manager section - not supported on K2 Series firmware
    python3 -c "
import re
try:
    content = open('/mnt/UDISK/printer_data/config/moonraker.conf').read()
    content = re.sub(r'\[update_manager helixscreen\][^\[]*', '', content)
    open('/mnt/UDISK/printer_data/config/moonraker.conf', 'w').write(content)
    print('Cleaned moonraker.conf')
except: pass
"
    mark_installed "helixscreen"
    echo ""
    log_success "HelixScreen installed successfully!"
    echo ""
    log_info "The touchscreen will show HelixScreen after reboot."
    log_info "Note: WiFi management shows as unavailable — this is normal."
    log_info "      Your printer WiFi connection is not affected."
    echo ""
    echo ""
    echo "======================================================"
    echo "  HelixScreen installed successfully."
    echo ""
    echo "  The printer will reboot in 10 seconds..."
    echo ""
    echo "  After reboot:"
    echo "    - Startup may take longer than usual."
    echo "    - Please be patient and do not power off."
    echo "======================================================"
    echo ""
    sleep 10
    reboot
}

remove_helixscreen() {
    if ! is_installed "helixscreen"; then
        log_info "HelixScreen is not installed."
        return 0
    fi

    printf "%b\n" "${YELLOW}WARNING: This will remove HelixScreen.${NC}"
    printf "%b\n" "  The printer will reboot automatically after removal."
    printf "%b\n" "  Stock Creality UI will be restored after reboot."
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    echo ""
    log_info "Removing HelixScreen..."

    if ! check_helixscreen; then
        log_error "HelixScreen is not installed."
        return 1
    fi

    # Download installer if not present (may have been removed with Entware)
    if [ ! -f "$HELIX_INSTALL" ]; then
        log_info "Downloading HelixScreen installer for uninstall..."
        python3 -c "
import urllib.request as u
open('/tmp/helix_uninstall.sh','wb').write(
    u.urlopen(u.Request('$HELIX_INSTALLER_URL',
    headers={'User-Agent':'helixscreen-installer/1.0'}), timeout=30).read()
)
"
    else
        cp "$HELIX_INSTALL" /tmp/helix_uninstall.sh
    fi
    if [ ! -s /tmp/helix_uninstall.sh ]; then
        log_error "HelixScreen uninstall script is missing."
        rm -f /tmp/helix_uninstall.sh
        return 1
    fi
    sh /tmp/helix_uninstall.sh --uninstall
    rm -f /tmp/helix_uninstall.sh
    # Ensure stock services are running
    /etc/init.d/klipper restart 2>/dev/null
    /etc/init.d/moonraker restart 2>/dev/null
    # Clean up any remaining HelixScreen traces
    rm -rf /mnt/UDISK/printer_data/config/helixscreen 2>/dev/null
    rm -f /mnt/UDISK/printer_data/config/moonraker.conf.bak.helixscreen 2>/dev/null

    mark_removed "helixscreen"
    echo ""
    log_success "HelixScreen removed. Stock Creality UI restored after reboot."
    echo ""
    echo "======================================================"
    echo "  HelixScreen removed successfully."
    echo ""
    echo "  The printer will reboot in 10 seconds..."
    echo "  Stock Creality UI will be restored after reboot."
    echo "======================================================"
    echo ""
    sleep 10
    reboot
}

case "$1" in
    status|audit|probe) helix_status ;;
    install) install_helixscreen ;;
    remove)  remove_helixscreen ;;
    *)       echo "Usage: $0 [status|install|remove]" ;;
esac
