#!/bin/bash

set -e

chmod +x /app/mihomo

RETRY_COUNT=0
MAX_RETRIES=3
RESOURCE_DIR="/app/res"

CONFIG_DIR="/config"
WEBUI_DIR="$CONFIG_DIR/WEBUI"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

mkdir -p "$CONFIG_DIR"

if [ "$WEBUI_OVERWRITE" != "false" ]; then
    rm -rf "$WEBUI_DIR"
    cp -rf "$RESOURCE_DIR/WEBUI" "$CONFIG_DIR/"
fi

for item in "$RESOURCE_DIR"/*; do
    name=$(basename "$item")
    [ "$name" != "WEBUI" ] && cp -rfu "$item" "$CONFIG_DIR/"
done

[ ! -f "$CONFIG_FILE" ] && echo "mixed-port: 7890" > "$CONFIG_FILE"

[ -z "$WEBUI_LISTEN_ADDR" ] && WEBUI_LISTEN_ADDR="0.0.0.0:9090"

if [ -z "$WEBUI_SECRET" ] || [ "$WEBUI_SECRET" = "none" ]; then
    WEBUI_SECRET=""
    echo "====> Web UI authentication is DISABLED."
else
    echo "***************************************************"
    echo " Web UI password set: $WEBUI_SECRET"
    echo "***************************************************"
fi

API_ADDR="${WEBUI_LISTEN_ADDR/0.0.0.0/127.0.0.1}"

export WEBUI_LISTEN_ADDR
export WEBUI_SECRET
export API_ADDR

echo "====> Environment initialization completed."
