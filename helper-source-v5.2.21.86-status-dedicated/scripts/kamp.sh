#!/bin/sh
# kamp.sh - Install/remove Klipper Adaptive Meshing & Purging for K2 Series printers
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

KAMP_DIR=$CONFIG_DIR/KAMP
KAMP_URL=https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging/archive/refs/heads/main.zip

guard_dangerous_install() {
    if [ "$K2PRO_ALLOW_DANGEROUS_MODULES" = "1" ]; then
        return 0
    fi
    echo "BLOCKED: Fresh/direct KAMP install is intentionally blocked on K2 Pro Combo by default because Creality stock macros already include adaptive mesh behavior."
    echo "If KAMP is already detected, the helper menu offers repair/reinstall with backup. For a new manual test, use Expert-Unlock or override only if you understand the risk:"
    echo "  K2PRO_ALLOW_DANGEROUS_MODULES=1 sh $0 install"
    return 1
}

install_kamp() {
    guard_dangerous_install || return 1

    if is_installed "kamp"; then
        log_info "Kamp is already installed."
        echo ""
        printf "  Reinstall? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return 0
    fi
    echo ""
    log_info "Installing Klipper Adaptive Meshing & Purging (KAMP)..."
    echo ""

    if ! is_installed "moonraker_extensions"; then
        log_warn "Moonraker Extensions not installed. Installing now (required for KAMP)..."
        sh "$SCRIPT_DIR/scripts/moonraker.sh" install || {
            log_error "Moonraker Extensions installation failed. KAMP not installed."
            return 1
        }
    fi

    mkdir -p "$KAMP_DIR"

    log_info "Downloading KAMP..."
    python3 << 'PYEOF' || { log_error "KAMP download or extraction failed."; return 1; }
import urllib.request, zipfile, os, shutil, glob
print('Downloading KAMP...')
urllib.request.urlretrieve(
    'https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging/archive/refs/heads/main.zip',
    '/tmp/kamp.zip'
)
print('Extracting...')
with zipfile.ZipFile('/tmp/kamp.zip', 'r') as z:
    z.extractall('/tmp/kamp_extract/')
src = '/tmp/kamp_extract/Klipper-Adaptive-Meshing-Purging-main/Configuration/'
import os
os.makedirs('/mnt/UDISK/printer_data/config/KAMP', exist_ok=True)
files = glob.glob(src + '*.cfg')
if not files:
    raise SystemExit('No KAMP cfg files found in downloaded archive')
for f in files:
    shutil.copy(f, '/mnt/UDISK/printer_data/config/KAMP/')
    print('Copied: ' + os.path.basename(f))
import shutil as sh
sh.rmtree('/tmp/kamp_extract', ignore_errors=True)
os.remove('/tmp/kamp.zip')
print('Done')
PYEOF

    # Write KAMP_Settings.cfg with conservative margins for K2 Series beds.
    cat > "$KAMP_DIR/KAMP_Settings.cfg" << 'EOF'
# KAMP Settings — K2 Series
[include ./Adaptive_Meshing.cfg]
[include ./Line_Purge.cfg]

[gcode_macro _KAMP_Settings]
variable_verbose_enable: True
variable_mesh_margin: 5
variable_fuzz_amount: 0
variable_probe_dock_enable: False
variable_attach_macro: 'Attach_Probe'
variable_detach_macro: 'Dock_Probe'
variable_purge_height: 0.8
variable_tip_distance: 3
variable_purge_margin: 10
variable_purge_amount: 30
variable_flow_rate: 12
variable_start_x: 10
variable_start_y: 10
variable_size: 15
variable_smart_park_height: 5
gcode:
EOF

    add_include_to_printer_cfg "KAMP/KAMP_Settings.cfg"

    # Ensure object processing is enabled without creating duplicate [file_manager] sections.
    if [ -f "$CONFIG_DIR/moonraker.conf" ]; then
        python3 - "$CONFIG_DIR/moonraker.conf" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()

out = []
in_file_manager = False
seen_file_manager = False
seen_object_processing = False
changed = False

for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_file_manager and not seen_object_processing:
            out.append("enable_object_processing: True\n")
            changed = True
        in_file_manager = stripped == "[file_manager]"
        if in_file_manager:
            seen_file_manager = True
            seen_object_processing = False
        out.append(line)
        continue

    if in_file_manager and stripped.startswith("enable_object_processing:"):
        if stripped != "enable_object_processing: True":
            out.append("enable_object_processing: True\n")
            changed = True
        else:
            out.append(line)
        seen_object_processing = True
        continue

    out.append(line)

if in_file_manager and not seen_object_processing:
    out.append("enable_object_processing: True\n")
    changed = True

if not seen_file_manager:
    if out and out[-1].strip():
        out.append("\n")
    out.extend(["[file_manager]\n", "enable_object_processing: True\n"])
    changed = True

if changed:
    with open(path, "w") as f:
        f.writelines(out)
    print("Updated moonraker file_manager object processing")
else:
    print("moonraker file_manager object processing already enabled")
    sys.exit(10)
PYEOF
        rc=$?
        if [ $rc -eq 0 ]; then
            restart_moonraker force
        elif [ $rc -eq 10 ]; then
            :
        else
            log_error "Failed to update moonraker.conf for KAMP object processing."
            return 1
        fi
    fi

    restart_klipper force
    mark_installed "kamp"
    echo ""
    log_success "KAMP installed!"
    log_info "Add BED_MESH_CALIBRATE to your START_PRINT macro."
    log_info "Add LINE_PURGE after heating for a purge line at the print edge."
    echo ""
}

remove_kamp() {
    if ! is_installed "kamp"; then
        log_info "Kamp is not installed."
        return 0
    fi

    printf "%b\n" "${YELLOW}WARNING: This will remove KAMP.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    echo ""
    log_info "Removing KAMP..."
    remove_include_from_printer_cfg "KAMP/KAMP_Settings.cfg"
    rm -rf "$KAMP_DIR"
    restart_klipper force
    mark_removed "kamp"
    log_success "KAMP removed."
    echo ""
}

case "$1" in
    install) install_kamp ;;
    remove)  remove_kamp ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
