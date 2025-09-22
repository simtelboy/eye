#!/bin/bash
# 设置天神之眼自动更新功能的安装脚本

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
none='\033[0m'

# 日志函数
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 错误处理
error_exit() {
    echo -e "${red}❌ 错误: $1${none}"
    exit 1
}

# 简化版：直接使用北京时间，无需转换
get_beijing_time_schedule() {
    local hour="$1"
    local min="${2:-0}"
    printf "Sun *-*-* %02d:%02d:00" "$hour" "$min"
}

# 安装自动更新功能
install_auto_update() {
    log "开始设置天神之眼自动更新功能..."
    
    # 检查是否为 root 用户
    if [[ $EUID -ne 0 ]]; then
        error_exit "此脚本需要 root 权限运行"
    fi
    
    # 检查必要工具
    for tool in curl jq wget systemctl; do
        if ! command -v $tool >/dev/null 2>&1; then
            log "安装缺少的工具: $tool"
            apt update && apt install -y $tool || error_exit "无法安装 $tool"
        fi
    done
    
    # 复制自动更新脚本到系统目录
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local updater_script="$script_dir/caddy-auto-updater.sh"
    
    if [[ ! -f "$updater_script" ]]; then
        error_exit "找不到自动更新脚本: $updater_script"
    fi
    
    log "复制自动更新脚本到系统目录..."
    cp "$updater_script" /usr/local/bin/caddy-auto-updater.sh || error_exit "复制脚本失败"
    chmod +x /usr/local/bin/caddy-auto-updater.sh || error_exit "设置权限失败"
    
    # 创建 systemd 服务
    log "创建 systemd 服务..."
    cat > /etc/systemd/system/caddy-auto-update.service << EOF
[Unit]
Description=Caddy Auto Update Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/caddy-auto-updater.sh
User=root
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF

    # 计算正确的服务器时间（本地时间周日4点对应的服务器时间）
    local server_time=$(get_beijing_time_schedule 4 0)  # 本地时间4:00
    
    log "计算的服务器执行时间: $server_time"
    
    # 创建 systemd 定时器
    log "创建 systemd 定时器..."
    cat > /etc/systemd/system/caddy-auto-update.timer << EOF
[Unit]
Description=Run Caddy Auto Update Weekly
Requires=caddy-auto-update.service

[Timer]
OnCalendar=$server_time
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # 启用定时器
    log "启用定时器..."
    systemctl daemon-reload || error_exit "重新加载 systemd 失败"
    systemctl enable caddy-auto-update.timer || error_exit "启用定时器失败"
    systemctl start caddy-auto-update.timer || error_exit "启动定时器失败"
    
    log "✅ 自动更新设置完成"
    echo
    echo -e "${green}========== 设置完成 ==========${none}"
    echo -e "${yellow}定时器将在每周日凌晨4点（本地时间）检查更新${none}"
    echo -e "${yellow}对应服务器时间: $server_time${none}"
    echo
    echo "管理命令:"
    echo "  查看定时器状态: systemctl status caddy-auto-update.timer"
    echo "  查看更新日志:   tail -f /var/log/caddy-auto-update.log"
    echo "  手动执行更新:   /usr/local/bin/caddy-auto-updater.sh"
    echo "  停止定时器:     systemctl stop caddy-auto-update.timer"
    echo "  禁用定时器:     systemctl disable caddy-auto-update.timer"
    echo
    
    # 显示下次执行时间
    echo "下次执行时间:"
    systemctl list-timers caddy-auto-update.timer --no-pager 2>/dev/null || echo "无法获取定时器信息"
}

# 删除自动更新功能
remove_auto_update() {
    log "开始删除天神之眼自动更新功能..."
    
    # 检查是否为 root 用户
    if [[ $EUID -ne 0 ]]; then
        error_exit "此脚本需要 root 权限运行"
    fi
    
    # 停止并禁用定时器
    log "停止并禁用定时器..."
    systemctl stop caddy-auto-update.timer 2>/dev/null || true
    systemctl disable caddy-auto-update.timer 2>/dev/null || true
    
    # 删除文件
    log "删除相关文件..."
    rm -f /etc/systemd/system/caddy-auto-update.service
    rm -f /etc/systemd/system/caddy-auto-update.timer
    rm -f /usr/local/bin/caddy-auto-updater.sh
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    log "✅ 自动更新功能已删除"
}

# 显示帮助信息
show_help() {
    echo "天神之眼自动更新设置脚本"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  install   安装自动更新功能"
    echo "  remove    删除自动更新功能"
    echo "  status    查看自动更新状态"
    echo "  help      显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0 install    # 安装自动更新"
    echo "  $0 remove     # 删除自动更新"
    echo "  $0 status     # 查看状态"
}

# 查看状态
show_status() {
    echo "========== 天神之眼自动更新状态 =========="
    
    if systemctl is-active --quiet caddy-auto-update.timer; then
        echo -e "${green}✅ 自动更新定时器正在运行${none}"
    else
        echo -e "${red}❌ 自动更新定时器未运行${none}"
    fi
    
    echo
    echo "定时器详细状态:"
    systemctl status caddy-auto-update.timer --no-pager 2>/dev/null || echo "定时器未安装"
    
    echo
    echo "下次执行时间:"
    systemctl list-timers caddy-auto-update.timer --no-pager 2>/dev/null || echo "无法获取定时器信息"
    
    echo
    echo "最近的更新日志:"
    if [[ -f "/var/log/caddy-auto-update.log" ]]; then
        tail -10 /var/log/caddy-auto-update.log
    else
        echo "暂无更新日志"
    fi
}

# 主逻辑
case "${1:-help}" in
    install)
        install_auto_update
        ;;
    remove)
        remove_auto_update
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "未知选项: $1"
        show_help
        exit 1
        ;;
esac
