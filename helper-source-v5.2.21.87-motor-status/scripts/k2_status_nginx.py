#!/usr/bin/env python3
"""Manage the service-worker-free nginx endpoint for the K2 status page."""

import argparse
import json
import os
import re
import shutil
import subprocess
import time
import urllib.request
from pathlib import Path

DEFAULT_CONF = "/etc/nginx/nginx.conf"
DEFAULT_BACKUP_DIR = "/mnt/UDISK/printer_data/backups/k2pro_helper"
STATUS_URL = "http://127.0.0.1:4410/status.json"
BEGIN = "# K2_STATUS_SERVER_BEGIN"
END = "# K2_STATUS_SERVER_END"
LEGACY_BEGIN = "# K2_STATUS_CACHE_BEGIN"
LEGACY_END = "# K2_STATUS_CACHE_END"
MANAGED_SERVER = """    # K2_STATUS_SERVER_BEGIN
    server {
        listen 4410 default_server;
        server_name _;
        root /mnt/UDISK/helper-script/web/k2-status;
        index index.html;
        charset utf-8;

        add_header Cache-Control "no-store, no-cache, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header X-Content-Type-Options "nosniff" always;

        location = / {
            try_files /index.html =404;
        }
        location = /index.html {
            try_files /index.html =404;
        }
        location = /status.json {
            default_type application/json;
            try_files /status.json =404;
        }
        location / {
            return 404;
        }
    }
    # K2_STATUS_SERVER_END
"""


def matching_brace(text, open_index):
    depth = 0
    for index in range(open_index, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return -1


def find_named_blocks(content, name):
    blocks = []
    for match in re.finditer(r"\b%s\s*\{" % re.escape(name), content):
        open_index = content.find("{", match.start())
        close_index = matching_brace(content, open_index)
        if close_index >= 0:
            blocks.append(
                (match.start(), close_index + 1, content[match.start() : close_index + 1])
            )
    return blocks


def remove_marked_section(content, begin, end):
    pattern = re.compile(
        r"^[ \t]*%s\r?\n.*?^[ \t]*%s[ \t]*\r?\n?"
        % (re.escape(begin), re.escape(end)),
        re.MULTILINE | re.DOTALL,
    )
    return pattern.sub("", content)


def frontend_ports(content):
    ports = []
    for _, _, block in find_named_blocks(content, "server"):
        match = re.search(r"\blisten\s+(4408|4409)\b", block)
        if match:
            ports.append(match.group(1))
    return ports


def has_foreign_status_port(content):
    for _, _, block in find_named_blocks(content, "server"):
        if re.search(r"\blisten\s+4410\b", block):
            return True
    return False


def patch_content(content, install=True, require_frontends=True):
    content = remove_marked_section(content, LEGACY_BEGIN, LEGACY_END)
    content = remove_marked_section(content, BEGIN, END)
    ports = frontend_ports(content)
    if require_frontends and set(ports) != {"4408", "4409"}:
        raise RuntimeError("Expected nginx frontend blocks for ports 4408 and 4409")
    if not install:
        return content, ports
    if has_foreign_status_port(content):
        raise RuntimeError("Foreign nginx server on status port 4410; refusing to replace it")

    http_blocks = find_named_blocks(content, "http")
    if len(http_blocks) != 1:
        raise RuntimeError("Expected exactly one nginx http block")
    _, end, _ = http_blocks[0]
    insert_index = end - 1
    prefix = content[:insert_index].rstrip() + "\n\n"
    content = prefix + MANAGED_SERVER + content[insert_index:]
    return content, ports + ["4410"]


def check_content(content):
    if content.count(BEGIN) != 1 or content.count(END) != 1:
        return False, []
    if LEGACY_BEGIN in content or LEGACY_END in content:
        return False, []
    checked = []
    for _, _, block in find_named_blocks(content, "server"):
        if not re.search(r"\blisten\s+4410\b", block):
            continue
        required = (
            "/mnt/UDISK/helper-script/web/k2-status",
            "no-store",
            "location = /status.json",
        )
        if not all(item in block for item in required):
            return False, checked
        checked.append("4410")
    return checked == ["4410"], checked


def run_nginx(nginx_bin, *args):
    result = subprocess.run([nginx_bin, *args], capture_output=True, text=True)
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError("nginx %s failed: %s" % (" ".join(args), detail))


def verify_status_endpoint(url=STATUS_URL, attempts=20, delay=0.25):
    last_error = "no response"
    for _ in range(attempts):
        try:
            request = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
            with urllib.request.urlopen(request, timeout=2) as response:
                payload = json.loads(response.read().decode("utf-8"))
                cache_control = response.headers.get("Cache-Control", "")
                if response.status != 200:
                    raise RuntimeError("HTTP %s" % response.status)
                if "no-store" not in cache_control:
                    raise RuntimeError("missing no-store response header")
                if not isinstance(payload, dict) or "printer" not in payload:
                    raise RuntimeError("status.json is not a current K2 status payload")
                return
        except Exception as exc:  # The retry detail is reported after the final attempt.
            last_error = str(exc)
            time.sleep(delay)
    raise RuntimeError("dedicated K2 status endpoint failed: %s" % last_error)


def write_transaction(conf_path, content, nginx_bin, reload_nginx, verify_after_reload=False):
    original = conf_path.read_text(encoding="utf-8")
    if content == original:
        run_nginx(nginx_bin, "-t")
        if reload_nginx:
            run_nginx(nginx_bin, "-s", "reload")
            if verify_after_reload:
                verify_status_endpoint()
        return None

    backup_dir = Path(os.environ.get("K2_STATUS_NGINX_BACKUP_DIR", DEFAULT_BACKUP_DIR))
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / (
        "nginx-before-k2-status-%s-%s.conf" % (time.strftime("%Y%m%d_%H%M%S"), os.getpid())
    )
    shutil.copy2(conf_path, backup)
    temp = conf_path.with_name(conf_path.name + ".k2-status.tmp")
    temp.write_text(content, encoding="utf-8")
    os.replace(temp, conf_path)
    try:
        run_nginx(nginx_bin, "-t")
        if reload_nginx:
            run_nginx(nginx_bin, "-s", "reload")
            if verify_after_reload:
                verify_status_endpoint()
    except Exception:
        shutil.copy2(backup, conf_path)
        run_nginx(nginx_bin, "-t")
        if reload_nginx:
            run_nginx(nginx_bin, "-s", "reload")
        raise
    return backup


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "remove", "check"), nargs="?", default="check")
    parser.add_argument("--config", default=os.environ.get("K2_NGINX_CONF", DEFAULT_CONF))
    parser.add_argument("--nginx", default=os.environ.get("K2_NGINX_BIN", "nginx"))
    parser.add_argument("--no-reload", action="store_true")
    args = parser.parse_args()

    conf_path = Path(args.config)
    content = conf_path.read_text(encoding="utf-8")
    if args.action == "check":
        valid, ports = check_content(content)
        print("STATUS_NGINX|%s|ports=%s" % ("OK" if valid else "WARN", ",".join(ports)))
        raise SystemExit(0 if valid else 1)

    patched, ports = patch_content(content, install=args.action == "install")
    backup = write_transaction(
        conf_path,
        patched,
        args.nginx,
        not args.no_reload,
        verify_after_reload=args.action == "install",
    )
    print(
        "STATUS_NGINX|OK|action=%s|ports=%s|backup=%s"
        % (args.action, ",".join(ports), backup or "unchanged")
    )


if __name__ == "__main__":
    main()
