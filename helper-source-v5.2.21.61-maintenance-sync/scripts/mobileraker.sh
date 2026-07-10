#!/bin/sh
# mobileraker.sh - K2 Pro Mobileraker setup/status helper.

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

printer_ip() {
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'
}

status_mobileraker() {
    ipaddr="$(printer_ip)"
    [ -n "$ipaddr" ] || ipaddr="$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo ""
    echo "Mobileraker / Companion status"
    echo "Local app access usually needs no printer-side install."
    echo "Printer URL:    http://${ipaddr:-printer-ip}:4409  (Mainsail)"
    echo "Fallback URL:   http://${ipaddr:-printer-ip}:4408  (Fluidd)"
    echo "Moonraker:      http://${ipaddr:-printer-ip}:7125"
    echo "WebSocket:      ws://${ipaddr:-printer-ip}:7125/websocket"
    echo ""
    echo "Companion traces on this printer:"
    ps w | grep -i "mobileraker" | grep -v grep || echo "  none"
    find /mnt/UDISK /root /opt -maxdepth 3 -iname '*mobileraker*' 2>/dev/null | sed 's/^/  /' | head -30
    echo ""
}

install_mobileraker() {
    echo ""
    status_mobileraker
    printf "%b\n" "${GREEN}[INFO]${NC} For local Mobileraker app control, add the printer in the phone app with the URLs above."
    echo ""
    printf "%b\n" "${YELLOW}[INFO]${NC} Mobileraker Companion is best run on a Raspberry Pi/Debian host, not directly on the K2 Pro firmware."
    echo "Official standalone companion outline for a Debian/Raspberry Pi host:"
    echo "  cd ~/"
    echo "  git clone https://github.com/Clon1998/mobileraker_companion.git"
    echo "  ./mobileraker_companion/scripts/install.sh -standalone"
    echo ""
    echo "This helper therefore does not install the Companion onto the printer itself."
}

remove_mobileraker() {
    echo ""
    status_mobileraker
    log_info "No Mobileraker printer-side helper service is installed by this K2 helper."
    mark_removed mobileraker
}

case "$1" in
    install|guide) install_mobileraker ;;
    status)        status_mobileraker ;;
    remove)        remove_mobileraker ;;
    *)             echo "Usage: $0 [guide|install|status|remove]" ;;
esac
