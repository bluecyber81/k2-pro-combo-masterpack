#!/bin/sh
# mainsail.sh - Install, update, repair, or remove Mainsail on port 4409 for K2 Series printers

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

MAINSAIL_DIR=/usr/share/mainsail
MAINSAIL_URL=https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip
NGINX_CONF=/etc/nginx/nginx.conf

mainsail_version() {
    if [ -f "$MAINSAIL_DIR/.version" ]; then
        cat "$MAINSAIL_DIR/.version"
    elif [ -f "$MAINSAIL_DIR/version" ]; then
        cat "$MAINSAIL_DIR/version"
    elif [ -f "$MAINSAIL_DIR/release_info.json" ]; then
        python3 - "$MAINSAIL_DIR/release_info.json" << 'PYEOF' 2>/dev/null
import json
import sys
print(json.load(open(sys.argv[1])).get("version", "unknown"))
PYEOF
    else
        echo "unknown"
    fi
}

# ── Download helper ───────────────────────────────────────────────────────────

check_download_tool() {
    DOWNLOAD_CMD="python3"
}

download_file() {
    local url="$1"
    local dest="$2"
    python3 - "$url" "$dest" << 'PYEOF'
import sys
import urllib.request

url, dest = sys.argv[1], sys.argv[2]
urllib.request.urlretrieve(url, dest)
print('Downloaded ' + url)
PYEOF
}

# ── Nginx block management ────────────────────────────────────────────────────

check_mainsail_nginx_block() {
    grep -q "listen 4409" "$NGINX_CONF" 2>/dev/null
}

restore_mainsail_nginx_block() {
    if check_mainsail_nginx_block; then
        log_info "Mainsail nginx block (port 4409) already present."
        return 0
    fi

    log_info "Adding Mainsail nginx block on port 4409..."
    backup_nginx_conf

    python3 - << PYEOF
with open('$NGINX_CONF') as f:
    content = f.read()

mainsail_block = """
    server {
        listen 4409 default_server;

        access_log /var/log/nginx/mainsail-access.log;
        error_log /var/log/nginx/mainsail-error.log;

        gzip on;
        gzip_vary on;
        gzip_proxied any;
        gzip_comp_level 4;
        gzip_buffers 16 8k;
        gzip_http_version 1.1;
        gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/json application/xml;

        root /usr/share/mainsail;
        index index.html;
        server_name _;
        client_max_body_size 0;
        proxy_request_buffering off;

        location / {
            try_files \$uri \$uri/ /index.html;
        }
        location = /index.html {
            add_header Cache-Control "no-store, no-cache, must-revalidate";
        }
        location /websocket {
            proxy_pass http://apiserver/websocket;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$http_host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_read_timeout 86400;
        }
        location ~ ^/(printer|api|access|machine|server)/ {
            proxy_pass http://apiserver\$request_uri;
            proxy_set_header Host \$http_host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Scheme \$scheme;
        }
        location /webcam/  { proxy_pass http://mjpgstreamer1/; }
        location /webcam2/ { proxy_pass http://mjpgstreamer2/; }
        location /webcam3/ { proxy_pass http://mjpgstreamer3/; }
        location /webcam4/ { proxy_pass http://mjpgstreamer4/; }
    }
"""

content = content.rstrip()
if not content.endswith('}'):
    raise SystemExit('nginx.conf does not end with a closing brace')
content = content[:-1] + mainsail_block + '\n}'

with open('$NGINX_CONF', 'w') as f:
    f.write(content)
print("Mainsail nginx block added on port 4409.")
PYEOF
    if [ $? -ne 0 ]; then
        log_error "Failed to write Mainsail nginx block."
        return 1
    fi

    if command -v nginx >/dev/null 2>&1; then
        nginx -t || {
            log_error "nginx configuration test failed after restoring Mainsail block."
            return 1
        }
    fi
    restart_nginx force || return 1
    log_success "Mainsail nginx block restored on port 4409."
}

remove_mainsail_nginx_block() {
    if ! check_mainsail_nginx_block; then
        log_info "Mainsail nginx block not found - nothing to remove."
        return 0
    fi

    log_info "Removing Mainsail nginx block from nginx.conf..."
    python3 - << PYEOF
with open("$NGINX_CONF") as f:
    file_lines = f.readlines()
new_lines = []
skip = False
brace_count = 0
for line in file_lines:
    if not skip and "listen 4409" in line:
        for i in range(len(new_lines)-1, -1, -1):
            if new_lines[i].strip().startswith("server"):
                new_lines = new_lines[:i]
                break
        skip = True
        brace_count = 1
        continue
    if skip:
        brace_count += line.count("{") - line.count("}")
        if brace_count <= 0:
            skip = False
        continue
    new_lines.append(line)
with open("$NGINX_CONF", "w") as f:
    f.writelines(new_lines)
print("Mainsail nginx block removed.")
PYEOF
    if [ $? -ne 0 ]; then
        log_error "Failed to remove Mainsail nginx block."
        return 1
    fi
    if command -v nginx >/dev/null 2>&1; then
        nginx -t || {
            log_error "nginx configuration test failed after removing Mainsail block."
            return 1
        }
    fi
    log_success "Mainsail nginx block removed."
}

# ── Status ────────────────────────────────────────────────────────────────────

status_mainsail() {
    echo ""
    echo "Mainsail status:"
    if [ -f "$MAINSAIL_DIR/index.html" ]; then
        log_success "Static files present at $MAINSAIL_DIR"
        echo "  Version: $(mainsail_version)"
        if [ -f "$MAINSAIL_DIR/config.json" ]; then
            echo "  Config: config.json present"
        fi
        if [ -f "$MAINSAIL_DIR/release_info.json" ]; then
            echo "  Release info: $(cat "$MAINSAIL_DIR/release_info.json" 2>/dev/null)"
        fi
    else
        log_warn "Static files NOT found at $MAINSAIL_DIR"
    fi

    if check_mainsail_nginx_block; then
        log_success "Nginx block present (port 4409)"
    else
        log_warn "Nginx block NOT found for port 4409"
    fi

    if pgrep -f nginx > /dev/null; then
        log_success "Nginx is running"
    else
        log_warn "Nginx is NOT running"
    fi
    echo ""
}

# ── Install / update / repair ─────────────────────────────────────────────────

install_mainsail() {
    echo ""

    # Detect whether this is a fresh install or update/repair
    if [ -d "$MAINSAIL_DIR" ] && [ -f "$MAINSAIL_DIR/index.html" ]; then
        printf "%b\n" "${YELLOW}Mainsail is already installed at $MAINSAIL_DIR.${NC}"
        echo "  Current version: $(mainsail_version)"
        echo ""
        echo "  1) Update to the latest version"
        echo "  2) Repair (re-download and reinstall)"
        echo "  3) Restore nginx block only (if port 4409 is broken)"
        echo "  0) Cancel"
        echo ""
        printf "  Enter choice: "
        read subchoice
        case "$subchoice" in
            1|2) : ;;  # continue with full install
            3)  restore_mainsail_nginx_block; return $? ;;
            *)  log_info "Cancelled."; return 0 ;;
        esac
    else
        log_info "Installing Mainsail..."
    fi

    echo ""
    log_info "Downloading latest Mainsail..."
    if ! download_file "$MAINSAIL_URL" /tmp/mainsail.zip; then
        log_error "Download failed. Check your internet connection."
        rm -f /tmp/mainsail.zip
        return 1
    fi
    if [ ! -s /tmp/mainsail.zip ]; then
        log_error "Download failed: mainsail.zip is empty."
        rm -f /tmp/mainsail.zip
        return 1
    fi

    python3 - "$MAINSAIL_DIR" << 'PYEOF' || { log_error "Could not extract Mainsail archive."; rm -f /tmp/mainsail.zip; return 1; }
import os
import sys
import zipfile

dest = sys.argv[1]
os.makedirs(dest, exist_ok=True)
print('Extracting...')
with zipfile.ZipFile('/tmp/mainsail.zip', 'r') as z:
    z.extractall(dest)
os.remove('/tmp/mainsail.zip')
print('Done')
PYEOF

    if [ ! -f "$MAINSAIL_DIR/index.html" ]; then
        log_error "Installation failed - index.html not found after extraction."
        return 1
    fi

    # Ensure nginx block is in place
    restore_mainsail_nginx_block || return 1

    restart_nginx force || return 1

    NEW_VER=$(mainsail_version)
    if [ "$NEW_VER" != "unknown" ]; then
        log_success "Mainsail installed: version $NEW_VER"
    else
        log_success "Mainsail installed successfully."
    fi

    mark_installed "mainsail"
    echo ""
    log_info "Access Mainsail at: http://$(ip route get 1 | grep -o 'src [0-9.]*' | awk '{print $2}'):4409"
    echo ""
}

# ── Remove ────────────────────────────────────────────────────────────────────

remove_mainsail() {
    if ! is_installed "mainsail"; then
        log_info "Mainsail is not installed."
        return 0
    fi
        echo ""
    printf "%b\n" "${YELLOW}WARNING: This removes Mainsail static files and the port 4409 nginx block.${NC}"
    echo "Fluidd on port 4408 is not affected."
    echo ""
    printf "Are you sure? [y/n]: "
    read confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled."
        return 0
    fi

    remove_mainsail_nginx_block || return 1
    rm -rf "$MAINSAIL_DIR"
    restart_nginx force || return 1
    mark_removed "mainsail"
    echo ""
    log_success "Mainsail removed."
    log_info "Fluidd on port 4408 is unaffected."
    echo ""
}

# ── Entry point ───────────────────────────────────────────────────────────────

case "$1" in
    install) install_mainsail ;;
    remove)  remove_mainsail ;;
    restore) restore_mainsail_nginx_block && restart_nginx ;;
    status)  status_mainsail ;;
    *)       echo "Usage: $0 [install|remove|restore|status]" ;;
esac
