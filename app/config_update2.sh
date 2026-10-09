#!/bin/bash

set -e

TEMPLATE_FILE="/app/temporaryconfiguration.yaml"
CONFIG_DIR="/config"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

YQ_EXPR=""
DEL_KEYS=""
OBJ_KEYS=""

register_key() {
    local key="$1"
    DEL_KEYS="${DEL_KEYS}.${key}, "
    OBJ_KEYS="${OBJ_KEYS}\"${key}\": .${key}, "
}

# ==========================================
# 1. 动态注入 proxy-providers (从模板生成到目标文件)
# ==========================================
if [[ -n "$SUB_URL" ]] && [[ "$SUB_URL" == http://* || "$SUB_URL" == https://* ]]; then
    echo "====> Injecting proxy-providers from SUB_URL..."
    
    PROVIDERS_BLOCK=""
    IFS=',' read -ra URL_ARRAY <<< "$SUB_URL"
    
    count=1
    for url in "${URL_ARRAY[@]}"; do
        url=$(echo "$url" | tr -d ' ')
        if [ -n "$url" ]; then
            PROVIDERS_BLOCK="${PROVIDERS_BLOCK}  Provider_${count}: {<<: *Anchor_PR, url: '${url}', override: {additional-prefix: '[Provider_${count}] '}}\n"
            ((count++))
        fi
    done
    
    # 【关键修改】：读取模板文件 $TEMPLATE_FILE，替换后直接写入目标文件 $CONFIG_FILE
    awk -v insert="$PROVIDERS_BLOCK" '{
        if ($0 ~ /^[ \t]*PROVIDERS_PLACEHOLDER/) {
            printf "%s", insert
        } else {
            print $0
        }
    }' "$TEMPLATE_FILE" > "$CONFIG_FILE"
else
    # 如果用户没有提供 SUB_URL，且目标配置不存在，则将原始模板作为基础配置拷贝过去
    [ ! -f "$CONFIG_FILE" ] && cp -f "$TEMPLATE_FILE" "$CONFIG_FILE"
fi

# ==========================================
# 2. 环境变量动态覆盖与顶层重排
# ==========================================
[ -n "$MIXED_PORT" ] && YQ_EXPR="${YQ_EXPR} .mixed-port = $MIXED_PORT |" && register_key "mixed-port"
[ -n "$ALLOW_LAN" ] && YQ_EXPR="${YQ_EXPR} .allow-lan = $ALLOW_LAN |" && register_key "allow-lan"
[ -n "$IPV6" ] && YQ_EXPR="${YQ_EXPR} .ipv6 = $IPV6 |" && register_key "ipv6"
[ -n "$MIHOMO_MODE" ] && YQ_EXPR="${YQ_EXPR} .mode = \"$MIHOMO_MODE\" |" && register_key "mode"
[ -n "$BIND_ADDRESS" ] && YQ_EXPR="${YQ_EXPR} .bind-address = \"$BIND_ADDRESS\" |" && register_key "bind-address"
[ -n "$AUTHENTICATION" ] && export AUTHENTICATION && YQ_EXPR="${YQ_EXPR} .authentication = (env(AUTHENTICATION) | split(\",\") | .[] style=\"double\") |" && register_key "authentication"
[ -n "$SKIP_AUTH_PREFIXES" ] && export SKIP_AUTH_PREFIXES && YQ_EXPR="${YQ_EXPR} .skip-auth-prefixes = (env(SKIP_AUTH_PREFIXES) | split(\",\")) |" && register_key "skip-auth-prefixes"

if [ -n "$YQ_EXPR" ]; then
    yq eval -i "${YQ_EXPR% |}" "$CONFIG_FILE"
    yq eval -i ". as \$rest | ({ ${OBJ_KEYS%, } } | with_entries(select(.value != null))) + (\$rest | del(${DEL_KEYS%, }))" "$CONFIG_FILE"
fi