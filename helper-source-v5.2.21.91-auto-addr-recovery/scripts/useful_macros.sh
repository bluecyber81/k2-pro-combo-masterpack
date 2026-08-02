#!/bin/sh
# useful_macros.sh - Full useful macros suite for K2 Series printers
# Includes all K1 macros adapted for K2 hardware + K2-specific additions

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

MACROS_CFG=$CONFIG_DIR/useful_macros.cfg

install_useful_macros() {

    if is_installed "useful_macros"; then
        log_info "Useful Macros is already installed."
        echo ""
        printf "  Reinstall? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return 0
    fi
    echo ""
    log_info "Installing Useful Macros..."
    echo ""

    cat > "$MACROS_CFG" << 'EOF'
# Useful Macros — K2 Series
# Managed by Creality Helper Script
# https://github.com/sw3defy/Creality-Helper-Script-K2-Plus
#
# Included macros:
#   PID_BED, PID_HOTEND, PID_CHAMBER (SAVE_CONFIG is blocked when CFS auto_addr is pending)
#   BED_LEVELING, Z_TILT_CALIBRATE
#   WARMUP (movement stress test)
#   CHAMBER_HEAT, CHAMBER_COOL, CHAMBER_STATUS
#   KLIPPER_BACKUP_CONFIG, KLIPPER_RESTORE_CONFIG
#   MOONRAKER_BACKUP_DATABASE, MOONRAKER_RESTORE_DATABASE
#   RELOAD_CAMERA
#   SET_PRINT_STATS_INFO

# ═════════════════════════════════════════════════════════════════════════════
# PID CALIBRATION
# ═════════════════════════════════════════════════════════════════════════════

[gcode_macro PID_HOTEND]
description: PID calibration for the hotend. Usage: PID_HOTEND TEMP=220
gcode:
  {% set temp = params.TEMP|default(220)|float %}
  {action_respond_info("Starting hotend PID calibration at %.0f°C..." % temp)}
  {action_respond_info("This will take several minutes. Do not interrupt.")}
  PID_CALIBRATE HEATER=extruder TARGET={temp}
  {% set pending = printer.configfile.save_config_pending_items|default({}) %}
  {% if 'auto_addr' in pending %}
    {action_respond_info("Hotend PID calibration complete, but SAVE_CONFIG was blocked because CFS auto_addr is pending. Restart Klipper/Firmware first, then repeat/save only when auto_addr is clear.")}
  {% else %}
    SAVE_CONFIG
    {action_respond_info("Hotend PID calibration complete. Config saved.")}
  {% endif %}

[gcode_macro PID_BED]
description: PID calibration for the heated bed. Usage: PID_BED TEMP=60
gcode:
  {% set temp = params.TEMP|default(60)|float %}
  {action_respond_info("Starting bed PID calibration at %.0f°C..." % temp)}
  {action_respond_info("This will take several minutes. Do not interrupt.")}
  PID_CALIBRATE HEATER=heater_bed TARGET={temp}
  {% set pending = printer.configfile.save_config_pending_items|default({}) %}
  {% if 'auto_addr' in pending %}
    {action_respond_info("Bed PID calibration complete, but SAVE_CONFIG was blocked because CFS auto_addr is pending. Restart Klipper/Firmware first, then repeat/save only when auto_addr is clear.")}
  {% else %}
    SAVE_CONFIG
    {action_respond_info("Bed PID calibration complete. Config saved.")}
  {% endif %}

[gcode_macro PID_CHAMBER]
description: Tune the chamber heater watermark. Usage: PID_CHAMBER TEMP=45
gcode:
  {% set temp = params.TEMP|default(45)|float %}
  {% if printer['heater_generic chamber_heater'] is defined %}
    {action_respond_info("Heating chamber to %.0f°C for thermal soak observation..." % temp)}
    SET_HEATER_TEMPERATURE HEATER=chamber_heater TARGET={temp}
    TEMPERATURE_WAIT SENSOR="heater_generic chamber_heater" MINIMUM={temp - 2}
    {action_respond_info("Chamber reached %.0f°C. Note: chamber_heater uses watermark control, not PID." % temp)}
    {action_respond_info("Adjust max_delta in printer.cfg [verify_heater chamber_heater] if needed.")}
  {% else %}
    {action_respond_info("PID_CHAMBER skipped: chamber_heater is not configured.")}
  {% endif %}

# ═════════════════════════════════════════════════════════════════════════════
# BED LEVELING
# ═════════════════════════════════════════════════════════════════════════════

[gcode_macro BED_LEVELING]
description: Full bed leveling sequence with Z-tilt and mesh. Usage: BED_LEVELING BED_TEMP=60 EXTRUDER_TEMP=150
gcode:
  {% set bed_temp      = params.BED_TEMP|default(60)|float %}
  {% set extruder_temp = params.EXTRUDER_TEMP|default(150)|float %}

  {action_respond_info("Starting bed leveling sequence...")}
  {action_respond_info("Bed: %.0f°C  Nozzle: %.0f°C" % (bed_temp, extruder_temp))}

  G28
  M140 S{bed_temp}
  M109 S{extruder_temp}
  M190 S{bed_temp}

  {% if printer.configfile.settings.z_tilt is defined %}
    {action_respond_info("Running Z-tilt adjustment...")}
    Z_TILT_ADJUST
  {% else %}
    {action_respond_info("Z_TILT_ADJUST skipped: [z_tilt] is not configured.")}
  {% endif %}

  {action_respond_info("Running full 9x9 bed mesh...")}
  BED_MESH_CALIBRATE PROFILE=default

  {% set pending = printer.configfile.save_config_pending_items|default({}) %}
  {% if 'auto_addr' in pending %}
    {action_respond_info("Bed leveling complete, but SAVE_CONFIG was blocked because CFS auto_addr is pending. Restart Klipper/Firmware first, then rerun/save only when auto_addr is clear.")}
  {% else %}
    SAVE_CONFIG
    {action_respond_info("Bed leveling complete. Mesh saved as 'default'.")}
  {% endif %}

[gcode_macro Z_TILT_CALIBRATE]
description: Run Z-tilt adjustment only (no bed mesh). Home first if needed.
gcode:
  {% if printer.toolhead.homed_axes != "xyz" %}
    G28
  {% endif %}
  {% if printer.configfile.settings.z_tilt is defined %}
    {action_respond_info("Running Z-tilt adjustment...")}
    Z_TILT_ADJUST
    {action_respond_info("Z-tilt complete.")}
  {% else %}
    {action_respond_info("Z_TILT_ADJUST skipped: [z_tilt] is not configured.")}
  {% endif %}

# ═════════════════════════════════════════════════════════════════════════════
# WARMUP (movement stress test — adapted from K1 for CoreXY / K2 Series)
# ═════════════════════════════════════════════════════════════════════════════

[gcode_macro WARMUP]
description: Movement warm-up to seat bearings and rods. Usage: WARMUP LOOPS=10 ACCEL=5000
variable_margin: 5
gcode:
  {% set loops = params.LOOPS|default(10)|int %}
  {% set accel = params.ACCEL|default(5000)|int %}
  {% set margin = params.MARGIN|default(printer['gcode_macro WARMUP'].margin)|float %}
  {% set start_x = params.START_X|default(margin)|float %}
  {% set start_y = params.START_Y|default(margin)|float %}
  {% set end_x = params.END_X|default(printer.toolhead.axis_maximum.x - margin)|float %}
  {% set end_y = params.END_Y|default(printer.toolhead.axis_maximum.y - margin)|float %}

  {action_respond_info("Starting warmup: %d loops at %d mm/s² acceleration" % (loops, accel))}
  {action_respond_info("This moves the toolhead across the full bed. Make sure it is clear.")}

  {% if printer.toolhead.homed_axes != "xyz" %}
    G28
  {% endif %}

  ; Save current acceleration
  {% set orig_accel = printer.toolhead.max_accel %}
  SET_VELOCITY_LIMIT ACCEL={accel}

  G90
  G1 F12000

  {% for i in range(loops) %}
    G1 X{start_x} Y{start_y}
    G1 X{end_x}   Y{start_y}
    G1 X{end_x}   Y{end_y}
    G1 X{start_x} Y{end_y}
    G1 X{start_x} Y{start_y}
    G1 X{end_x}   Y{end_y}
    G1 X{start_x} Y{end_y}
    G1 X{end_x}   Y{start_y}
  {% endfor %}

  ; Restore original acceleration
  SET_VELOCITY_LIMIT ACCEL={orig_accel}

  G1 X{((start_x + end_x) / 2)|int} Y{((start_y + end_y) / 2)|int}
  {action_respond_info("Warmup complete. %d loops done." % loops)}

# ═════════════════════════════════════════════════════════════════════════════
# CHAMBER CONTROL
# ═════════════════════════════════════════════════════════════════════════════

[gcode_macro CHAMBER_HEAT]
description: Set chamber heater target. Use WAIT=1 to wait for temp. Usage: CHAMBER_HEAT TARGET=45 WAIT=1
gcode:
  {% set target = params.TARGET|default(0)|float %}
  {% set wait   = params.WAIT|default(0)|int %}
  {% if printer['heater_generic chamber_heater'] is defined %}
    SET_HEATER_TEMPERATURE HEATER=chamber_heater TARGET={target}
    {% if wait == 1 and target > 0 %}
      {action_respond_info("Waiting for chamber to reach %.0f°C..." % target)}
      TEMPERATURE_WAIT SENSOR="heater_generic chamber_heater" MINIMUM={target - 3}
      {action_respond_info("Chamber reached target: %.0f°C" % target)}
    {% endif %}
  {% else %}
    {action_respond_info("CHAMBER_HEAT skipped: chamber_heater is not configured.")}
  {% endif %}

[gcode_macro CHAMBER_COOL]
description: Disable chamber heater and run cooling fan at full speed
gcode:
  {% if printer['heater_generic chamber_heater'] is defined %}
    SET_HEATER_TEMPERATURE HEATER=chamber_heater TARGET=0
  {% endif %}
  {% if printer['temperature_fan chamber_fan'] is defined %}
    SET_TEMPERATURE_FAN_TARGET TEMPERATURE_FAN=chamber_fan TARGET=20
    {action_respond_info("Chamber cooling: heater off, cooling fan running.")}
  {% else %}
    {action_respond_info("Chamber cooling: heater off. chamber_fan is not configured.")}
  {% endif %}

[gcode_macro CHAMBER_STATUS]
description: Print current chamber temperature and target
gcode:
  {% if printer['heater_generic chamber_heater'] is defined %}
    {% set temp   = printer['heater_generic chamber_heater'].temperature %}
    {% set target = printer['heater_generic chamber_heater'].target %}
    {action_respond_info("Chamber: %.1f°C  /  target: %.1f°C" % (temp, target))}
  {% else %}
    {action_respond_info("CHAMBER_STATUS skipped: chamber_heater is not configured.")}
  {% endif %}

# ═════════════════════════════════════════════════════════════════════════════
EOF
# BACKUP & RESTORE (from Fluidd/Mainsail console)
# ═════════════════════════════════════════════════════════════════════════════



    add_include_to_printer_cfg "useful_macros.cfg"
    restart_klipper force

    mark_installed "useful_macros"
    echo ""
    log_success "Useful Macros installed!"
    echo ""
    echo "  Available macros:"
    printf "%b\n" "  ${GREEN}PID:${NC}          PID_HOTEND, PID_BED, PID_CHAMBER"
    printf "%b\n" "  ${GREEN}Leveling:${NC}     BED_LEVELING, Z_TILT_CALIBRATE"
    printf "%b\n" "  ${GREEN}Warmup:${NC}       WARMUP [LOOPS=10] [ACCEL=5000]"
    printf "%b\n" "  ${GREEN}Chamber:${NC}      CHAMBER_HEAT, CHAMBER_COOL, CHAMBER_STATUS"
    printf "%b\n" "  ${GREEN}Note:${NC}         START_PRINT/END_PRINT/CFS macros are not replaced."
    printf "%b\n" "  ${GREEN}Safety:${NC}       SAVE_CONFIG is blocked if CFS auto_addr is pending."
    echo ""
    log_info "Stock Creality START_PRINT, END_PRINT, PAUSE, RESUME, and CANCEL_PRINT are left unchanged."
    echo ""
}

remove_useful_macros() {
    if ! is_installed "useful_macros"; then
        log_info "Useful Macros is not installed."
        return 0
    fi

    printf "%b\n" "${YELLOW}WARNING: This will remove Useful Macros.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    echo ""
    log_info "Removing Useful Macros..."
    remove_include_from_printer_cfg "useful_macros.cfg"
    rm -f "$MACROS_CFG"
    restart_klipper force
    mark_removed "useful_macros"
    log_success "Useful Macros removed."
    echo ""
}

case "$1" in
    install) install_useful_macros ;;
    remove)  remove_useful_macros ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
