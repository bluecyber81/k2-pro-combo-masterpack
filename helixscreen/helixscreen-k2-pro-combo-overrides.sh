#!/bin/sh
set -eu
python3 - <<'PY'
import json
from pathlib import Path

SETTINGS = Path('/home/mks/helixscreen/config/settings.json')
K2_PRESET = Path('/home/mks/helixscreen/assets/config/presets/k2.json')
LAUNCHER = Path('/home/mks/helixscreen/bin/helix-launcher.sh')
CAMERA_FULLSCREEN_XML = Path('/home/mks/helixscreen/ui_xml/components/camera_fullscreen.xml')
SETTING_DROPDOWN_ROW_XML = Path('/home/mks/helixscreen/ui_xml/setting_dropdown_row.xml')

POLICY = (
    'K2 Pro Combo remote display: CFS/BOX is authoritative. '
    'Keep Klipper filament_switch_sensor visible but role=none in Helix to avoid false runout while CFS handles material state.'
)
CAMERA_POLICY = (
    'Keep one camera widget on the main page. Helix snapshot fallback keeps the '
    'stream alive across layout rebuilds, and a second details-page widget can '
    'leave the visible widget stuck on Connecting Camera.'
)


def write_json_if_changed(path: Path, data, original: str) -> bool:
    rendered = json.dumps(data, indent=2, ensure_ascii=False) + '\n'
    if rendered != original:
        path.write_text(rendered)
        return True
    return False


def patch_display(root) -> bool:
    display = root.setdefault('display', {})
    changed = False
    # The Raspberry Pi panel is physically landscape. Creality K2 built-in display
    # presets can write a portrait rotate value that makes this remote display wrong.
    if display.pop('rotate', None) is not None:
        changed = True
    if display.get('rotation_probed') is not True:
        display['rotation_probed'] = True
        changed = True
    # Helix recommends animations off for software-rotated panels;
    # keeping them off also makes the Pi screen feel more responsive.
    if display.get('animations_enabled') is not False:
        display['animations_enabled'] = False
        changed = True
    # Helix accepts fixed timer steps. The previously configured
    # 900/3600 values were snapped on every start and produced warning logs.
    for key, value in {'dim_sec': 600, 'sleep_sec': 1800}.items():
        if display.get(key) != value:
            display[key] = value
            changed = True
    return changed


def patch_camera_layout(printer) -> bool:
    panel_widgets = printer.get('panel_widgets')
    if not isinstance(panel_widgets, dict):
        return False
    home = panel_widgets.get('home')
    if not isinstance(home, dict):
        return False
    pages = home.get('pages')
    if not isinstance(pages, list):
        return False

    changed = False
    found_details_camera = False
    for page in pages:
        if not isinstance(page, dict) or page.get('id') != 'details':
            continue
        widgets = page.get('widgets')
        if not isinstance(widgets, list):
            continue
        filtered_widgets = []
        for widget in widgets:
            if isinstance(widget, dict) and widget.get('id') == 'camera':
                found_details_camera = True
                changed = True
                continue
            filtered_widgets.append(widget)
        if len(filtered_widgets) != len(widgets):
            page['widgets'] = filtered_widgets

    if found_details_camera:
        notes = printer.setdefault('notes', {})
        if notes.get('camera_widget_policy') != CAMERA_POLICY:
            notes['camera_widget_policy'] = CAMERA_POLICY
            changed = True
    return changed


def patch_printer(printer) -> bool:
    if not isinstance(printer, dict):
        return False
    changed = False
    sensors_cfg = printer.setdefault('filament_sensors', {})
    if sensors_cfg.get('master_enabled') is not True:
        sensors_cfg['master_enabled'] = True
        changed = True
    sensors = sensors_cfg.setdefault('sensors', [])
    target = None
    for sensor in sensors:
        if isinstance(sensor, dict) and sensor.get('klipper_name') == 'filament_switch_sensor filament_sensor':
            target = sensor
            break
    if target is None:
        target = {
            'enabled': True,
            'klipper_name': 'filament_switch_sensor filament_sensor',
            'role': 'none',
            'type': 'switch',
        }
        sensors.append(target)
        changed = True
    desired = {
        'enabled': True,
        'klipper_name': 'filament_switch_sensor filament_sensor',
        'role': 'none',
        'type': 'switch',
    }
    for key, value in desired.items():
        if target.get(key) != value:
            target[key] = value
            changed = True
    notes = printer.setdefault('notes', {})
    if notes.get('filament_sensor_policy') != POLICY:
        notes['filament_sensor_policy'] = POLICY
        changed = True
    changed = patch_camera_layout(printer) or changed
    return changed


def patch_settings() -> bool:
    if not SETTINGS.exists():
        return False
    original = SETTINGS.read_text()
    data = json.loads(original)
    changed = patch_display(data)
    printers = data.get('printers')
    if isinstance(printers, dict):
        for printer in printers.values():
            changed = patch_printer(printer) or changed
    return write_json_if_changed(SETTINGS, data, original) if changed else False


def patch_preset() -> bool:
    if not K2_PRESET.exists():
        return False
    original = K2_PRESET.read_text()
    data = json.loads(original)
    changed = patch_display(data)
    changed = patch_printer(data.setdefault('printer', {})) or changed
    return write_json_if_changed(K2_PRESET, data, original) if changed else False


def patch_launcher_redirections() -> bool:
    """Keep expected unprivileged console failures out of the service journal."""
    if not LAUNCHER.exists():
        return False
    original = LAUNCHER.read_text()
    rendered = original.replace(
        "setterm --cursor off 2>/dev/null || printf '\\033[?25l' > /dev/tty1 2>/dev/null || true",
        "setterm --cursor off 2>/dev/null || ( printf '\\033[?25l' > /dev/tty1 ) 2>/dev/null || true",
    ).replace(
        '[ -f "$vtcon" ] && echo 0 > "$vtcon" 2>/dev/null || true',
        '[ -f "$vtcon" ] && ( echo 0 > "$vtcon" ) 2>/dev/null || true',
    )
    if rendered == original:
        return False
    LAUNCHER.write_text(rendered)
    return True


def patch_camera_fullscreen_overlay() -> bool:
    """Hide the v0.99.93 spinner that remains over an already visible live frame."""
    if not CAMERA_FULLSCREEN_XML.exists():
        return False
    original = CAMERA_FULLSCREEN_XML.read_text()
    marker = '<lv_obj name="fullscreen_spinner"'
    if marker not in original or marker + ' hidden="true"' in original:
        return False
    rendered = original.replace(marker, marker + ' hidden="true"', 1)
    CAMERA_FULLSCREEN_XML.write_text(rendered)
    return True


def patch_setting_dropdown_row() -> bool:
    """Avoid the v0.99.94 pipe-expression warning while preserving behavior."""
    if not SETTING_DROPDOWN_ROW_XML.exists():
        return False
    original = SETTING_DROPDOWN_ROW_XML.read_text()
    old = 'hidden_if_prop_eq="$hide_description|true"'
    new = 'hidden="$hide_description"'
    if old not in original:
        return False
    SETTING_DROPDOWN_ROW_XML.write_text(original.replace(old, new, 1))
    return True

changed_settings = patch_settings()
changed_preset = patch_preset()
changed_launcher = patch_launcher_redirections()
changed_camera_overlay = patch_camera_fullscreen_overlay()
changed_dropdown_row = patch_setting_dropdown_row()
print(
    'k2_pro_combo_overrides '
    f'settings_changed={changed_settings} '
    f'preset_changed={changed_preset} '
    f'launcher_changed={changed_launcher} '
    f'camera_overlay_changed={changed_camera_overlay} '
    f'dropdown_row_changed={changed_dropdown_row}'
)
PY
chown mks:mks /home/mks/helixscreen/config/settings.json 2>/dev/null || true
chown mks:mks /home/mks/helixscreen/assets/config/presets/k2.json 2>/dev/null || true
chown mks:mks /home/mks/helixscreen/bin/helix-launcher.sh 2>/dev/null || true
chown mks:mks /home/mks/helixscreen/ui_xml/components/camera_fullscreen.xml 2>/dev/null || true
chown mks:mks /home/mks/helixscreen/ui_xml/setting_dropdown_row.xml 2>/dev/null || true
