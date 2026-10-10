#!/bin/bash

set -e

# ==============================================================================
# 0. 脚本使用规范与函数速查手册 (Multi-line Documentation)
# ==============================================================================
: << 'COMMENT'
[通用函数调用规范]
1. 单值参数更新:
   update_param "键名" "$环境变量值" "插入位置行特征"
   示例: update_param "mixed-port" "$MIXED_PORT" "log-level: error"

2. 列表数组更新:
   update_list "缩进空格数" "键名" "$环境变量值" "插入位置行特征"
   示例: update_list "0" "authentication" "$AUTHENTICATION" "log-level: error"

3. 多行代码块注入:
   update_block "$开关变量" "插入位置行特征" << 'EOF'
   待插入的多行内容
   EOF

4. 特征行及其紧随折号列表级联删除:
   delete_line "行匹配特征"
   示例: delete_line "authentication"

5. 行内单参数原样直替:
   replace_inline_param "环境变量名" "行特征" "参数名" "$环境变量值"
   示例: replace_inline_param "UPDATE_INTERVAL" "Anchor_PR: &Anchor_PR" "interval" "$UPDATE_INTERVAL"
COMMENT

# ==============================================================================
# 一. 路径初始化与内存工作区构建
# ==============================================================================
echo "====> [Init] Initializing configuration generator workspace in memory..."

TEMPLATE_FILE="/app/template_config.yaml"
DEST_CONFIG_FILE="/config/config.yaml"          # 最终落盘的真实存储路径
CONFIG_FILE="/dev/shm/config.yaml.tmp"          # 内存工作文件 (tmpfs 零磁盘磨损)

# 将模板复制到内存空间开始动态渲染
cp -f "$TEMPLATE_FILE" "$CONFIG_FILE"


# ==============================================================================
# 二. 核心动态注入引擎函数库
# ==============================================================================

# --- 通用函数 1：处理单值配置 (如 mixed-port: 7890) ---
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
            # 匹配行内任意位置，插在该行正下方
            sed -i "\|${pattern}|a ${key}: ${val}" "$CONFIG_FILE"
        fi
    fi
}

# --- 通用函数 2：处理多行列表配置 (如 authentication, default-nameserver) ---
update_list() {
    local indent="${1:-0}"    # 缩进空格数 (如 0, 2, 4)
    local key="$2"            # 键名
    local raw_val="$3"        # 逗号分隔的原始值
    local target="$4"         # 插入锚点目标片段

    if [ -n "$raw_val" ] && [ -n "$target" ]; then
        # 1. 动态生成 key 前面的空格
        local key_spaces=""
        [ "$indent" -gt 0 ] 2>/dev/null && key_spaces=$(printf '%*s' "$indent" "")
        
        # 2. 下面的 '-' 列表项自动再后退 2 个空格
        local item_spaces="${key_spaces}  "

        # 3. 动态拼装标准换行的 YAML 文本
        local block="${key_spaces}${key}:"
        IFS=',' read -ra arr <<< "$raw_val"
        for item in "${arr[@]}"; do
            local clean_item
            clean_item=$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$clean_item" ]; then
                block="${block}"$'\n'"${item_spaces}- \"${clean_item}\""
            fi
        done

        # 4. 模糊匹配 target（转义特殊符号，忽略空格差异）
        local pattern
        pattern=$(echo "$target" | sed 's/[]\/$*.^|+[]/\\&/g; s/[[:space:]]\+/[[:space:]]*/g')

        # 5. 使用 sed 的 r 命令从标准输入流读取，保证真实换行与缩进原样保留
        printf '%s\n' "$block" | sed -i "\|${pattern}|r /dev/stdin" "$CONFIG_FILE"
    fi
}

# --- 通用函数 3：多行 YAML 代码块动态注入 (开关控制) ---
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

# --- 通用函数 4：删除所有包含目标特征的行 (支持多行连续删除，连带删除紧随的折号行) ---
delete_line() {
    local target="$1"
    if [ -n "$target" ]; then
        local pattern
        pattern=$(echo "$target" | sed 's/[]\/$*.^|+[]/\\&/g; s/[[:space:]]\+/[[:space:]]*/g')

        sed -i -e "/${pattern}/"' {
            :loop
            $!N
            # 如果下一行依然匹配 pattern，删掉它并继续循环
            /\n.*'"${pattern}"'/{
                s/\n.*//
                b loop
            }
            # 如果下一行是以折号开头的列表项，删掉它并继续循环
            /\n[[:space:]]*-/{
                s/\n[[:space:]]*-[^\n]*//
                b loop
            }
            # 遇到其他普通行：保留该普通行，删掉当前被匹配行
            s/^[^\n]*\n//
            b end
            d
            :end
        }' "$CONFIG_FILE"
    fi
}

# --- 通用函数 5：行内参数原样直替函数 (纯 sed 原生兼容版) ---
replace_inline_param() {
    local env_name="$1"
    local line_target="$2"
    local param_name="$3"
    local new_val="$4"

    # 只要环境变量声明了且值非空，就执行
    if [ -n "$env_name" ] && [ -n "$new_val" ]; then
        # 1. 转义行特征中的特殊符号（特别是 & 符号）并容错空格
        local line_pat
        line_pat=$(echo "$line_target" | sed 's/[]\/$*.^|+&[]/\\&/g; s/[[:space:]]\+/[[:space:]]*/g')

        # 2. 转义参数名中的特殊符号
        local param_pat
        param_pat=$(echo "$param_name" | sed 's/[]\/$*.^|+&[]/\\&/g')

        # 3. 转义新值中的 / 和 & 符号（防止作为 sed 替换词时引发语法错误）
        local safe_new_val
        safe_new_val=$(echo "$new_val" | sed 's/[\/&]/\\&/g')

        # 4. 精准替换：匹配 (参数名:任意空格)(旧值)(可选空格 逗号或右花括号)
        sed -i "\|${line_pat}|s|\(${param_pat}[[:space:]]*:[[:space:]]*\)[^,}[:space:]][^,}]*\([[:space:]]*[,}]\)|\\1${safe_new_val}\\2|" "$CONFIG_FILE"
    fi
}


# ==============================================================================
# 三. 执行环境变量参数渲染与动态注入
# ==============================================================================
echo "====> [Render] Applying environment configurations..."

# 1. 单值基础参数注入
update_param "mixed-port" "$MIXED_PORT" "log-level: error"
update_param "allow-lan" "$ALLOW_LAN" "log-level: error"
update_param "ipv6" "$IPV6" "log-level: error"
update_param "mode" "$MIHOMO_MODE" "log-level: error"

# 2. 列表参数覆盖注入 (先清理后追加)
delete_line "authentication"

# 3. Geo 数据库自动更新配置块注入
GEO_VAL="${GEO_UPDATE:-$(printenv GEO-UPDATE 2>/dev/null)}"
update_block "$GEO_VAL" "log-level: error" << 'EOF'
geo-auto-update: true
geo-update-interval: 24
geox-url:
  geoip: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
  geosite: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
EOF

# 4. 订阅更新周期参数替换 (Flow 格式行内更新)
replace_inline_param "UPDATE_INTERVAL" "Anchor_PR: &Anchor_PR" "interval" "$UPDATE_INTERVAL"

# 5. 动态解析并注入 proxy-providers 节点订阅
delete_line "697726db523"
if [[ -n "$SUB_URL" ]] && [[ "$SUB_URL" == http://* || "$SUB_URL" == https://* ]]; then
    echo "====> [Providers] Injecting proxy-providers from SUB_URL..."
    PROVIDERS_BLOCK=""
    IFS=',' read -ra URL_ARRAY <<< "$SUB_URL"
    count=1
    for url in "${URL_ARRAY[@]}"; do
        url=$(echo "$url" | tr -d ' ')
        if [ -n "$url" ]; then
            # 在首行前面添加反斜杠，防止 sed 吞掉首行缩进
            PROVIDERS_BLOCK="${PROVIDERS_BLOCK}\\
  Provider_${count}: {<<: *Anchor_PR, url: '${url}', override: {additional-prefix: '[Provider_${count}] '}}"
            ((count++))
        fi
    done

    sed -i "\|proxy-providers:|a${PROVIDERS_BLOCK}" "$CONFIG_FILE"
fi


# ==============================================================================
# 四. 内存配置原子落盘与清理
# ==============================================================================
echo "====> [Sync] Writing finalized configuration to storage: $DEST_CONFIG_FILE..."
cp -f "$CONFIG_FILE" "$DEST_CONFIG_FILE"
rm -f "$CONFIG_FILE"

echo "====> [Done] Configuration update workflow completed successfully."