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

# ==========================================
# 1. 任何情况下清空文件夹，并无条件强制覆盖 WebUI
# ==========================================
echo "====> Cleaning up all files in $CONFIG_DIR..."
rm -rf "$CONFIG_DIR"/*
cp -rf "$RESOURCE_DIR/WEBUI" "$CONFIG_DIR/"

# ==========================================
# 2. 仅当 GEO_UPDATE="true" 时，才复制规则库文件
# ==========================================
GEO_VAL="${GEO_UPDATE:-$(printenv GEO-UPDATE 2>/dev/null)}"

if [ "$GEO_VAL" = "true" ]; then
    echo "====> GEO_UPDATE is true: Copying Geo databases to $CONFIG_DIR..."
    cp -rfu "$RESOURCE_DIR"/geoip* "$CONFIG_DIR/" 2>/dev/null || true
    cp -rfu "$RESOURCE_DIR"/geosite* "$CONFIG_DIR/" 2>/dev/null || true
else
    echo "====> GEO_UPDATE is false: Skipping Geo databases copy."
fi

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
