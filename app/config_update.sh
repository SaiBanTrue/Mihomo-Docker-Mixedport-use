#!/bin/bash

set -e

CONFIG_DIR="/app"
CONFIG_FILE="$CONFIG_DIR/temporaryconfiguration.yaml"

YQ_EXPR=""
DEL_KEYS=""
OBJ_KEYS=""

register_key() {
    local key="$1"
    DEL_KEYS="${DEL_KEYS}.${key}, "
    OBJ_KEYS="${OBJ_KEYS}\"${key}\": .${key}, "
}
# ==========================================
# 动态注入 proxy-providers (支持多订阅链接)
# ==========================================
if [[ -n "$SUB_URL" ]] && [[ "$SUB_URL" == http://* || "$SUB_URL" == https://* ]]; then
    echo "====> Injecting proxy-providers from SUB_URL..."
    
    PROVIDERS_BLOCK=""
    # 将 SUB_URL 按照逗号分割成数组（支持多个链接同时填入，用逗号隔开）
    IFS=',' read -ra URL_ARRAY <<< "$SUB_URL"
    
    count=1
    for url in "${URL_ARRAY[@]}"; do
        # 剔除用户填写时可能不小心多打的空格
        url=$(echo "$url" | tr -d ' ')
        if [ -n "$url" ]; then
            # 动态拼装 YAML 节点代码。机场名被替换为通用的 Provider_1, Provider_2 ...
            PROVIDERS_BLOCK="${PROVIDERS_BLOCK}  Provider_${count}: {<<: *Anchor_PR, url: '${url}', override: {additional-prefix: '[Provider_${count}] '}}\n"
            ((count++))
        fi
    done
    
    # 使用 awk 将组装好的多行字符串，精准且安全地替换掉 config.yaml 中的占位符
    awk -v insert="$PROVIDERS_BLOCK" '{
        if ($0 ~ /^[ \t]*PROVIDERS_PLACEHOLDER/) {
            printf "%s", insert
        } else {
            print $0
        }
    }' "$CONFIG_FILE" > /tmp/tmp_config.yaml && mv /tmp/tmp_config.yaml "$CONFIG_FILE"
fi

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
