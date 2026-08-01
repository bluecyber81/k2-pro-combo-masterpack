#!/bin/sh
# fluidd.sh - Install, repair, or remove Fluidd for K2 Series printers
#
# K2 Series firmware commonly ships with Fluidd at /usr/share/fluidd served on port 4408.
# This script can:
#   install  - download and install the latest Fluidd (replaces stock or broken install)
#   remove   - remove Fluidd static files (nginx block stays, port 4408 will 404)
#   restore  - restore the nginx config to serve Fluidd on port 4408

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

FLUIDD_DIR=/usr/share/fluidd
FLUIDD_API=https://api.github.com/repos/fluidd-core/fluidd/releases/latest
NGINX_CONF=/etc/nginx/nginx.conf

# Stock nginx server block for Fluidd - matches what ships on K2 Series firmware
STOCK_FLUIDD_BLOCK='    server {
        listen 4408 default_server;

        access_log /var/log/nginx/fluidd-access.log;
        error_log /var/log/nginx/fluidd-error.log;

        gzip on;
        gzip_vary on;
        gzip_proxied any;
        gzip_proxied expired no-cache no-store private auth;
        gzip_comp_level 4;
        gzip_buffers 16 8k;
        gzip_http_version 1.1;
        gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/json application/xml;

        root /usr/share/fluidd;
        index index.html;
        server_name _;
        client_max_body_size 0;
        proxy_request_buffering off;

        location / {
            try_files $uri $uri/ /index.html;
        }
        location = /index.html {
            add_header Cache-Control "no-store, no-cache, must-revalidate";
        }
        location /websocket {
            proxy_pass http://apiserver/websocket;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_read_timeout 86400;
        }
        location ~ ^/(printer|api|access|machine|server)/ {
            proxy_pass http://apiserver$request_uri;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Scheme $scheme;
        }
        location /webcam/  { proxy_pass http://mjpgstreamer1/; }
        location /webcam2/ { proxy_pass http://mjpgstreamer2/; }
        location /webcam3/ { proxy_pass http://mjpgstreamer3/; }
        location /webcam4/ { proxy_pass http://mjpgstreamer4/; }
    }'

# ── Check internet ────────────────────────────────────────────────────────────

download_verified_fluidd() {
    local dest="$1"
    local metadata="$2"
    python3 - "$FLUIDD_API" "$dest" "$metadata" << 'PYEOF'
import hashlib
import json
import os
import pathlib
import sys
import urllib.request

api_url, destination, metadata_path = sys.argv[1:]
headers = {"Accept": "application/vnd.github+json", "User-Agent": "K2-Pro-Helper"}
request = urllib.request.Request(api_url, headers=headers)
with urllib.request.urlopen(request, timeout=30) as response:
    release = json.load(response)

asset = next((item for item in release.get("assets", []) if item.get("name") == "fluidd.zip"), None)
if not asset:
    raise SystemExit("Official fluidd.zip asset is missing from the latest release")

digest = asset.get("digest") or ""
if not digest.startswith("sha256:"):
    raise SystemExit("GitHub did not publish a SHA-256 digest for fluidd.zip")
expected = digest.split(":", 1)[1].lower()

part = destination + ".part"
download = urllib.request.Request(asset["browser_download_url"], headers=headers)
sha256 = hashlib.sha256()
try:
    with urllib.request.urlopen(download, timeout=60) as response, open(part, "wb") as output:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            output.write(chunk)
            sha256.update(chunk)
    actual = sha256.hexdigest()
    if actual != expected:
        raise SystemExit("Fluidd SHA-256 mismatch: expected %s, got %s" % (expected, actual))
    os.replace(part, destination)
except BaseException:
    pathlib.Path(part).unlink(missing_ok=True)
    raise

with open(metadata_path, "w", encoding="utf-8") as output:
    output.write("tag=%s\n" % release.get("tag_name", "unknown"))
    output.write("sha256=%s\n" % actual)
    output.write("url=%s\n" % asset["browser_download_url"])
print("Downloaded and verified Fluidd %s (%s)" % (release.get("tag_name", "unknown"), actual))
PYEOF
}

preserve_camera_injection() {
    local old_index="$1"
    local new_index="$2"
    python3 - "$old_index" "$new_index" << 'PYEOF'
import pathlib
import re
import sys

old_path, new_path = map(pathlib.Path, sys.argv[1:])
if not old_path.exists() or not new_path.exists():
    raise SystemExit(0)

old = old_path.read_text(encoding="utf-8")
new = new_path.read_text(encoding="utf-8")
match = re.search(
    r"<!-- K2_CAMERA_KEEPALIVE_V2 -->.*?<!-- /K2_CAMERA_KEEPALIVE_V2 -->",
    old,
    flags=re.DOTALL,
)
if not match:
    print("No managed K2 camera injection found; nothing to preserve")
    raise SystemExit(0)

new = re.sub(
    r"<!-- K2_CAMERA_KEEPALIVE_V2 -->.*?<!-- /K2_CAMERA_KEEPALIVE_V2 -->",
    "",
    new,
    flags=re.DOTALL,
)
if "</body>" not in new:
    raise SystemExit("New Fluidd index.html has no closing body tag")
new = new.replace("</body>", match.group(0) + "\n</body>", 1)
new_path.write_text(new, encoding="utf-8")
print("Preserved managed K2 camera injection")
PYEOF
}

# ── Nginx: check and restore Fluidd block ────────────────────────────────────

check_fluidd_nginx_block() {
    grep -q "listen 4408" "$NGINX_CONF" 2>/dev/null
}

restore_fluidd_nginx_block() {
    if check_fluidd_nginx_block; then
        log_info "Fluidd nginx block (port 4408) already present."
        return 0
    fi

    log_info "Adding Fluidd nginx block on port 4408..."
    backup_nginx_conf

    python3 - << PYEOF
with open('$NGINX_CONF') as f:
    content = f.read()

fluidd_block = """
$STOCK_FLUIDD_BLOCK
"""

# Insert before the closing brace of the http block
content = content.rstrip()
if not content.endswith('}'):
    raise SystemExit('nginx.conf does not end with a closing brace')
content = content[:-1] + fluidd_block + '\n}'

with open('$NGINX_CONF', 'w') as f:
    f.write(content)
print("Fluidd nginx block restored on port 4408.")
PYEOF
    if [ $? -ne 0 ]; then
        log_error "Failed to write Fluidd nginx block."
        return 1
    fi

    if command -v nginx >/dev/null 2>&1; then
        nginx -t || {
            log_error "nginx configuration test failed after restoring Fluidd block."
            return 1
        }
    fi
    restart_nginx force || return 1
}

# ── Install / repair Fluidd ───────────────────────────────────────────────────

install_fluidd() {
    echo ""

    # Detect whether this is a fresh install or a repair
    if [ -d "$FLUIDD_DIR" ] && [ -f "$FLUIDD_DIR/index.html" ]; then
        printf "%b\n" "${YELLOW}Fluidd is already installed at $FLUIDD_DIR.${NC}"
        echo ""
        echo "  1) Update to the latest version"
        echo "  2) Repair (re-download and reinstall current latest)"
        echo "  3) Restore nginx block only (if port 4408 is broken)"
        echo "  0) Cancel"
        echo ""
        printf "  Enter choice: "
        read subchoice
        case "$subchoice" in
            1|2) mark_installed "fluidd_updated" ;;  # continue with install
            3) restore_fluidd_nginx_block; /etc/rc.d/S80nginx restart; log_success "Nginx block restored for port 4408."; return 0 ;;
            *)  log_info "Cancelled."; return 0 ;;
        esac
    else
        log_info "Installing Fluidd..."
    fi

    echo ""
    # Get current installed version if present
    if [ -f "$FLUIDD_DIR/.version" ]; then
        CURRENT_VER=$(cat "$FLUIDD_DIR/.version")
        log_info "Current version: $CURRENT_VER"
    elif [ -f "$FLUIDD_DIR/version" ]; then
        CURRENT_VER=$(cat "$FLUIDD_DIR/version")
        log_info "Current version: $CURRENT_VER"
    fi

    log_info "Downloading and verifying the latest official Fluidd release..."
    rm -f /tmp/fluidd.zip /tmp/fluidd.zip.part /tmp/fluidd.meta
    if ! download_verified_fluidd /tmp/fluidd.zip /tmp/fluidd.meta; then
        log_error "Verified Fluidd download failed. Existing files were not changed."
        rm -f /tmp/fluidd.zip /tmp/fluidd.zip.part /tmp/fluidd.meta
        return 1
    fi

    if [ ! -f /tmp/fluidd.zip ] || [ ! -s /tmp/fluidd.zip ]; then
        log_error "Download failed. Check your internet connection."
        rm -f /tmp/fluidd.zip
        return 1
    fi

    STAGE_DIR=/usr/share/fluidd.new
    ROLLBACK_DIR=/usr/share/fluidd.rollback
    BACKUP_DIR="$SCRIPT_DIR/backups"
    STAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/fluidd-before-update-$STAMP.tar.gz"

    mkdir -p "$BACKUP_DIR"
    if [ -d "$FLUIDD_DIR" ]; then
        log_info "Creating verified Fluidd backup..."
        tar -czf "$BACKUP_FILE" -C /usr/share fluidd || {
            log_error "Could not create Fluidd backup. Existing files were not changed."
            rm -f /tmp/fluidd.zip /tmp/fluidd.meta
            return 1
        }
        tar -tzf "$BACKUP_FILE" >/dev/null || {
            log_error "Fluidd backup verification failed. Existing files were not changed."
            rm -f "$BACKUP_FILE" /tmp/fluidd.zip /tmp/fluidd.meta
            return 1
        }
        sha256sum "$BACKUP_FILE" > "$BACKUP_FILE.sha256"
    fi

    log_info "Staging Fluidd update..."
    rm -rf "$STAGE_DIR" "$ROLLBACK_DIR"
    mkdir -p "$STAGE_DIR"
    python3 - "$STAGE_DIR" << 'PYEOF' || { log_error "Could not extract Fluidd archive."; rm -rf "$STAGE_DIR"; rm -f /tmp/fluidd.zip /tmp/fluidd.meta; return 1; }
import shutil
import sys

shutil.unpack_archive('/tmp/fluidd.zip', sys.argv[1])
PYEOF

    if [ ! -f "$STAGE_DIR/index.html" ] || [ ! -s "$STAGE_DIR/.version" ]; then
        log_error "Staged Fluidd files are incomplete. Existing files were not changed."
        rm -rf "$STAGE_DIR"
        rm -f /tmp/fluidd.zip /tmp/fluidd.meta
        return 1
    fi

    preserve_camera_injection "$FLUIDD_DIR/index.html" "$STAGE_DIR/index.html" || {
        log_error "Could not preserve the K2 camera integration. Existing files were not changed."
        rm -rf "$STAGE_DIR"
        rm -f /tmp/fluidd.zip /tmp/fluidd.meta
        return 1
    }

    # Ensure nginx block is in place
    restore_fluidd_nginx_block || return 1

    if [ -d "$FLUIDD_DIR" ]; then
        mv "$FLUIDD_DIR" "$ROLLBACK_DIR"
    fi
    mv "$STAGE_DIR" "$FLUIDD_DIR"

    if ! restart_nginx force || ! wget -qO- --timeout=8 http://127.0.0.1:4408/ >/dev/null; then
        log_error "Updated Fluidd did not pass its health check; rolling back."
        rm -rf "$FLUIDD_DIR"
        [ -d "$ROLLBACK_DIR" ] && mv "$ROLLBACK_DIR" "$FLUIDD_DIR"
        restart_nginx force >/dev/null 2>&1 || true
        rm -f /tmp/fluidd.zip /tmp/fluidd.meta
        return 1
    fi

    rm -rf "$ROLLBACK_DIR"
    rm -f /tmp/fluidd.zip /tmp/fluidd.meta

    # Show installed version
    if [ -f "$FLUIDD_DIR/.version" ]; then
        NEW_VER=$(cat "$FLUIDD_DIR/.version")
        log_success "Fluidd installed: version $NEW_VER"
    elif [ -f "$FLUIDD_DIR/version" ]; then
        NEW_VER=$(cat "$FLUIDD_DIR/version")
        log_success "Fluidd installed: version $NEW_VER"
    else
        log_success "Fluidd installed successfully."
    fi

    mark_installed "fluidd_updated"
    echo ""
    log_info "Access Fluidd at: http://$(ip route get 1 | grep -o 'src [0-9.]*' | awk '{print $2}'):4408"
    echo ""
}

# ── Remove Fluidd static files ────────────────────────────────────────────────

remove_fluidd() {
    if ! is_installed "fluidd_updated"; then
        log_info "Fluidd Updated is not installed."
        return 0
    fi
        printf "%b\n" "${YELLOW}WARNING: This will restore stock Fluidd nginx configuration.${NC}"
        echo "Fluidd itself will NOT be removed as it is pre-installed on the K2 Series."
    echo ""
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    log_info "Restoring stock Fluidd nginx configuration..."
    restore_fluidd_nginx_block || return 1
    restart_nginx force || return 1
    mark_removed "fluidd_updated"
    echo ""
    log_success "Stock Fluidd nginx configuration restored."
    echo ""
}

# ── Status ────────────────────────────────────────────────────────────────────

status_fluidd() {
    echo ""
    echo "Fluidd status:"
    if [ -f "$FLUIDD_DIR/index.html" ]; then
        log_success "Static files present at $FLUIDD_DIR"
        if [ -f "$FLUIDD_DIR/.version" ]; then
            echo "  Version: $(cat $FLUIDD_DIR/.version)"
        elif [ -f "$FLUIDD_DIR/version" ]; then
            echo "  Version: $(cat $FLUIDD_DIR/version)"
        fi
    else
        log_warn "Static files NOT found at $FLUIDD_DIR"
    fi

    if check_fluidd_nginx_block; then
        log_success "Nginx block present (port 4408)"
    else
        log_warn "Nginx block NOT found for port 4408"
    fi

    if pgrep -f nginx > /dev/null; then
        log_success "Nginx is running"
    else
        log_warn "Nginx is NOT running"
    fi
    echo ""
}

# ── Entry point ───────────────────────────────────────────────────────────────

case "$1" in
    install) install_fluidd ;;
    remove)  remove_fluidd ;;
    restore) restore_fluidd_nginx_block && restart_nginx ;;
    status)  status_fluidd ;;
    *)       echo "Usage: $0 [install|remove|restore|status]" ;;
esac
