#!/bin/bash

set -e

TEMPLATE_FILE="/app/template_config.yaml"
CONFIG_DIR="/config"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

cp -f "$TEMPLATE_FILE" "$CONFIG_FILE"

# ==========================================
# 2. 环境变量参数动态注入引擎
# ==========================================
# --- 通用函数 1：处理单值配置 (类似于：mixed-port: 7890) ---
update_param() {
    local key="$1"
    local val="$2"
    local target="$3"

    if [ -n "$val" ]; then
        if grep -q "^${key}:" "$CONFIG_FILE"; then
            # 规则 1：模板已有该参数，原地精准替换
            sed -i "s|^${key}:.*|${key}: ${val}|" "$CONFIG_FILE"
        elif [ -n "$target" ]; then
            # 规则 2：转义特殊符号，并将空格转为 [[:space:]]* (任意空格容错)
            local pattern
            pattern=$(echo "$target" | sed 's/[]\/$*.^|+[]/\\&/g; s/[[:space:]]\+/[[:space:]]*/g')
            # 使用 \| 作为定界符，匹配行内任意位置，插在该行正下方
            sed -i "\|${pattern}|a ${key}: ${val}" "$CONFIG_FILE"
        fi
    fi
}

# --- 通用函数 2：处理多行配置
# 类似于：
# default-nameserver:
#   - 223.5.5.5          
#   - 114.114.114.114
#   - 119.29.29.29
update_list() {
    local indent="${1:-0}"    # 参数 1：缩进空格数 (如 0, 2, 4)
    local key="$2"            # 参数 2：键名 (如 "authentication", "default-nameserver")
    local raw_val="$3"        # 参数 3：逗号分隔的原始值
    local target="$4"         # 参数 4：插入锚点目标片段

    if [ -n "$raw_val" ] && [ -n "$target" ]; then
        # 1. 动态生成 key 前面的空格
        local key_spaces=""
        [ "$indent" -gt 0 ] 2>/dev/null && key_spaces=$(printf '%*s' "$indent" "")
        
        # 2. 下面的 '-' 列表项自动再后退 2 个空格
        local item_spaces="${key_spaces}  "

        # 3. 拼装带动态缩进的 YAML 文本块
        local block="${key_spaces}${key}:"
        IFS=',' read -ra arr <<< "$raw_val"
        for item in "${arr[@]}"; do
            block="${block}\n${item_spaces}- \"$(echo "$item" | tr -d ' ')\""
        done

        # 4. 模糊匹配 target，并在其正下方插入
        local pattern
        pattern=$(echo "$target" | sed 's/[]\/$*.^|+[]/\\&/g; s/[[:space:]]\+/[[:space:]]*/g')
        sed -i "\|${pattern}|a ${block}" "$CONFIG_FILE"
    fi
}

# --- 通用函数 3：多行 YAML 块动态注入
update_block() {
    local enable="$1"
    local target="$2"

    if [ "$enable" = "true" ] && [ -n "$target" ]; then
        local block
        block=$(cat | sed ':a;N;$!ba;s/\n/\\n/g')
        
        local pattern
        pattern=$(echo "$target" | sed 's/[]\/$*.^|+[]/\\&/g; s/[[:space:]]\+/[[:space:]]*/g')
        sed -i "\|${pattern}|a ${block}" "$CONFIG_FILE"
    fi
}

# --- 通用函数 4：纯 sed 删除目标行及其紧随的所有折号列表项
delete_line() {
    local target="$1"
    if [ -n "$target" ]; then
        # 1. 模糊匹配正则转义
        local pattern
        pattern=$(echo "$target" | sed 's/[]\/$*.^|+[]/\\&/g; s/[[:space:]]\+/[[:space:]]*/g')

        # 2. 纯 sed 高级多行循环删除（向下吃掉所有紧随的折号行，遇到非折号立刻刹车）
        sed -i -e "/${pattern}/"' {
            :loop
            $!N
            /\n[[:space:]]*-/{
                s/\n[[:space:]]*-[^\n]*//
                t loop
            }
            s/^[^\n]*\n//
            t
            d
        }' "$CONFIG_FILE"
    fi
}

# --- 通用函数 5：行内参数原样直替函数 ---
# 仅匹配两种情况：
# 1) key: 旧值,
# 2) key: 旧值}
# 用法: replace_inline_param "环境变量" "行特征" "参数名" "$环境变量值"
replace_inline_param() {
    local env_name="$1"
    local line_target="$2"
    local param_name="$3"
    local new_val="$4"

    if [ -n "$env_name" ] && [ -n "$new_val" ]; then
        awk -v target="$line_target" -v key="$param_name" -v val="$new_val" '
        BEGIN {
            # 处理行特征正则：特殊符号转义，支持空格模糊匹配
            gsub(/[\[\]\/$*.^|+(){}?]/, "\\\\&", target)
            gsub(/[ \t]+/, "[ \\t]+", target)
            # 处理参数名正则
            gsub(/[\[\]\/$*.^|+(){}?]/, "\\\\&", key)
        }
        {
            # 找到包含行特征的行
            if ($0 ~ target) {
                # 严格匹配: (key:[任意空格]) (旧值，直到遇到逗号或右花括号) (逗号或右花括号)
                regex = "(" key "[ \t]*:[ \t]*)([^,}]+)([,}])"
                if (match($0, regex)) {
                    p = gensub(regex, "\\1", 1, $0)
                    s = gensub(regex, "\\3", 1, $0)
                    # 无论 val 是什么直接原样填入：前缀 + val + 后缀
                    $0 = gensub(regex, p val s, 1, $0)
                }
            }
            print $0
        }
        ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv -f "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi
}



# ----------------------------------------------------
# 执行参数更新（显式声明插入目标）
# ----------------------------------------------------
# 1. 传入单值，有则原位替代，没有则加到指定行之后
update_param "mixed-port" "$MIXED_PORT" "log-level: error"
update_param "allow-lan" "$ALLOW_LAN" "log-level: error"
update_param "ipv6" "$IPV6" "log-level: error"
update_param "mode" "$MIHOMO_MODE" "log-level: error"

# 2. 传入列表，完全覆盖
delete_line "authentication"
update_list "0" "authentication" "$AUTHENTICATION" "log-level: error"
delete_line "skip-auth-prefixes"
update_list "0" "skip-auth-prefixes" "$SKIP_AUTH_PREFIXES" "log-level: error"



# 4. Geo 块注入：直接匹配 "log-level: error" 插在下方：
GEO_VAL="${GEO_UPDATE:-$(printenv GEO-UPDATE 2>/dev/null)}"
update_block "$GEO_VAL" "log-level: error" << 'EOF'
geo-auto-update: true
geo-update-interval: 24
geox-url:
  geoip: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
  geosite: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
EOF


# ==========================================
# 2. 动态拼装并直接注入 proxy-providers
# ==========================================
delete_line "697726db523"
if [[ -n "$SUB_URL" ]] && [[ "$SUB_URL" == http://* || "$SUB_URL" == https://* ]]; then
    echo "====> Injecting proxy-providers from SUB_URL..."
    PROVIDERS_BLOCK=""
    IFS=',' read -ra URL_ARRAY <<< "$SUB_URL"
    count=1
    for url in "${URL_ARRAY[@]}"; do
        url=$(echo "$url" | tr -d ' ')
        if [ -n "$url" ]; then
            # 动态拼装，前面保留 2 个空格缩进，末尾带 \n 换行
            PROVIDERS_BLOCK="${PROVIDERS_BLOCK}  Provider_${count}: {<<: *Anchor_PR, url: '${url}', override: {additional-prefix: '[Provider_${count}] '}}\n"
            ((count++))
        fi
    done
    # 👉【核心变动】：彻底告别 awk，直接一条 sed 插在 proxy-providers: 正下方
    sed -i "\|proxy-providers:|a ${PROVIDERS_BLOCK}" "$CONFIG_FILE"
fi

# ==========================================
# 动态计算并更新订阅拉取周期 (小时 -> 秒)
# ==========================================
replace_inline_param "UPDATE_INTERVAL" "Anchor_PR: &Anchor_PR" "interval" "$UPDATE_INTERVAL"