#!/bin/bash
# Caddy 自动更新脚本
# 用于定时检查和更新 Caddy 到最新版本

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/caddy-auto-update.log
}

# 错误处理
error_exit() {
    log "❌ 错误: $1"
    exit 1
}

# 获取本地版本
get_local_version() {
    if command -v caddy >/dev/null 2>&1; then
        caddy version 2>/dev/null | awk '{print $1}' || echo "unknown"
    else
        echo "not_installed"
    fi
}

# 获取最新版本
get_latest_version() {
    curl -s https://api.github.com/repos/simtelboy/eye/releases/latest | jq -r '.tag_name' 2>/dev/null || echo "unknown"
}

# 获取最新版本的文件名
get_latest_filename() {
    local latest_version=$(get_latest_version)
    if [[ "$latest_version" != "unknown" && -n "$latest_version" ]]; then
        echo "caddy-${latest_version}-linux-amd64"
    else
        echo "caddy"
    fi
}

# 重试下载函数
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_delay=5
    
    for ((i=1; i<=max_retries; i++)); do
        log "尝试下载 (第 $i 次): $url"
        
        if wget --timeout=30 --tries=3 -O "$output" "$url"; then
            log "✅ 下载成功: $output"
            return 0
        else
            log "❌ 下载失败 (第 $i 次)"
            if [[ $i -lt $max_retries ]]; then
                log "等待 $retry_delay 秒后重试..."
                sleep $retry_delay
            fi
        fi
    done
    
    log "❌ 下载失败，已重试 $max_retries 次: $url"
    return 1
}

# 下载并更新天神之眼 Caddy
update_caddy() {
    local filename=$(get_latest_filename)
    local download_url="https://github.com/simtelboy/eye/releases/latest/download/$filename"
    local temp_file="/tmp/caddy_update_$$"

    log "下载天神之眼最新版本: $filename"
    log "下载地址: $download_url"

    if download_with_retry "$download_url" "$temp_file"; then
        log "下载成功，开始更新天神之眼..."

        # 检查下载的文件是否有效
        if [[ ! -f "$temp_file" ]] || [[ ! -s "$temp_file" ]]; then
            error_exit "下载的文件无效或为空"
        fi

        # 停止服务
        log "停止天神之眼服务..."
        systemctl stop caddy || log "警告: 停止服务失败，继续更新..."

        # 备份当前版本
        if [[ -f "/usr/bin/caddy" ]]; then
            local backup_file="/usr/bin/caddy.backup.$(date +%s)"
            cp /usr/bin/caddy "$backup_file" 2>/dev/null || log "警告: 备份失败"
            log "当前版本已备份到: $backup_file"
        fi

        # 安装新版本
        log "安装天神之眼新版本..."
        cp "$temp_file" /usr/bin/caddy || error_exit "安装新版本失败"
        chmod +x /usr/bin/caddy || error_exit "设置权限失败"

        # 验证安装
        local new_version=$(get_local_version)
        log "天神之眼新版本验证: $new_version"

        # 启动服务
        log "启动天神之眼服务..."
        systemctl start caddy || error_exit "启动服务失败"

        # 检查服务状态
        sleep 3
        if systemctl is-active --quiet caddy; then
            log "✅ 天神之眼服务启动成功"
        else
            log "❌ 天神之眼服务启动失败，检查配置"
            systemctl status caddy --no-pager
        fi

        # 清理临时文件
        rm -f "$temp_file"

        log "✅ 天神之眼更新完成: $new_version"
        return 0
    else
        log "❌ 天神之眼下载失败"
        rm -f "$temp_file"
        return 1
    fi
}

# 比较版本号
compare_versions() {
    local local_version="$1"
    local latest_version="$2"
    
    if [[ "$local_version" == "not_installed" ]]; then
        echo "1"  # 需要安装
        return
    fi
    
    if [[ "$local_version" == "unknown" || "$latest_version" == "unknown" ]]; then
        echo "0"  # 无法比较
        return
    fi
    
    # 使用 sort -V 进行语义版本比较
    if [[ $(echo -e "$local_version\n$latest_version" | sort -V | head -n1) == "$local_version" ]]; then
        if [[ "$local_version" == "$latest_version" ]]; then
            echo "0"  # 相等
        else
            echo "1"  # local < latest
        fi
    else
        echo "-1"  # local > latest
    fi
}

# 主逻辑
main() {
    log "========== 天神之眼自动更新开始 =========="
    
    # 检查必要工具
    for tool in curl jq wget systemctl; do
        if ! command -v $tool >/dev/null 2>&1; then
            error_exit "缺少必要工具: $tool"
        fi
    done
    
    local_version=$(get_local_version)
    latest_version=$(get_latest_version)
    
    log "本地版本: $local_version"
    log "最新版本: $latest_version"
    
    if [[ "$local_version" == "not_installed" ]]; then
        log "天神之眼未安装，跳过更新"
        exit 0
    fi
    
    if [[ "$local_version" == "unknown" || "$latest_version" == "unknown" ]]; then
        log "无法获取版本信息，跳过更新"
        exit 0
    fi
    
    # 比较版本
    comparison_result=$(compare_versions "$local_version" "$latest_version")
    
    if [[ "$comparison_result" == "1" ]]; then
        log "发现新版本，开始更新..."
        if update_caddy; then
            log "✅ 自动更新成功"
        else
            log "❌ 自动更新失败"
            exit 1
        fi
    else
        log "当前版本为最新，无需更新"
    fi
    
    log "========== 天神之眼自动更新完成 =========="
}

# 执行主函数
main "$@"
