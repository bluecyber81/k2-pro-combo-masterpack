#!/bin/sh
set -eu

STAGE=/tmp/k2dash-full-stage
BASE=/opt/k2dash-readonly
STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP=/home/mks/backups/k2dash_full_preinstall_$STAMP
RELEASE=$BASE/releases/full_$STAMP
PREVIOUS_RELEASE=$(readlink -f "$BASE/current")
COMMITTED=0

test -d "$PREVIOUS_RELEASE"
test -f "$STAGE/dist/index.html"
test -f "$STAGE/nginx.conf"
test -f "$STAGE/k2dash-readonly.service"
test -f "$STAGE/rollback-to-readonly.sh.in"

mkdir -p "$BACKUP"
cp -a "$BASE/nginx.conf" "$BACKUP/nginx.conf"
cp -a /etc/systemd/system/k2dash-readonly.service "$BACKUP/k2dash-readonly.service"
printf '%s\n' "$PREVIOUS_RELEASE" >"$BACKUP/previous-release.txt"
systemctl status helixscreen.service --no-pager >"$BACKUP/helixscreen-before.txt" 2>&1 || true
systemctl status k2dash-readonly.service --no-pager >"$BACKUP/k2dash-before.txt" 2>&1 || true
ss -lntp >"$BACKUP/listeners-before.txt" 2>&1 || true

restore_previous() {
    if [ "$COMMITTED" -eq 1 ]; then return; fi
    cp "$BACKUP/nginx.conf" "$BASE/nginx.conf"
    cp "$BACKUP/k2dash-readonly.service" /etc/systemd/system/k2dash-readonly.service
    ln -sfn "$PREVIOUS_RELEASE" "$BASE/current"
    systemctl daemon-reload
    systemctl restart k2dash-readonly.service || true
}
trap restore_previous EXIT INT TERM

mkdir -p "$RELEASE"
cp -a "$STAGE/dist/." "$RELEASE/"
chown -R root:root "$RELEASE"
find "$RELEASE" -type d -exec chmod 755 {} \;
find "$RELEASE" -type f -exec chmod 644 {} \;

cp "$STAGE/nginx.conf" "$BASE/nginx.conf"
cp "$STAGE/k2dash-readonly.service" /etc/systemd/system/k2dash-readonly.service
chmod 644 "$BASE/nginx.conf" /etc/systemd/system/k2dash-readonly.service
ln -sfn "$RELEASE" "$BASE/current"

sed \
    -e "s|@PREVIOUS_RELEASE@|$PREVIOUS_RELEASE|g" \
    -e "s|@BACKUP@|$BACKUP|g" \
    "$STAGE/rollback-to-readonly.sh.in" >"$BASE/rollback-to-readonly.sh"
chmod 755 "$BASE/rollback-to-readonly.sh"

install -d -o mks -g mks -m 755 /run/k2dash-readonly
runuser -u mks -- /usr/sbin/nginx -t \
    -p /run/k2dash-readonly/ -c "$BASE/nginx.conf"

systemctl daemon-reload
systemctl enable k2dash-readonly.service
systemctl restart k2dash-readonly.service
sleep 3

systemctl is-active --quiet k2dash-readonly.service
systemctl is-active --quiet helixscreen.service
curl -fsS http://127.0.0.1:8090/ >/dev/null
curl -fsS http://127.0.0.1:8090/api/moonraker/api/version >/dev/null

COMMITTED=1
trap - EXIT INT TERM
printf 'INSTALL_OK|release=%s|backup=%s|rollback=%s\n' \
    "$RELEASE" "$BACKUP" "$BASE/rollback-to-readonly.sh"
