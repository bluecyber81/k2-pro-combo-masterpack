#!/bin/sh
# entware.sh - Install Entware package manager on K2 Series printers
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

ENTWARE_INSTALLER_URL=http://bin.entware.net/armv7sf-k2.6/installer/generic.sh
DUMMY_WGET_URL=https://github.com/vsevolod-volkov/K2Plus-entware/raw/refs/heads/main/wget
ENTWARE_INSTALLER=/tmp/entware_generic.sh
RC_LOCAL=/etc/rc.local
BASE_PACKAGES="nano htop git git-http curl openssh-sftp-server"
DIAG_PACKAGES="bash bc xz file sqlite3-cli jq tree diffutils coreutils-stat coreutils-timeout"
ALL_PACKAGES="$BASE_PACKAGES $DIAG_PACKAGES"

patch_rc_local_entware() {
    python3 << 'PYEOF'
import os
import shutil
import time

path = '/etc/rc.local'
block = (
    '# Entware\n'
    '[ -f /opt/etc/init.d/rc.unslung ] && /opt/etc/init.d/rc.unslung start\n'
    'export PATH=/opt/bin:/opt/sbin:$PATH\n'
)

if os.path.exists(path):
    shutil.copy(path, f'{path}.bak.entware.{int(time.time())}')
    with open(path) as f:
        content = f.read()
else:
    content = '#!/bin/sh\nexit 0\n'

if 'rc.unslung' in content or '/opt/bin:/opt/sbin' in content:
    print('Entware already present in rc.local')
else:
    if 'exit 0' in content:
        content = content.replace('exit 0', block + 'exit 0', 1)
    else:
        if not content.endswith('\n'):
            content += '\n'
        content += block + 'exit 0\n'
    with open(path, 'w') as f:
        f.write(content)
    print('Added Entware to rc.local')
PYEOF
}

patch_rc_local_sftp() {
    python3 << 'PYEOF'
import os
import shutil
import time

path = '/etc/rc.local'
line = 'ln -sf /opt/libexec/sftp-server /usr/libexec/sftp-server 2>/dev/null\n'

if os.path.exists(path):
    shutil.copy(path, f'{path}.bak.sftp.{int(time.time())}')
    with open(path) as f:
        content = f.read()
else:
    content = '#!/bin/sh\nexit 0\n'

if '/opt/libexec/sftp-server' in content:
    print('SFTP link already present in rc.local')
elif '# Entware\n' in content:
    content = content.replace('# Entware\n', '# Entware\n' + line, 1)
    with open(path, 'w') as f:
        f.write(content)
    print('Added SFTP link to Entware rc.local block')
elif 'exit 0' in content:
    content = content.replace('exit 0', line + 'exit 0', 1)
    with open(path, 'w') as f:
        f.write(content)
    print('Added SFTP link before exit 0')
else:
    if not content.endswith('\n'):
        content += '\n'
    content += line + 'exit 0\n'
    with open(path, 'w') as f:
        f.write(content)
    print('Added SFTP link to rc.local')
PYEOF
}

link_entware_sftp() {
    if [ -x /usr/libexec/sftp-server ] || [ -x /usr/lib/sftp-server ]; then
        log_info "A system SFTP server already exists; keeping the stock server in place."
        return 0
    fi
    if [ ! -x /opt/libexec/sftp-server ]; then
        log_warn "Entware SFTP server is not installed; skipping SFTP symlink."
        return 0
    fi
    mkdir -p /usr/libexec
    ln -sf /opt/libexec/sftp-server /usr/libexec/sftp-server
    patch_rc_local_sftp
}

patch_profile_entware() {
    python3 << 'PYEOF'
import os
import shutil
import time

path = '/etc/profile'
block = '\n# Entware tools\nexport PATH=/opt/bin:/opt/sbin:$PATH\n'

if os.path.exists(path):
    shutil.copy(path, f'{path}.bak.entware.{int(time.time())}')
    with open(path) as f:
        content = f.read()
else:
    content = ''

if '/opt/bin:/opt/sbin' in content:
    print('Entware PATH already present in /etc/profile')
else:
    if content and not content.endswith('\n'):
        content += '\n'
    content += block
    with open(path, 'w') as f:
        f.write(content)
    print('Added Entware PATH to /etc/profile')
PYEOF
}

link_entware_tools() {
    mkdir -p /usr/bin /usr/libexec
    for item in \
        /opt/bin/opkg:/usr/bin/opkg \
        /opt/bin/bash:/usr/bin/bash \
        /opt/bin/bc:/usr/bin/bc \
        /opt/bin/xz:/usr/bin/xz \
        /opt/bin/file:/usr/bin/file \
        /opt/bin/nano:/usr/bin/nano \
        /opt/bin/git:/usr/bin/git \
        /opt/bin/curl:/usr/bin/curl \
        /opt/bin/sqlite3:/usr/bin/sqlite3 \
        /opt/bin/jq:/usr/bin/jq \
        /opt/sbin/tree:/usr/bin/tree \
        /opt/bin/diff:/usr/bin/diff \
        /opt/libexec/sftp-server:/usr/bin/sftp-server \
        /opt/libexec/sftp-server:/usr/libexec/sftp-server
    do
        src="${item%%:*}"
        dst="${item#*:}"
        [ -x "$src" ] && ln -sf "$src" "$dst"
    done
}

entware_status() {
    export PATH=/opt/bin:/opt/sbin:$PATH
    echo ""
    echo "Entware status:"
    if [ -x /opt/bin/opkg ]; then
        echo "  opkg: installed ($(/opt/bin/opkg --version 2>/dev/null | head -1))"
    else
        echo "  opkg: missing"
    fi
    echo ""
    echo "Tool check:"
    for cmd in opkg bash bc xz file nano git curl sftp-server sqlite3 jq tree diff wget ss unzip base64 timeout; do
        printf "  %-12s " "$cmd"
        command -v "$cmd" || echo "MISSING"
    done
}

unpatch_rc_local_entware() {
    python3 << 'PYEOF'
import os
import shutil
import time

path = '/etc/rc.local'
block = (
    '# Entware\n'
    '[ -f /opt/etc/init.d/rc.unslung ] && /opt/etc/init.d/rc.unslung start\n'
    'export PATH=/opt/bin:/opt/sbin:$PATH\n'
)
sftp_line = 'ln -sf /opt/libexec/sftp-server /usr/libexec/sftp-server 2>/dev/null\n'

if not os.path.exists(path):
    raise SystemExit(0)

shutil.copy(path, f'{path}.bak.entware_remove.{int(time.time())}')
with open(path) as f:
    content = f.read()
content = content.replace(sftp_line, '')
content = content.replace(block, '')
with open(path, 'w') as f:
    f.write(content)
print('Removed Entware entries from rc.local')
PYEOF
}

unpatch_profile_entware() {
    python3 << 'PYEOF'
import os
import shutil
import time

path = '/etc/profile'
if not os.path.exists(path):
    raise SystemExit(0)

shutil.copy(path, f'{path}.bak.entware_remove.{int(time.time())}')
with open(path) as f:
    content = f.read()
content = content.replace('\n# Entware tools\nexport PATH=/opt/bin:/opt/sbin:$PATH\n', '\n')
content = content.replace('# Entware tools\nexport PATH=/opt/bin:/opt/sbin:$PATH\n', '')
with open(path, 'w') as f:
    f.write(content)
print('Removed Entware PATH from /etc/profile')
PYEOF
}

download_file() {
    url="$1"
    dest="$2"
    python3 - "$url" "$dest" << 'PYEOF'
import sys
import urllib.request

url, dest = sys.argv[1], sys.argv[2]
urllib.request.urlretrieve(url, dest)
print('Downloaded ' + url)
PYEOF
}

install_entware() {
    echo ""
    echo "======================================================"
    echo "  Entware Package Manager"
    echo "======================================================"
    echo ""
    echo "  Entware provides hundreds of Linux packages for K2 Series printers."
    echo "  It modifies /opt, /etc/rc.local and PATH. Backup first."
    echo ""
    echo "  Detected architecture: $(uname -m)"
    if [ "$(uname -m)" != "armv7l" ] && [ "$(uname -m)" != "armv7" ]; then
        log_warn "This Entware bootstrap uses armv7sf-k2.6. Architecture is not armv7; stopping."
        return 1
    fi

    printf "  Continue? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }

    if [ -f /opt/bin/opkg ]; then
        log_info "Entware already installed."
        echo ""
        echo "  What would you like to do?"
        echo "   1) Install useful packages"
        echo "   2) Update package list"
        echo "   3) Open opkg shell"
        echo "   4) Show Entware status"
        echo "   0) Back"
        echo ""
        printf "  Enter choice: "
        read choice
        case "$choice" in
            1) install_packages ;;
            2) export PATH=/opt/bin:/opt/sbin:$PATH; opkg update; log_success "Package list updated." ;;
            3) export PATH=/opt/bin:/opt/sbin:$PATH; sh ;;
            4) entware_status ;;
        esac
        return 0
    fi

    log_info "Creating temporary wget shim for the Entware bootstrap..."
    mkdir -p ~/bin
    if ! download_file "$DUMMY_WGET_URL" /root/bin/wget; then
        log_error "Failed to download temporary wget shim."
        return 1
    fi
    chmod +x ~/bin/wget
    export PATH=$PATH:~/bin

    log_info "Downloading Entware installer..."
    rm -f "$ENTWARE_INSTALLER"
    if ! download_file "$ENTWARE_INSTALLER_URL" "$ENTWARE_INSTALLER"; then
        log_error "Failed to download Entware installer."
        rm -f ~/bin/wget "$ENTWARE_INSTALLER"
        return 1
    fi
    if [ ! -s "$ENTWARE_INSTALLER" ]; then
        log_error "Entware installer is empty."
        rm -f ~/bin/wget "$ENTWARE_INSTALLER"
        return 1
    fi

    log_info "Running Entware installer..."
    sh "$ENTWARE_INSTALLER"
    rc=$?
    rm -f "$ENTWARE_INSTALLER"
    if [ $rc -ne 0 ] || [ ! -x /opt/bin/opkg ]; then
        log_error "Entware installer failed or /opt/bin/opkg was not created."
        rm -f ~/bin/wget
        return 1
    fi

    export PATH=/opt/bin:/opt/sbin:$PATH

    log_info "Installing real wget..."
    opkg update && opkg install wget
    rc=$?
    rm -f ~/bin/wget
    if [ $rc -ne 0 ]; then
        log_warn "Entware installed, but installing wget failed. You can retry from the Entware menu."
    fi

    patch_rc_local_entware || return 1
    patch_profile_entware || return 1

    test -f ~/.profile || echo '#!/bin/ash' > ~/.profile
    chmod +x ~/.profile
    grep -q 'opt/bin' ~/.profile || echo 'export PATH=/opt/bin:/opt/sbin:$PATH' >> ~/.profile

    mark_installed "entware"
    echo ""
    log_success "Entware installed!"
    echo ""
    echo "  Would you like to install useful packages now?"
    printf "  [y/n]: "
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        install_packages
    fi
}

ensure_entware_packages() {
    export PATH=/opt/bin:/opt/sbin:$PATH
    if [ ! -x /opt/bin/opkg ]; then
        log_error "Entware is not installed yet. Use the Entware install menu first; ensure will not patch rc.local or create symlinks without opkg."
        return 1
    fi
    opkg update || return 1
    opkg install $ALL_PACKAGES || return 1
    link_entware_tools
    link_entware_sftp
    patch_rc_local_entware
    patch_profile_entware
    entware_status
}

install_packages() {
    export PATH=/opt/bin:/opt/sbin:$PATH
    echo ""
    echo "  Select packages to install:"
    echo "   1) nano        - better text editor"
    echo "   2) htop        - process monitor"
    echo "   3) git         - version control"
    echo "   4) openssh-sftp-server - SFTP file transfer"
    echo "   5) curl        - HTTP client"
    echo "   6) All base packages"
    echo "   7) Diagnostics pack - bash bc xz file sqlite3 jq tree diffutils timeout"
    echo "   8) All recommended K2 Pro maintenance packages"
    echo "   9) Relink installed Entware tools into /usr/bin"
    echo "   0) Back"
    echo ""
    printf "  Enter choice: "
    read choice
    case "$choice" in
        1) opkg install nano ;;
        2) opkg install htop ;;
        3) opkg install git git-http && ln -sf /opt/bin/git /usr/bin/git ;;
        4) opkg install openssh-sftp-server
           link_entware_sftp
           ;;
        5) opkg install curl && ln -sf /opt/bin/curl /usr/bin/curl ;;
        6)
            opkg install $BASE_PACKAGES
            link_entware_tools
            link_entware_sftp
            ;;
        7)
            opkg install $DIAG_PACKAGES
            link_entware_tools
            ;;
        8)
            opkg install $ALL_PACKAGES
            link_entware_tools
            link_entware_sftp
            patch_rc_local_entware
            patch_profile_entware
            ;;
        9)
            link_entware_tools
            patch_rc_local_entware
            patch_profile_entware
            ;;
        0) return ;;
    esac
    echo ""
    log_success "Done!"
}

remove_entware() {
    if ! is_installed "entware"; then
        log_info "Entware is not installed."
        return 0
    fi
    echo ""
    printf "%b\n" "${YELLOW}WARNING: This will remove Entware and all installed packages.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }

    rm -rf /opt
    unpatch_rc_local_entware
    unpatch_profile_entware
    for link in /usr/bin/opkg /usr/bin/bash /usr/bin/bc /usr/bin/xz /usr/bin/file /usr/bin/nano /usr/bin/git /usr/bin/curl /usr/bin/sqlite3 /usr/bin/jq /usr/bin/tree /usr/bin/diff /usr/bin/sftp-server /usr/libexec/sftp-server; do
        if [ -L "$link" ]; then
            target="$(readlink "$link")"
            case "$target" in
                /opt/*) rm -f "$link" ;;
            esac
        fi
    done
    mark_removed "entware"
    log_success "Entware removed."
}

case "$1" in
    install) install_entware ;;
    ensure)  ensure_entware_packages ;;
    status)  entware_status ;;
    remove)  remove_entware ;;
    *)       echo "Usage: $0 [install|ensure|status|remove]" ;;
esac
