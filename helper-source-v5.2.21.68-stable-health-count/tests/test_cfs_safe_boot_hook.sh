#!/bin/sh
set -eu

PACKAGE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=${TMPDIR:-/tmp}/k2-cfs-safe-boot-test.$$
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

mkdir -p "$TMP_DIR/helper/scripts" "$TMP_DIR/etc/init.d" "$TMP_DIR/etc/rc.d" "$TMP_DIR/backups"

cat > "$TMP_DIR/helper/scripts/system.sh" <<'EOF'
log_error() { echo "ERROR: $*" >&2; }
log_info() { echo "INFO: $*"; }
log_success() { echo "OK: $*"; }
mark_installed() { :; }
mark_removed() { :; }
EOF

cat > "$TMP_DIR/python3" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$TMP_DIR/helper/scripts/S97cfs_safe_monitor" <<'EOF'
#!/bin/sh
case "$1" in
    restart|start|boot) echo "$$" > "$CFS_SAFE_TEST_PID" ;;
    stop) rm -f "$CFS_SAFE_TEST_PID" ;;
    status) [ -f "$CFS_SAFE_TEST_PID" ] && { echo "running: $(cat "$CFS_SAFE_TEST_PID")"; exit 0; } || { echo stopped; exit 1; } ;;
    *) exit 2 ;;
esac
EOF

: > "$TMP_DIR/helper/scripts/cfs_safe_tools.py"
cat > "$TMP_DIR/rc.local" <<'EOF'
#!/bin/sh
echo existing-service
exit 0
EOF
chmod 755 "$TMP_DIR/python3" "$TMP_DIR/helper/scripts/S97cfs_safe_monitor" "$TMP_DIR/rc.local"

export K2_HELPER_DIR="$TMP_DIR/helper"
export CFS_SAFE_SERVICE_INIT="$TMP_DIR/etc/init.d/S97cfs_safe_monitor"
export CFS_SAFE_SERVICE_RC="$TMP_DIR/etc/rc.d/S97cfs_safe_monitor"
export CFS_SAFE_RC_LOCAL="$TMP_DIR/rc.local"
export CFS_SAFE_BOOT_LINE="$TMP_DIR/etc/rc.d/S97cfs_safe_monitor boot &"
export CFS_SAFE_BACKUP_DIR="$TMP_DIR/backups"
export CFS_SAFE_PY="$TMP_DIR/python3"
export CFS_SAFE_TEST_PID="$TMP_DIR/service.pid"

sh "$PACKAGE_DIR/scripts/cfs_safe_tools.sh" install >/dev/null
sh "$PACKAGE_DIR/scripts/cfs_safe_tools.sh" install >/dev/null

[ "$(grep -Fxc "$CFS_SAFE_BOOT_LINE" "$TMP_DIR/rc.local")" -eq 1 ]
[ "$(grep -Fxc '# K2 CFS Safe Tools passive monitor' "$TMP_DIR/rc.local")" -eq 1 ]
sh -n "$TMP_DIR/rc.local"
sh "$PACKAGE_DIR/scripts/cfs_safe_tools.sh" status >/dev/null

sh "$PACKAGE_DIR/scripts/cfs_safe_tools.sh" remove >/dev/null
! grep -Fqx "$CFS_SAFE_BOOT_LINE" "$TMP_DIR/rc.local"
! grep -Fqx '# K2 CFS Safe Tools passive monitor' "$TMP_DIR/rc.local"
grep -Fqx 'echo existing-service' "$TMP_DIR/rc.local"
grep -Fqx 'exit 0' "$TMP_DIR/rc.local"
[ "$(find "$TMP_DIR/backups" -type f | wc -l | awk '{print $1}')" -eq 2 ]

echo "CFS_SAFE_BOOT_HOOK_TEST_OK"
