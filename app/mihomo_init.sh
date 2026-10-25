#!/bin/bash

set -e

chmod +x /app/mihomo

RETRY_COUNT=0
MAX_RETRIES=3

RESOURCE_DIR="/app/res"
CONFIG_DIR="/config"
WEBUI_DIR="$CONFIG_DIR/ui/zashboard"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

mkdir -p "$CONFIG_DIR"

shopt -s extglob
echo "====> Cleaning up files in $CONFIG_DIR (preserving Geo and config.yaml)..."
rm -rf "$CONFIG_DIR"/!(config.yaml|geoip*|geosite*|proxies|rules|cache.db) 2>/dev/null || true
shopt -u extglob

mkdir -p "$WEBUI_DIR"
cp -rf "$RESOURCE_DIR/WEBUI/." "$WEBUI_DIR/"

GEO_VAL="${GEO_UPDATE:-false}"
if [ "$GEO_VAL" = "true" ]; then
    echo "====> GEO_UPDATE is true: Copying Geo databases to $CONFIG_DIR..."
    cp -rfu "$RESOURCE_DIR"/geoip* "$CONFIG_DIR/" 2>/dev/null || true
    cp -rfu "$RESOURCE_DIR"/geosite* "$CONFIG_DIR/" 2>/dev/null || true
else
    rm -rf "$CONFIG_DIR"/geoip* "$CONFIG_DIR"/geosite* 2>/dev/null || true
    echo "====> GEO_UPDATE is false: Skipping Geo databases copy."
fi

echo "====> Environment initialization completed."
