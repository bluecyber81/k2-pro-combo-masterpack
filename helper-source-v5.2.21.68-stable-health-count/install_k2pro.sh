#!/bin/sh
# Install/update this extracted helper package without replacing local state.
set -eu

TARGET=/mnt/UDISK/helper-script
BACKUP_ROOT=/mnt/UDISK/printer_data/backups/k2pro_helper
SOURCE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: run this installer as root."
    exit 1
fi

model="$(/usr/bin/get_sn_mac.sh model 2>/dev/null || true)"
board="$(/usr/bin/get_sn_mac.sh board 2>/dev/null || true)"
if [ "$model" != "F012" ] || [ "$board" != "CR0CN200400C10" ]; then
    echo "ERROR: expected K2 Pro model F012 and board CR0CN200400C10."
    echo "Detected: model=${model:-unknown} board=${board:-unknown}"
    exit 1
fi

test -f "$SOURCE/helper.sh"
test -f "$SOURCE/scripts/system.sh"
test -f "$SOURCE/scripts/klipper_gc.sh"
sh -n "$SOURCE/helper.sh"

echo "This updates only /mnt/UDISK/helper-script and preserves local hidden/state files."
echo "It does not flash firmware, MCU or CFS and does not restart printer services."
printf "Install/update Helper v5.2.21.68-stable-health-count? [y/n]: "
read confirm
[ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || { echo "Cancelled."; exit 0; }

mkdir -p "$TARGET" "$BACKUP_ROOT"
if [ "$SOURCE" != "$TARGET" ] && [ -d "$TARGET" ]; then
    stamp="$(date +%Y%m%d_%H%M%S)"
    backup="$BACKUP_ROOT/helper-script-before-v67_$stamp.tar.gz"
    tar -czf "$backup" -C /mnt/UDISK helper-script
    echo "Backup: $backup"
    cp -a "$SOURCE"/. "$TARGET"/
fi

chmod 0755 "$TARGET/helper.sh" "$TARGET/go2rtc"
find "$TARGET" -maxdepth 1 -type f -name '*.py' -exec chmod 0755 {} \;
find "$TARGET/scripts" -maxdepth 1 -type f \( -name '*.sh' -o -name 'S[0-9]*' \) -exec chmod 0755 {} \;
find "$TARGET/scripts" -maxdepth 1 -type f -name '*.py' -exec chmod 0755 {} \;
find "$TARGET" -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
touch "$TARGET/.installed"

grep -q 'v5.2.21.68-stable-health-count' "$TARGET/helper.sh"
sync
echo "HELPER_INSTALL_OK|version=v5.2.21.68-stable-health-count|target=$TARGET"
