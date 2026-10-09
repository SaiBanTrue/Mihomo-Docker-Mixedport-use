#!/bin/bash

set -e

TEMPLATE_FILE="/app/temporaryconfiguration.yaml"
CONFIG_DIR="/config"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

# ==========================================
# 1. 动态注入 proxy-providers (支持多订阅链接)
# ==========================================
PROVIDERS_BLOCK=""
if [[ -n "$SUB_URL" ]] && [[ "$SUB_URL" == http://* || "$SUB_URL" == https://* ]]; then
    echo "====> Injecting proxy-providers from SUB_URL..."
    
    IFS=',' read -ra URL_ARRAY <<< "$SUB_URL"
    count=1
    for url in "${URL_ARRAY[@]}"; do
        url=$(echo "$url" | tr -d ' ')
        if [ -n "$url" ]; then
            PROVIDERS_BLOCK="${PROVIDERS_BLOCK}  Provider_${count}: {<<: *Anchor_PR, url: '${url}', override: {additional-prefix: '[Provider_${count}] '}}\n"
            ((count++))
        fi
    done
fi

# ==========================================
# 2. 单次 awk：替换占位符并覆盖 5 个环境变量参数
# ==========================================
awk \
    -v insert="$PROVIDERS_BLOCK" \
    -v mport="$MIXED_PORT" \
    -v lan="$ALLOW_LAN" \
    -v ipv6="$IPV6" \
    -v mode="$MIHOMO_MODE" \
    -v bind="$BIND_ADDRESS" \
    '{
        # 替换 proxy-providers 占位符
        if ($0 ~ /^[ \t]*PROVIDERS_PLACEHOLDER/) {
            printf "%s", insert
            next
        }
        # 环境变量动态覆盖（有传参就覆盖，没传参就保留模板默认值）
        if (mport != "" && $0 ~ /^mixed-port:/)   { print "mixed-port: " mport; next }
        if (lan != ""   && $0 ~ /^allow-lan:/)    { print "allow-lan: " lan; next }
        if (ipv6 != ""  && $0 ~ /^ipv6:/)         { print "ipv6: " ipv6; next }
        if (mode != ""  && $0 ~ /^mode:/)         { print "mode: " mode; next }
        if (bind != ""  && $0 ~ /^bind-address:/) { print "bind-address: \"" bind "\""; next }
        
        # 其余所有内容（注释、规则、锚点）100% 原样保留
        print $0
    }' "$TEMPLATE_FILE" > "$CONFIG_FILE"