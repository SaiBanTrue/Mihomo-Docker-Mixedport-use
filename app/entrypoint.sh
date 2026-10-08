#!/bin/bash

set -e

source /app/app_init.sh

bash /app/config_update.sh

_term() {
    killall -9 mihomo 2>/dev/null || true
    exit 0
}
trap _term SIGTERM SIGINT SIGHUP
#它的职责是：启动并死死盯住 Mihomo 核心，一旦崩溃立刻拉起。
echo "====> Starting Mihomo core engine loop..."

while [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
    /app/mihomo \
        -d "$CONFIG_DIR" \
        -f "$CONFIG_FILE" \
        -ext-ui "$WEBUI_DIR" \
        -ext-ctl "$WEBUI_LISTEN_ADDR" \
        -secret "$WEBUI_SECRET" &
    MIHOMO_PID=$!
    
    IS_HEALTHY=false
    for ((i=10; i>0; i--)); do
        kill -0 "$MIHOMO_PID" 2>/dev/null || break
        
        VERSION_INFO=$(curl -s \
            -H "Authorization: Bearer ${WEBUI_SECRET}" \
            "http://${API_ADDR}/version" 2>/dev/null) && [ -n "$VERSION_INFO" ] && IS_HEALTHY=true && break
            
        sleep 1
    done
    
    if [ "$IS_HEALTHY" = "true" ]; then
        echo "====> Mihomo core version: $VERSION_INFO"
        RETRY_COUNT=0
        wait "$MIHOMO_PID" || true
    else
        ((RETRY_COUNT++))
        echo "====> WARNING: Mihomo health check failed. Retry $RETRY_COUNT/$MAX_RETRIES"
    fi
    
    killall -9 mihomo 2>/dev/null || true
    [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ] && sleep 2
done

echo "====> ERROR: Mihomo core failed to start. Exiting."
exit 1
