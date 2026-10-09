#!/bin/bash

set -e

TEMPLATE_FILE="/app/template_config.yaml"
CONFIG_DIR="/config"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

# ==========================================
# 1. 动态注入 proxy-providers (从模板安全生成)
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

    awk -v insert="$PROVIDERS_BLOCK" '{
        if ($0 ~ /^[ \t]*PROVIDERS_PLACEHOLDER/) {
            printf "%s", insert
        } else {
            print $0
        }
    }' "$TEMPLATE_FILE" > "$CONFIG_FILE"
else
    # 未提供 SUB_URL 时，若配置不存在则复制一份模板
    [ ! -f "$CONFIG_FILE" ] && cp -f "$TEMPLATE_FILE" "$CONFIG_FILE"
fi

# ==========================================
# 2. 纯 sed 更新环境变量（彻底抛弃 yq，绝无 !!merge）
# ==========================================
update_param() {
    local key="$1"
    local val="$2"
    if [ -n "$val" ]; then
        if grep -q "^${key}:" "$CONFIG_FILE"; then
            # 如果配置中已存在该字段，原地精准替换
            sed -i "s|^${key}:.*|${key}: ${val}|" "$CONFIG_FILE"
        else
            # 如果配置中原本没有，直接插入到文件第 1 行（置顶）
            sed -i "1i ${key}: ${val}" "$CONFIG_FILE"
        fi
    fi
}

# 基础参数覆盖
update_param "mixed-port" "$MIXED_PORT"
update_param "allow-lan" "$ALLOW_LAN"
update_param "ipv6" "$IPV6"
update_param "mode" "$MIHOMO_MODE"

# 处理用户认证列表（如果有配置）
if [ -n "$AUTHENTICATION" ]; then
    AUTH_BLOCK="authentication:"
    IFS=',' read -ra AUTH_ARRAY <<< "$AUTHENTICATION"
    for auth in "${AUTH_ARRAY[@]}"; do
        AUTH_BLOCK="${AUTH_BLOCK}\n  - \"$(echo "$auth" | tr -d ' ')\""
    done
    sed -i '/^authentication:/,/^[a-zA-Z0-9_-]\+:/ { /^authentication:/d; /^[a-zA-Z0-9_-]\+:/!d }' "$CONFIG_FILE" 2>/dev/null || true
    sed -i "1i ${AUTH_BLOCK}" "$CONFIG_FILE"
fi

# 处理免认证网段（如果有配置）
if [ -n "$SKIP_AUTH_PREFIXES" ]; then
    SKIP_BLOCK="skip-auth-prefixes:"
    IFS=',' read -ra SKIP_ARRAY <<< "$SKIP_AUTH_PREFIXES"
    for prefix in "${SKIP_ARRAY[@]}"; do
        SKIP_BLOCK="${SKIP_BLOCK}\n  - \"$(echo "$prefix" | tr -d ' ')\""
    done
    sed -i '/^skip-auth-prefixes:/,/^[a-zA-Z0-9_-]\+:/ { /^skip-auth-prefixes:/d; /^[a-zA-Z0-9_-]\+:/!d }' "$CONFIG_FILE" 2>/dev/null || true
    sed -i "1i ${SKIP_BLOCK}" "$CONFIG_FILE"
fi