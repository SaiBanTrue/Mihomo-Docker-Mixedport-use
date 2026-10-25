#!/bin/bash

set -e

source /app/mihomo_init.sh

if [ -f "$CONFIG_FILE" ]; then
    echo "====> Found config file: $CONFIG_FILE. Validating..."
    if ! /app/mihomo -t -d "$CONFIG_DIR" -f "$CONFIG_FILE"; then
        echo "====> ERROR: Configuration validation failed. Exiting."
        exit 1
    fi
    echo "====> Configuration validation passed."
else
    echo "====> WARNING: No config file found at $CONFIG_FILE. Skipping validation."
    exit 1
fi

_term() {
    killall -9 mihomo 2>/dev/null || true
    exit 0
}
trap _term SIGTERM SIGINT SIGHUP



echo "====> Mihomo core version: $(/app/mihomo -v 2>&1 | head -n 1)"
echo "====> Starting Mihomo core engine loop..."

while [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
    /app/mihomo \
        -d "$CONFIG_DIR" \
        -f "$CONFIG_FILE" &
    MIHOMO_PID=$!
    
    sleep 2

    if kill -0 "$MIHOMO_PID" 2>/dev/null; then
        echo "====> Mihomo started successfully (PID: $MIHOMO_PID)."
        RETRY_COUNT=0
        wait "$MIHOMO_PID" || true
    else
        ((RETRY_COUNT++))
        echo "====> WARNING: Mihomo process exited unexpectedly. Retry $RETRY_COUNT/$MAX_RETRIES"
    fi
    
    killall -9 mihomo 2>/dev/null || true
    [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ] && sleep 2
done

echo "====> ERROR: Mihomo core failed to start. Exiting."
exit 1