#!/bin/sh
# moonraker.sh - Install/remove Moonraker extensions for K2 Series printers

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

MOONRAKER_CONF=$CONFIG_DIR/moonraker.conf
STOCK_MOONRAKER_CONF=/usr/share/moonraker/moonraker.conf
MOONRAKER_METADATA=/usr/share/moonraker/components/file_manager/metadata.py

ensure_creality_cloud_slicer_metadata() {
    if [ ! -f "$MOONRAKER_METADATA" ]; then
        log_warn "Moonraker metadata parser not found: $MOONRAKER_METADATA"
        return 1
    fi
    if grep -Fq 'Creality[_ ](?:Print|Cloud[_ ]Slicer)' "$MOONRAKER_METADATA"; then
        log_info "Moonraker already recognizes Creality Print and Cloud Slicer metadata."
        return 0
    fi

    backup_dir=/mnt/UDISK/printer_data/backups/k2pro_helper/moonraker_metadata
    stamp="$(date +%Y%m%d_%H%M%S)"
    backup="$backup_dir/metadata.py.before-cloud.$stamp"
    mkdir -p "$backup_dir"

    if ! python3 - "$MOONRAKER_METADATA" "$backup" <<'PYEOF'
import os
import pathlib
import shutil
import sys

path = pathlib.Path(sys.argv[1])
backup = pathlib.Path(sys.argv[2])
old = 'r";\\s*generated\\s+by\\s+Creality[_ ]Print\\s+V?([^\\s]+)"'
new = 'r";\\s*generated\\s+by\\s+Creality[_ ](?:Print|Cloud[_ ]Slicer)\\s+V?([^\\s]+)"'
source = path.read_text(encoding="utf-8")
if source.count(old) != 1:
    raise SystemExit("expected Creality Print identity expression was not found exactly once")
updated = source.replace(old, new, 1)
compile(updated, str(path), "exec")
shutil.copy2(str(path), str(backup))
temporary = path.with_name(path.name + ".cloud-new.%d" % os.getpid())
with temporary.open("w", encoding="utf-8", newline="") as stream:
    stream.write(updated)
    stream.flush()
    os.fsync(stream.fileno())
current = path.stat()
os.chmod(str(temporary), current.st_mode & 0o7777)
os.chown(str(temporary), current.st_uid, current.st_gid)
os.replace(str(temporary), str(path))
os.sync()
PYEOF
    then
        log_warn "Moonraker Cloud Slicer metadata patch was not applied."
        return 1
    fi

    if grep -Fq 'Creality[_ ](?:Print|Cloud[_ ]Slicer)' "$MOONRAKER_METADATA"; then
        log_success "Enabled Creality Cloud Slicer metadata recognition (backup: $backup)"
        return 0
    fi
    log_warn "Moonraker Cloud Slicer metadata patch did not verify."
    return 1
}

ensure_update_manager_compat_files() {
    # This Creality firmware reports Moonraker's base path as /usr/share.
    # Moonraker's bundled update_manager therefore expects /usr/share/scripts/*
    # even though the firmware image does not ship those files.
    mkdir -p /usr/share/scripts

    if [ ! -f /usr/share/scripts/moonraker-requirements.txt ]; then
        cat > /usr/share/scripts/moonraker-requirements.txt << 'EOF'
# Compatibility stub created by Creality Helper Script.
# The K2 firmware bundles Moonraker dependencies in /usr/share/moonraker-env.
EOF
        log_success "Created /usr/share/scripts/moonraker-requirements.txt"
    fi

    if [ ! -f /usr/share/scripts/install-moonraker.sh ]; then
        cat > /usr/share/scripts/install-moonraker.sh << 'EOF'
#!/bin/sh
echo "Moonraker dependency install is managed by Creality firmware on this printer."
exit 0
EOF
        chmod +x /usr/share/scripts/install-moonraker.sh
        log_success "Created /usr/share/scripts/install-moonraker.sh"
    fi

    mkdir -p /mnt/UDISK/printer_data/comms 2>/dev/null || true
}

ensure_update_manager_section() {
    if grep -q "^\[update_manager\]" "$MOONRAKER_CONF" 2>/dev/null; then
        log_info "[update_manager] already present in moonraker.conf"
        return 0
    fi

    cat >> "$MOONRAKER_CONF" << 'EOF'

[update_manager]
channel: dev
enable_auto_refresh: False
enable_system_updates: False
EOF
    log_success "Added [update_manager] to moonraker.conf"
}

verify_update_manager_endpoint() {
    python3 - << 'PYEOF'
import json
import sys
import time
import urllib.request

last_error = None
for _ in range(12):
    try:
        with urllib.request.urlopen("http://127.0.0.1:7125/server/info", timeout=3) as response:
            info = json.loads(response.read().decode())
        components = info.get("result", {}).get("components", [])
        failed = info.get("result", {}).get("failed_components", [])
        with urllib.request.urlopen(
            "http://127.0.0.1:7125/machine/update/status", timeout=5
        ) as response:
            response.read()
        if "update_manager" in components and "update_manager" not in failed:
            print("[OK] Moonraker update_manager endpoint is loaded.")
            sys.exit(0)
        last_error = "update_manager not active in /server/info"
    except Exception as exc:
        last_error = str(exc)
    time.sleep(1)
print("[WARN] Update Manager endpoint was not confirmed yet: %s" % last_error)
PYEOF
}

install_moonraker_extensions() {

    if is_installed "moonraker_extensions"; then
        log_info "Moonraker Extensions is already installed."
        echo ""
        printf "  Reinstall? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return 0
    fi
    echo ""
    log_info "Installing Moonraker Extensions..."
    echo ""

    # 1. Create our moonraker.conf wrapper in /mnt/UDISK
    if [ ! -f "$MOONRAKER_CONF" ]; then
        cat > "$MOONRAKER_CONF" << 'EOF'
# Creality K2 Series - Moonraker extension config
# Managed by Creality Helper Script
# https://github.com/sw3defy/Creality-Helper-Script-Wiki-K2-Plus
#
# This file loads the stock read-only Moonraker config first,
# then extensions added by the helper script appear below.

[include /usr/share/moonraker/moonraker.conf]
EOF
        log_success "Created $MOONRAKER_CONF"
    else
        log_info "moonraker.conf already exists, checking include..."
        # Ensure include is present
        if ! grep -q "include /usr/share/moonraker/moonraker.conf" "$MOONRAKER_CONF"; then
            sed -i "1s/^/[include \/usr\/share\/moonraker\/moonraker.conf]\n\n/" "$MOONRAKER_CONF"
            log_success "Added stock config include to existing moonraker.conf"
        fi
    fi

    # 2. Add compatibility files needed by this firmware's update_manager.
    ensure_update_manager_compat_files

    # 3. Enable Moonraker's update_manager component.
    ensure_update_manager_section

    # 4. Patch S56moonraker to point to our config
    patch_moonraker_startup

    # 5. Avoid Fluidd/Mainsail metadata races while large G-code files are scanned.
    ensure_moonraker_gcode_queue || log_warn "Could not enable queue_gcode_uploads automatically; check Moonraker health."

    # 6. Recognize Creality Cloud Slicer files in Fluidd/Mainsail metadata.
    ensure_creality_cloud_slicer_metadata || log_warn "Cloud Slicer metadata support was not enabled."

    # 7. Keep Moonraker's webcam test compatible with BusyBox netstat.
    sh "$SCRIPT_DIR/scripts/moonraker_webcam_test.sh" install || \
        log_warn "Moonraker webcam-test compatibility was not installed."

    # 8. Restart Moonraker
    restart_moonraker force
    verify_update_manager_endpoint

    mark_installed "moonraker_extensions"
    echo ""
    log_success "Moonraker Extensions installed successfully!"
    echo ""
    log_info "Update Manager is now available in Fluidd under Settings -> Software Updates."
    log_info "System package updates are disabled in Moonraker for safety on this firmware."
    echo ""
}

remove_moonraker_extensions() {
    if ! is_installed "moonraker_extensions"; then
        log_info "Moonraker Extensions is not installed."
        return 0
    fi
    echo ""
    echo ""

    # Only remove the extensions file if it exists
    if [ ! -f "$MOONRAKER_CONF" ]; then
        log_warn "No moonraker.conf found at $MOONRAKER_CONF - nothing to remove."
        unpatch_moonraker_startup
        mark_removed "moonraker_extensions"
        return 0
    fi

    echo ""
    printf "%b\n" "${YELLOW}WARNING: This will remove your moonraker.conf and restore the stock config.${NC}"
    echo "Any other extensions (timelapse, KAMP, etc.) that added sections to"
    echo "moonraker.conf will also stop working until re-installed."
    echo ""
    printf "Are you sure? [y/n]: "
    read confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled."
        return 0
    fi

    # Restore stock moonraker startup
    unpatch_moonraker_startup

    # Archive the config rather than deleting it
    mv "$MOONRAKER_CONF" "${MOONRAKER_CONF}.removed.$(date +%Y%m%d_%H%M%S)"
    log_success "Archived moonraker.conf"

    restart_moonraker force

    mark_removed "moonraker_extensions"
    log_success "Moonraker Extensions removed. Stock config restored."
}

case "$1" in
    install) install_moonraker_extensions ;;
    remove)  remove_moonraker_extensions ;;
    metadata) ensure_creality_cloud_slicer_metadata ;;
    webcam-test-fix) sh "$SCRIPT_DIR/scripts/moonraker_webcam_test.sh" install ;;
    webcam-test-status) sh "$SCRIPT_DIR/scripts/moonraker_webcam_test.sh" status ;;
    *)       echo "Usage: $0 [install|remove|metadata|webcam-test-fix|webcam-test-status]" ;;
esac
