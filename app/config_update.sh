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
# 动态计算并更新订阅拉取周期 (小时 -> 秒)
# ==========================================
if [ -n "$UPDATE_INTERVAL" ] && [ "$UPDATE_INTERVAL" -gt 0 ] 2>/dev/null; then
    # 将小时换算为秒数 (例如: 12小时 * 3600 = 43200秒)
    INTERVAL_SEC=$(( UPDATE_INTERVAL * 3600 ))
    
    # 精准替换 Anchor_PR 里面的 interval 数值
    sed -i -E "s/(Anchor_PR:.*interval: *)[0-9]+/\1${INTERVAL_SEC}/" "$CONFIG_FILE"
    
    echo "====> Subscription update interval set to: ${UPDATE_INTERVAL}h (${INTERVAL_SEC}s)"
fi




# ==========================================
# 2. 环境变量参数动态注入引擎
# ==========================================

# --- 通用函数 1：处理单值参数 (有则替换，无则插到 log-level 下方，未设用默认) ---
update_param() {
    local key="$1"
    local val="$2"
    if [ -n "$val" ]; then
        if grep -q "^${key}:" "$CONFIG_FILE"; then
            # 规则 1：模板已有该参数，原地精准替换
            sed -i "s|^${key}:.*|${key}: ${val}|" "$CONFIG_FILE"
        else
            # 规则 2：模板原本没有，插入到 log-level 下方
            sed -i "/^log-level:.*/a ${key}: ${val}" "$CONFIG_FILE"
        fi
    fi
    # 规则 3：val 为空（未设置变量），自动跳过，原封不动保留模板默认值
}

# --- 通用函数 2：处理列表数组 (逗号拆分，插入到 log-level 下方，未设用默认) ---
update_list() {
    local key="$1"
    local raw_val="$2"
    if [ -n "$raw_val" ]; then
        local block="${key}:"
        IFS=',' read -ra arr <<< "$raw_val"
        for item in "${arr[@]}"; do
            block="${block}\n  - \"$(echo "$item" | tr -d ' ')\""
        done
        # 清除历史遗留并统一插入在 log-level 下方
        sed -i "/^${key}:/,/^[a-zA-Z0-9_#-]\+:/ { /^${key}:/d; /^[a-zA-Z0-9_#-]\+:/!d }" "$CONFIG_FILE" 2>/dev/null || true
        sed -i "/^log-level:.*/a ${block}" "$CONFIG_FILE"
    fi
}

# --- 通用函数 3：纯内存 sed 多行 YAML 块动态注入引擎（零临时文件）---
update_block() {
    local enable="$1"
    if [ "$enable" = "true" ]; then
        local block
        # 在内存中直接读取文本，并将换行符转为 sed 原生识别的格式（纯内存，无磁盘读写）
        block=$(cat | sed ':a;N;$!ba;s/\n/\\n/g')
        
        # 和 update_list 一模一样的写法：直接一条命令注入到 log-level 下方
        sed -i "/^log-level:.*/a ${block}" "$CONFIG_FILE"
    fi
}

# ----------------------------------------------------
# 执行参数更新（代码高度统一、一目了然）
# ----------------------------------------------------
# 1. 基础单值参数
update_param "mixed-port" "$MIXED_PORT"
update_param "allow-lan" "$ALLOW_LAN"
update_param "ipv6" "$IPV6"
update_param "mode" "$MIHOMO_MODE"

# 2. 认证与白名单列表参数
update_list "authentication" "$AUTHENTICATION"
update_list "skip-auth-prefixes" "$SKIP_AUTH_PREFIXES"

# 3. 仅当 GEO_UPDATE="true" 时，将完整 Geo 更新块插入到 log-level 下方
GEO_VAL="${GEO_UPDATE:-$(printenv GEO-UPDATE 2>/dev/null)}"
update_block "$GEO_VAL" << 'EOF'
geo-auto-update: true
geo-update-interval: 24
geox-url:
  geoip: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
  geosite: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
EOF