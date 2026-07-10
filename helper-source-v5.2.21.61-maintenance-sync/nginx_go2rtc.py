#!/usr/bin/env python3
import re
import shutil
import subprocess
import sys

NGINX_CONF = "/etc/nginx/nginx.conf"
BACKUP_CONF = "/mnt/UDISK/helper-script/.nginx.conf.bak"

GO2RTC_LOCATIONS = """        location /go2rtc/ {
            proxy_pass http://127.0.0.1:1984/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $http_host;
            proxy_read_timeout 3600;
            proxy_send_timeout 3600;
        }
        location /go2rtc/api/ws {
            proxy_pass http://127.0.0.1:1984/api/ws?src=k2camera&$args;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $http_host;
            proxy_read_timeout 3600;
            proxy_send_timeout 3600;
        }
"""


def matching_brace(text, open_index):
    depth = 0
    for index in range(open_index, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    return -1


def remove_location(block, location):
    pattern = re.compile(r"^[ \t]*location\s+%s\s*\{" % re.escape(location), re.M)
    while True:
        match = pattern.search(block)
        if not match:
            return block
        open_index = block.find("{", match.start())
        close_index = matching_brace(block, open_index)
        if close_index < 0:
            raise RuntimeError("Could not parse nginx location %s" % location)
        end_index = close_index + 1
        while end_index < len(block) and block[end_index] in " \t":
            end_index += 1
        if end_index < len(block) and block[end_index] == "\r":
            end_index += 1
        if end_index < len(block) and block[end_index] == "\n":
            end_index += 1
        block = block[: match.start()] + block[end_index:]


def patch_server_block(block, install):
    block = remove_location(block, "/go2rtc/api/ws")
    block = remove_location(block, "/go2rtc/")
    if not install:
        return block

    webcam_match = re.search(r"^[ \t]*location\s+/webcam\b", block, re.M)
    insert_index = webcam_match.start() if webcam_match else block.rfind("}")
    if insert_index < 0:
        raise RuntimeError("Could not find insertion point in nginx server block")
    return block[:insert_index] + GO2RTC_LOCATIONS + block[insert_index:]


def find_server_blocks(content):
    blocks = []
    for match in re.finditer(r"\bserver\s*\{", content):
        open_index = content.find("{", match.start())
        close_index = matching_brace(content, open_index)
        if close_index >= 0:
            blocks.append((match.start(), close_index + 1, content[match.start():close_index + 1]))
    return blocks


def patch_content(content, install):
    replacements = []
    patched_ports = []
    for start, end, block in find_server_blocks(content):
        listen_match = re.search(r"\blisten\s+(4408|4409)\b", block)
        if not listen_match:
            continue
        port = listen_match.group(1)
        new_block = patch_server_block(block, install)
        replacements.append((start, end, new_block))
        patched_ports.append(port)

    if install and not patched_ports:
        raise RuntimeError("No nginx server blocks for ports 4408 or 4409 were found")

    for start, end, new_block in reversed(replacements):
        content = content[:start] + new_block + content[end:]
    return content, patched_ports


def validate_or_restore():
    result = subprocess.run(["nginx", "-t"], capture_output=True, text=True)
    if result.returncode == 0:
        return True
    print("ERROR: nginx -t failed:")
    print(result.stderr.strip())
    try:
        shutil.copy(BACKUP_CONF, NGINX_CONF)
        print("Restored nginx backup: %s" % BACKUP_CONF)
    except Exception as exc:
        print("Could not restore nginx backup: %s" % exc)
    return False


def main():
    install = len(sys.argv) < 2 or sys.argv[1] != "remove"
    with open(NGINX_CONF, "r") as handle:
        content = handle.read()

    new_content, ports = patch_content(content, install)
    with open(NGINX_CONF, "w") as handle:
        handle.write(new_content)

    if not validate_or_restore():
        sys.exit(1)

    action = "updated" if install else "removed"
    if ports:
        print("Nginx go2rtc proxy %s for ports: %s" % (action, ", ".join(ports)))
    else:
        print("No go2rtc nginx blocks needed removal.")


if __name__ == "__main__":
    main()
