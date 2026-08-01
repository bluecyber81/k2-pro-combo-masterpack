#!/bin/sh
# git_backup.sh - local Git snapshots for K2 Pro printer config.

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

CONFIG_REPO=/mnt/UDISK/printer_data/config
REMOTE_HINT_FILE=$CONFIG_REPO/.k2pro_git_remote_hint

git_bin() {
    if command -v git >/dev/null 2>&1; then
        command -v git
    elif [ -x /opt/bin/git ]; then
        echo /opt/bin/git
    else
        return 1
    fi
}

require_git() {
    GIT="$(git_bin)" || {
        log_error "git is missing. Install/ensure Entware first, then retry Git Backup."
        echo "Menu path: Installieren / Reparieren -> Entware Package Manager"
        return 1
    }
    return 0
}

write_gitignore() {
    ignore_file="$CONFIG_REPO/.gitignore"
    touch "$ignore_file" 2>/dev/null || return 1
    for pattern in \
        "__pycache__/" "*.pyc" "*.pyo" "*.tmp" "*.bak" "*.old" "*.swp" \
        "*.bak-*" "/printer-[0-9]*_[0-9]*.cfg" "/printer.cfg.bak-*" \
        "backup_config.tar.gz" "*.log" ".DS_Store"; do
        grep -Fxq "$pattern" "$ignore_file" 2>/dev/null || echo "$pattern" >> "$ignore_file"
    done
}

ensure_repo() {
    require_git || return 1
    if [ ! -d "$CONFIG_REPO" ]; then
        log_error "Config directory missing: $CONFIG_REPO"
        return 1
    fi
    cd "$CONFIG_REPO" || return 1
    if [ ! -d .git ]; then
        "$GIT" init || return 1
    fi
    "$GIT" config user.name "K2 Pro Helper" >/dev/null 2>&1 || true
    "$GIT" config user.email "k2pro-helper@local" >/dev/null 2>&1 || true
    "$GIT" config --global --add safe.directory "$CONFIG_REPO" >/dev/null 2>&1 || true
    write_gitignore || log_warn "Could not update .gitignore."
}

commit_snapshot() {
    ensure_repo || return 1
    cd "$CONFIG_REPO" || return 1
    "$GIT" add -A || return 1
    if "$GIT" diff --cached --quiet --exit-code; then
        log_info "No config changes to commit."
        return 0
    fi
    stamp="$(date '+%Y-%m-%d %H:%M:%S')"
    "$GIT" commit -m "K2 Pro config backup $stamp" || return 1
    log_success "Local Git config snapshot created."
}

status_git_backup() {
    echo ""
    echo "K2 Pro local Git Backup status"
    echo "Config repo: $CONFIG_REPO"
    require_git || return 1
    if [ ! -d "$CONFIG_REPO/.git" ]; then
        log_warn "Git repo is not initialized yet."
        echo "Run install/snapshot once to create it."
        echo ""
        return 0
    fi
    cd "$CONFIG_REPO" || return 1
    "$GIT" status --short 2>/dev/null | sed 's/^/  /'
    last="$("$GIT" log -1 --oneline 2>/dev/null || true)"
    if [ -n "$last" ]; then
        echo "Last commit: $last"
    else
        echo "Last commit: none yet"
    fi
    remote="$("$GIT" remote get-url origin 2>/dev/null || true)"
    if [ -n "$remote" ]; then
        echo "Remote origin: $remote"
    else
        echo "Remote origin: not configured"
        echo "Optional later: sh $SCRIPT_DIR/scripts/git_backup.sh remote <git-url>"
    fi
    echo ""
}

set_remote() {
    require_git || return 1
    url="$1"
    if [ -z "$url" ]; then
        log_error "Missing remote URL."
        echo "Usage: $0 remote <git-url>"
        return 1
    fi
    ensure_repo || return 1
    cd "$CONFIG_REPO" || return 1
    if "$GIT" remote get-url origin >/dev/null 2>&1; then
        "$GIT" remote set-url origin "$url" || return 1
    else
        "$GIT" remote add origin "$url" || return 1
    fi
    echo "$url" > "$REMOTE_HINT_FILE" 2>/dev/null || true
    log_success "Remote origin configured."
}

push_remote() {
    ensure_repo || return 1
    cd "$CONFIG_REPO" || return 1
    if ! "$GIT" remote get-url origin >/dev/null 2>&1; then
        log_error "No remote origin configured. Use: $0 remote <git-url>"
        return 1
    fi
    branch="$("$GIT" symbolic-ref --short HEAD 2>/dev/null || echo master)"
    "$GIT" push -u origin "$branch"
}

install_git_backup() {
    echo ""
    log_info "Installing local Git Backup for /mnt/UDISK/printer_data/config ..."
    echo "This is local-only by default. It does not push to GitHub unless you add a remote URL."
    commit_snapshot || return 1
    mark_installed git_backup
    status_git_backup
}

remove_git_backup() {
    echo ""
    printf "%b\n" "${YELLOW}WARNING: This can remove the local Git history in $CONFIG_REPO/.git.${NC}"
    printf "Remove only helper marker and keep .git history? [Y/n]: "
    read keep
    if [ "$keep" = "n" ] || [ "$keep" = "N" ]; then
        printf "%b\n" "${YELLOW}Delete .git history permanently? Type DELETE-GIT to confirm:${NC} "
        read phrase
        if [ "$phrase" = "DELETE-GIT" ]; then
            rm -rf "$CONFIG_REPO/.git" "$REMOTE_HINT_FILE"
            log_success "Local Git history removed."
        else
            log_info "Git history kept."
        fi
    else
        log_info "Git history kept."
    fi
    mark_removed git_backup
}

case "$1" in
    install|snapshot|backup) install_git_backup ;;
    status)                 status_git_backup ;;
    remote)                 shift; set_remote "$1" ;;
    push)                   push_remote ;;
    remove)                 remove_git_backup ;;
    *)                      echo "Usage: $0 [install|snapshot|status|remote <git-url>|push|remove]" ;;
esac
