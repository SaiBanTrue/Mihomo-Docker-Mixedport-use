#!/bin/bash

set -e

LATEST_TAG=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | jq -r '.tag_name')
MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_TAG}/mihomo-linux-arm64-${LATEST_TAG}.gz"
METADB_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
GEOSITE_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
WEBUI_URL="https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip"

APP_DIR="./app"
RES_DIR="$APP_DIR/res"

mkdir -p "$RES_DIR"

echo "====> [1/4] Downloading rule databases..."
curl -L -o "$RES_DIR/geoip.metadb" "$METADB_URL"
curl -L -o "$RES_DIR/geosite.dat" "$GEOSITE_URL"

echo "====> [2/4] Downloading and deploying Mihomo core..."
curl -L -o "$APP_DIR/mihomo.gz" "$MIHOMO_URL"
gzip -d -c "$APP_DIR/mihomo.gz" > "$APP_DIR/mihomo"
rm -f "$APP_DIR/mihomo.gz"

echo "====> [3/4] Downloading and deploying Web UI..."
curl -L -o "$RES_DIR/ui.zip" "$WEBUI_URL"
mkdir -p "$RES_DIR/temp_ui"
unzip -q -o "$RES_DIR/ui.zip" -d "$RES_DIR/temp_ui"
mkdir -p "$RES_DIR/WEBUI"

# 将 dist 内部的所有静态资源直接移入 WEBUI 根目录
# 清理无用的临时文件和目录
mv "$RES_DIR/temp_ui/dist/"* "$RES_DIR/WEBUI/"
rm -rf "$RES_DIR/temp_ui" "$RES_DIR/ui.zip"

echo "====> [4/4] Pre-build process completed successfully."
