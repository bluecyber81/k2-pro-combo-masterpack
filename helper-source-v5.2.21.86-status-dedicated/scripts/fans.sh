#!/bin/sh
# fans.sh - Install/remove Fans Control Macros for K2 Series printers

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

FANS_CFG=$CONFIG_DIR/fans_control.cfg

install_fans() {

    if is_installed "fans_control_macros"; then
        log_info "Fans Control Macros is already installed."
        echo ""
        printf "  Reinstall? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return 0
    fi
    echo ""
    log_info "Installing Fans Control Macros..."
    echo ""

    cat > "$FANS_CFG" << 'EOF'
# Fans Control Macros — K2 Series
# Managed by Creality Helper Script
# K2 Plus exposes part cooling as output_pin fan0/fan0_en and aux fan as fan2.
# K2 Pro firmware can differ, so these macros check for the pins before use.

# ── Save / Restore fan state ──────────────────────────────────────────────────

[gcode_macro SAVE_FANS]
description: Save current fan speeds
variable_fan0_speed: 0
variable_fan2_speed: 0
gcode:
  {% if printer['output_pin fan0'] is defined %}
    SET_GCODE_VARIABLE MACRO=SAVE_FANS VARIABLE=fan0_speed VALUE={printer['output_pin fan0'].value}
  {% endif %}
  {% if printer['output_pin fan2'] is defined %}
    SET_GCODE_VARIABLE MACRO=SAVE_FANS VARIABLE=fan2_speed VALUE={printer['output_pin fan2'].value}
  {% endif %}

[gcode_macro RESTORE_FANS]
description: Restore previously saved fan speeds
gcode:
  {% set s = printer['gcode_macro SAVE_FANS'] %}
  {% set scale0 = printer.configfile.settings['output_pin fan0'].scale|default(1)|float if printer['output_pin fan0'] is defined else 1 %}
  {% set scale2 = printer.configfile.settings['output_pin fan2'].scale|default(1)|float if printer['output_pin fan2'] is defined else 1 %}
  {% set fan0_value = s.fan0_speed if scale0 > 1 else (s.fan0_speed * 255) %}
  {% set fan2_value = s.fan2_speed if scale2 > 1 else (s.fan2_speed * 255) %}
  SET_FAN0 S={fan0_value|int}
  {% if printer['output_pin fan2'] is defined %}
    SET_FAN2 S={fan2_value|int}
  {% endif %}

# ── Part cooling fan (fan0) ───────────────────────────────────────────────────

[gcode_macro SET_FAN0]
description: Set part cooling fan speed. S=0-255
gcode:
  {% set speed = params.S|default(0)|int %}
  {% set pwm = (speed / 255.0)|round(4) %}
  {% if printer['output_pin fan0'] is defined %}
    {% set scale = printer.configfile.settings['output_pin fan0'].scale|default(1)|float %}
    {% if printer['output_pin fan0_en'] is defined %}
      SET_PIN PIN=fan0_en VALUE={% if speed > 0 %}1{% else %}0{% endif %}
    {% endif %}
    {% if scale > 1 %}
      SET_PIN PIN=fan0 VALUE={speed}
    {% else %}
      SET_PIN PIN=fan0 VALUE={pwm}
    {% endif %}
  {% else %}
    M106 S{speed}
  {% endif %}

# ── Aux fan (fan2) ────────────────────────────────────────────────────────────

[gcode_macro SET_FAN2]
description: Set aux fan speed. S=0-255
gcode:
  {% set speed = params.S|default(0)|int %}
  {% set pwm = (speed / 255.0)|round(4) %}
  {% if printer['output_pin fan2'] is defined %}
    {% set scale = printer.configfile.settings['output_pin fan2'].scale|default(1)|float %}
    {% if scale > 1 %}
      SET_PIN PIN=fan2 VALUE={speed}
    {% else %}
      SET_PIN PIN=fan2 VALUE={pwm}
    {% endif %}
  {% else %}
    {action_respond_info("Aux fan output_pin fan2 is not configured; skipping.")}
  {% endif %}

# ── Turn off all output fans ──────────────────────────────────────────────────

[gcode_macro FANS_OFF]
description: Turn off all output fans (does not affect hotend_fan auto-control)
gcode:
  SET_FAN0 S=0
  SET_FAN2 S=0
EOF

    add_include_to_printer_cfg "fans_control.cfg"
    restart_klipper force

    mark_installed "fans_control_macros"
    echo ""
    log_success "Fans Control Macros installed!"
    echo ""
    log_info "Available macros: SET_FAN0, SET_FAN2, FANS_OFF, SAVE_FANS, RESTORE_FANS"
    log_info "Chamber macros are provided by Useful Macros."
    echo ""
}

remove_fans() {
    if ! is_installed "fans_control_macros"; then
        log_info "Fans Control Macros is not installed."
        return 0
    fi

    printf "%b\n" "${YELLOW}WARNING: This will remove Fans Control Macros.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    echo ""
    log_info "Removing Fans Control Macros..."
    remove_include_from_printer_cfg "fans_control.cfg"
    rm -f "$FANS_CFG"
    restart_klipper force
    mark_removed "fans_control_macros"
    log_success "Fans Control Macros removed."
    echo ""
}

case "$1" in
    install) install_fans ;;
    remove)  remove_fans ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
