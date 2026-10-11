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

shopt -s extglob
echo "====> Cleaning up files in $CONFIG_DIR (preserving Geo and config.yaml)..."
rm -rf "$CONFIG_DIR"/!(config.yaml|geoip*|geosite*) 2>/dev/null || true
shopt -u extglob
cp -rf "$RESOURCE_DIR/WEBUI" "$CONFIG_DIR/"

GEO_VAL="${GEO_UPDATE:-false}"
if [ "$GEO_VAL" = "true" ]; then
    echo "====> GEO_UPDATE is true: Copying Geo databases to $CONFIG_DIR..."
    cp -rfu "$RESOURCE_DIR"/geoip* "$CONFIG_DIR/" 2>/dev/null || true
    cp -rfu "$RESOURCE_DIR"/geosite* "$CONFIG_DIR/" 2>/dev/null || true
else
    rm -rf "$CONFIG_DIR"/geoip* "$CONFIG_DIR"/geosite* 2>/dev/null || true
    echo "====> GEO_UPDATE is false: Skipping Geo databases copy."
fi

[ -z "$WEBUI_LISTEN_ADDR" ] && WEBUI_LISTEN_ADDR="0.0.0.0:9090"

if [ -z "$WEBUI_SECRET" ] || [ "$WEBUI_SECRET" = "none" ]; then
    WEBUI_SECRET=""
    echo "====> Web UI authentication is DISABLED."
else
    echo " Web UI password set: $WEBUI_SECRET"
fi

API_ADDR="${WEBUI_LISTEN_ADDR/0.0.0.0/127.0.0.1}"

export WEBUI_LISTEN_ADDR
export WEBUI_SECRET
export API_ADDR

echo "====> Environment initialization completed."
