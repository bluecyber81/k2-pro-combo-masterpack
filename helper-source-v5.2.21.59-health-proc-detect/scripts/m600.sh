#!/bin/sh
# m600.sh - M600 support for K2 printers.
# v5.2.21.57 live-audited-improved provides a K2 Pro Combo/CFS bridge macro that pauses and parks
# without issuing direct CFS load/unload/extrude commands.
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"
M600_CFG=$CONFIG_DIR/m600.cfg

cfs_box_config_detected() {
    [ -f "$CONFIG_DIR/box.cfg" ] && return 0
    grep -qs "^\[include[[:space:]]\+box\.cfg\]" "$CONFIG_DIR/printer.cfg" 2>/dev/null && return 0
    grep -Rqs "^\[box\]" "$CONFIG_DIR" 2>/dev/null && return 0
    grep -Rqs "BOX_LOAD_MATERIAL\|BOX_EXTRUDE_MATERIAL\|BOX_GO_TO_EXTRUDE_POS" "$CONFIG_DIR" 2>/dev/null && return 0
    return 1
}

write_cfs_bridge() {
    cat > "$M600_CFG" <<'EOF_CFG'
# M600 CFS bridge - K2 Pro Combo live-audited-improved
# This deliberately does not send BOX_LOAD_MATERIAL, BOX_EXTRUDE_MATERIAL,
# _CFS_LOAD or _CFS_UNLOAD. It provides an M600-compatible pause/park hook so
# slicers that emit M600 can stop the print while the actual material handling
# remains in the official Creality/CFS/display/slicer workflow.

[gcode_macro M600]
description: CFS-aware M600 pause/park bridge for K2 Pro Combo. No direct CFS movement.
variable_park_x: 10
variable_park_y: 10
variable_z_lift: 10
gcode:
  {% set x = params.X|default(printer['gcode_macro M600'].park_x)|float %}
  {% set y = params.Y|default(printer['gcode_macro M600'].park_y)|float %}
  {% set z_lift = params.Z|default(printer['gcode_macro M600'].z_lift)|float %}
  SAVE_GCODE_STATE NAME=M600_CFS_BRIDGE_STATE
  {% if 'xyz' in printer.toolhead.homed_axes %}
    {% set z_now = printer.toolhead.position.z|float %}
    {% set z_target = [z_now + z_lift, printer.toolhead.axis_maximum.z|float]|min %}
    G90
    G1 Z{z_target} F600
    G1 X{x} Y{y} F12000
  {% else %}
    {action_respond_info("M600 CFS bridge: axes not homed, skipping park move.")}
  {% endif %}
  {% if 'PAUSE_BASE' in printer.gcode.commands %}
    PAUSE_BASE
  {% else %}
    PAUSE
  {% endif %}
  RESTORE_GCODE_STATE NAME=M600_CFS_BRIDGE_STATE MOVE=0
  {action_respond_info("M600 CFS bridge: print paused. Use Creality/CFS/display or slicer toolchange workflow for filament movement, then RESUME.")}

[gcode_macro M600_CFS_HELP]
description: Explain K2 Pro Combo M600 bridge behavior.
gcode:
  {action_respond_info("M600 is installed as a CFS-aware pause/park bridge. It does not send direct CFS load/unload/extrude commands.")}
EOF_CFG
}

write_non_cfs_m600() {
    cat > "$M600_CFG" <<'EOF_CFG'
# M600 Filament Change — K2 without CFS/Box
# For K2 Pro Combo/CFS use the CFS bridge mode instead.

[gcode_macro M600]
description: Manual filament change for printers WITHOUT CFS/Box only.
variable_park_x: 10
variable_park_y: 10
variable_retract: 5
gcode:
  {% set cfs_present = printer.box is defined %}
  {% if cfs_present %}
    {action_respond_info("M600 blocked at runtime: CFS/Box is present. Install the CFS bridge mode if you need an M600 pause hook.")}
  {% else %}
  {% set x = printer['gcode_macro M600'].park_x %}
  {% set y = printer['gcode_macro M600'].park_y %}
  {% set e = printer['gcode_macro M600'].retract %}

  SAVE_GCODE_STATE NAME=M600_STATE

  {% if printer.extruder.can_extrude %}
    G91
    G1 E-{e} F3600
    G90
  {% endif %}

  {% set z_pos = printer.toolhead.position.z %}
  {% set z_target = [z_pos + 10, printer.toolhead.axis_maximum.z]|min %}
  G90
  G1 Z{z_target} F600
  G1 X{x} Y{y} F12000

  {% set temp = printer.extruder.target %}
  M104 S{[temp - 20, 160]|max}

  {% if 'PAUSE_BASE' in printer.gcode.commands %}
    PAUSE_BASE
  {% else %}
    PAUSE
  {% endif %}

  {action_respond_info("M600: Filament change paused. Swap filament then RESUME.")}
  {% endif %}

[gcode_macro FILAMENT_LOAD]
description: Manual filament load for printers WITHOUT CFS/Box only.
gcode:
  {% if printer.box is defined %}
    {action_respond_info("FILAMENT_LOAD blocked: CFS/Box is present. Use Creality/CFS workflow.")}
  {% else %}
  {% set temp = params.TEMP|default(200)|float %}
  M109 S{temp}
  G91
  G1 E80 F300
  G1 E30 F150
  G90
  {action_respond_info("Filament loaded.")}
  {% endif %}

[gcode_macro FILAMENT_UNLOAD]
description: Manual filament unload for printers WITHOUT CFS/Box only.
gcode:
  {% if printer.box is defined %}
    {action_respond_info("FILAMENT_UNLOAD blocked: CFS/Box is present. Use Creality/CFS workflow.")}
  {% else %}
  {% set temp = params.TEMP|default(200)|float %}
  M109 S{temp}
  G91
  G1 E5 F300
  G1 E-80 F1800
  G90
  {action_respond_info("Filament unloaded.")}
  {% endif %}
EOF_CFG
}

install_m600() {
    cfs_mode=0
    if cfs_box_config_detected; then
        if [ "$K2PRO_ALLOW_CFS_M600" = "1" ] || [ "$K2PRO_FULL_CONTROL" = "1" ]; then
            cfs_mode=1
        else
            echo ""
            log_error "M600 standard install blocked because CFS/Box configuration was detected."
            echo "Use CFS bridge mode instead:"
            echo "  K2PRO_ALLOW_CFS_M600=1 sh $0 install"
            echo "or use helper menu: Expert Full-Control -> M600 CFS bridge."
            return 1
        fi
    fi

    if is_installed "m600_support"; then
        log_info "M600 Support is already installed."
        echo ""
        printf "  Reinstall? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return 0
    fi

    echo ""
    if [ "$cfs_mode" -eq 1 ]; then
        log_info "Installing M600 CFS-aware pause/park bridge for K2 Pro Combo..."
        write_cfs_bridge
    else
        log_info "Installing M600 Support for NON-CFS manual single-filament use..."
        write_non_cfs_m600
    fi
    add_include_to_printer_cfg "m600.cfg"
    restart_klipper force
    mark_installed "m600_support"
    echo ""
    if [ "$cfs_mode" -eq 1 ]; then
        log_success "M600 CFS bridge installed. It pauses/parks but does not directly move CFS filament."
    else
        log_success "M600 Support installed for non-CFS manual single-filament use."
    fi
    echo ""
}

remove_m600() {
    if ! is_installed "m600_support" && [ ! -f "$M600_CFG" ]; then
        log_info "M600 Support is not installed."
        return 0
    fi

    printf "%b\n" "${YELLOW}WARNING: This will remove M600 Support.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    remove_include_from_printer_cfg "m600.cfg"
    rm -f "$M600_CFG"
    restart_klipper force
    mark_removed "m600_support"
    log_success "M600 Support removed."
}

case "$1" in
    install) install_m600 ;;
    remove)  remove_m600 ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
