#!/bin/bash
# 改进版天神之眼管理脚本
# 强制设置终端支持颜色
export TERM=xterm-256color


# 一键安装
# apt update
# apt install -y curl
# bash <(curl -L https://raw.githubusercontent.com/simtelboy/eye/refs/heads/main/caddy-auto-updater/caddy_manager_improved.sh)
# 
# 一条语句安装: apt update -y && apt install -y curl && bash <(curl -L https://raw.githubusercontent.com/simtelboy/eye/refs/heads/main/caddy-auto-updater/caddy_manager_improved.sh)


# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
magenta='\033[0;35m'
cyan='\033[0;36m'
none='\033[0m'
_red() { echo -e ${red}$*${none}; }
_green() { echo -e ${green}$*${none}; }
_yellow() { echo -e ${yellow}$*${none}; }
_magenta() { echo -e ${magenta}$*${none}; }
_cyan() { echo -e ${cyan}$*${none}; }

# 错误处理
error() {
    echo -e "\n$red 输入错误! $none\n"
}

# 日志函数
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
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

# 获取最新版本的实际文件名
get_latest_caddy_filename() {
    local latest_version=$(curl -s https://api.github.com/repos/simtelboy/eye/releases/latest | jq -r '.tag_name')
    if [[ "$latest_version" != "null" && -n "$latest_version" ]]; then
        echo "caddy-${latest_version}-linux-amd64"
    else
        echo "caddy"  # 回退到默认名称
    fi
}

# 下载天神之眼 Caddy（用于安装）
download_caddy_for_install() {
    local temp_dir="/tmp/caddy_install_$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    log "获取最新版本信息..."
    local filename=$(get_latest_caddy_filename)
    local download_url="https://github.com/simtelboy/eye/releases/latest/download/$filename"

    log "下载天神之眼 Caddy: $filename"
    if download_with_retry "$download_url" "$filename"; then
        log "重命名文件为 caddy..."
        mv "$filename" "caddy"
        chmod +x "caddy"

        log "执行天神之眼一键安装..."
        if ./caddy install; then
            log "✅ 天神之眼安装成功"
            cd /
            rm -rf "$temp_dir"
            return 0
        else
            log "❌ 天神之眼安装失败"
            cd /
            rm -rf "$temp_dir"
            return 1
        fi
    else
        log "❌ 天神之眼 Caddy 下载失败"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
}

# 下载天神之眼 Caddy（用于升级）
download_and_install_caddy() {
    local temp_dir="/tmp/caddy_upgrade_$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    log "获取最新版本信息..."
    local filename=$(get_latest_caddy_filename)
    local download_url="https://github.com/simtelboy/eye/releases/latest/download/$filename"

    log "下载天神之眼 Caddy: $filename"
    if download_with_retry "$download_url" "$filename"; then
        log "升级天神之眼 Caddy..."

        # 停止服务
        systemctl stop caddy 2>/dev/null || true

        # 备份旧版本
        if [[ -f "/usr/bin/caddy" ]]; then
            cp /usr/bin/caddy /usr/bin/caddy.backup.$(date +%s) 2>/dev/null || true
            log "当前版本已备份"
        fi

        # 替换新版本
        cp "$filename" /usr/bin/caddy
        chmod +x /usr/bin/caddy

        log "✅ 天神之眼 Caddy 升级成功"

        # 清理临时文件
        cd /
        rm -rf "$temp_dir"
        return 0
    else
        log "❌ 天神之眼 Caddy 下载失败"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
}

# 天神之眼单文件版本不需要额外文件，配置已嵌入
# 此函数保留用于兼容性，但实际不执行任何操作
download_and_extract_files() {
    log "天神之眼单文件版本，配置文件已嵌入，无需额外下载"
    return 0
}

# 获取本地Caddy版本
get_local_caddy_version() {
    if command -v caddy >/dev/null 2>&1; then
        caddy version 2>/dev/null | awk '{print $1}' || echo "unknown"
    else
        echo "not_installed"
    fi
}

# 获取GitHub上最新的Caddy版本
get_latest_caddy_version() {
    curl -s https://api.github.com/repos/simtelboy/eye/releases/latest | jq -r '.tag_name' 2>/dev/null || echo "unknown"
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

# 暂停函数
pause() {
    read -rsp "$(echo -e "按 $green Enter 回车键 $none 继续....或按 $red Ctrl + C $none 取消.")" -d $'\n'
    echo
}

sleep 1
# 显示"天神之眼"的ASCII艺术（金色）
echo -e "${yellow}             #      #       #            #                      #    \n #############      #      #             #             # ########   \n       #            #      #  #          #          ######     #    \n       #         ###### ########                    #  # #     #    \n       #             #  #  #  #    ############     #  # #######    \n       #     #      #   #  #  #              #      #  # #     #    \n###############    ###  #  #  #             #       #### #     #    \n       #          # # # #######            #        #  # #######    \n      # #        #  #   #  #  #           #         #  # # #    #   \n      # #           #   #  #  #          #          #### # #   #    \n     #   #          #   #  #  #         #           #  # #  # #     \n     #   #          #   #######       ##            #  # #   #      \n    #     #         #   #  #  #     ##              #  # #    #     \n   #       #        #      #       #  #        ##   #### # #   ###  \n  #         ###     #      #           #########    #  # ##     #   \n##           #      #      #                             #    ${none}"

echo
echo -e "$yellow此脚本仅兼容于Debian 10+系统. 如果你的系统不符合,请Ctrl+C退出脚本$none"

# 显示菜单
show_menu() {
    echo -e "${yellow}请选择操作：${none}"
    echo -e "${green}1: 安装【天神之眼】单文件版${none}"
    echo -e "${green}2: 升级天神之眼核心程序${none}"
    echo -e "${green}3: 升级天神之眼（与选项2相同，配置已嵌入）${none}"
    echo -e "${green}4: 卸载所有${none}"
    echo -e "${green}5: 查看天神之眼状态${none}"
    echo -e "${green}6: 设置自动更新${none}"
    echo -e "${green}7: 删除自动更新${none}"
    echo -e "${green}8: 退出（Ctrl+C）${none}"
    read -p "请输入选项 (1/2/3/4/5/6/7/8): " choice
}

# 检查 Caddy 状态
check_caddy_status() {
    # 获取 Caddy 的进程 ID
    CADDY_PID=$(pgrep -f caddy)

    if [ -z "$CADDY_PID" ]; then
        echo -e "${red}未找到正在运行的 Caddy 进程${none}"
        return 1
    fi

    echo -e "${yellow}=== 天神之眼 进程监控 ===${none}"
    echo "进程 PID: $CADDY_PID"
    echo ""

    # 获取 CPU 和内存使用情况（通过 /proc）
    echo "1. CPU 和内存占用:"
    cpu_times=$(cat /proc/"$CADDY_PID"/stat 2>/dev/null | awk '{print $14 + $15 + $16 + $17}') # utime + stime + cutime + cstime
    total_cpu=$(cat /proc/stat 2>/dev/null | grep '^cpu ' | awk '{print $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9 + $10}')
    if [ -n "$cpu_times" ] && [ -n "$total_cpu" ] && [ "$total_cpu" -gt 0 ]; then
        cpu_usage=$((cpu_times * 100 / total_cpu))
        cpu_display="$cpu_usage%"
    else
        cpu_display="无法获取"
    fi
    rss=$(grep "VmRSS" /proc/"$CADDY_PID"/status 2>/dev/null | awk '{print $2}') # Resident Set Size (KB)
    total_mem=$(grep "MemTotal" /proc/meminfo 2>/dev/null | awk '{print $2}') # Total memory (KB)
    if [ -n "$rss" ] && [ -n "$total_mem" ] && [ "$total_mem" -gt 0 ]; then
        mem_usage=$((rss * 100 / total_mem))
        mem_display="$mem_usage% ($rss KB / $total_mem KB)"
    else
        mem_display="无法获取"
    fi
    echo "CPU 使用率: $cpu_display"
    echo "内存使用率: $mem_display"
    echo ""

    # 获取线程数
    echo "2. 线程数:"
    threads=$(cat /proc/"$CADDY_PID"/status 2>/dev/null | grep "Threads" | awk '{print $2}')
    echo "线程数: ${threads:-无法获取}"
    echo ""

    # 获取运行时间
    echo "3. 进程运行时间:"
    start_time=$(cat /proc/"$CADDY_PID"/stat 2>/dev/null | awk '{print $22}') # 以 jiffies 为单位
    jiffies_per_sec=$(getconf CLK_TCK 2>/dev/null) # 系统每秒 jiffies 数，通常是 100
    current_time=$(cat /proc/uptime 2>/dev/null | awk '{print $1}' | cut -d'.' -f1) # 系统运行时间（秒）
    if [ -n "$start_time" ] && [ -n "$jiffies_per_sec" ] && [ -n "$current_time" ] && [ "$jiffies_per_sec" -gt 0 ]; then
        elapsed_sec=$((current_time - start_time / jiffies_per_sec))
        days=$((elapsed_sec / 86400))
        hours=$(((elapsed_sec % 86400) / 3600))
        mins=$(((elapsed_sec % 3600) / 60))
        secs=$((elapsed_sec % 60))
        runtime=$(printf "%d-%02d:%02d:%02d" "$days" "$hours" "$mins" "$secs")
    else
        runtime="无法获取"
    fi
    echo "运行时间: $runtime"
    echo ""

    echo -e "${yellow}=== 监控完成 ===${none}"
}

# 计算服务器时间对应的本地时间
calculate_server_time_for_local() {
    local local_hour="$1"
    local local_min="${2:-0}"

    # 获取服务器时区偏移（小时）
    local server_offset_str=$(date +%z)
    local server_offset_hours=$((${server_offset_str:1:2}))
    if [[ "${server_offset_str:0:1}" == "-" ]]; then
        server_offset_hours=$((0 - server_offset_hours))
    fi

    # 假设用户在 UTC+8 时区（中国时间）
    local user_offset_hours=8

    # 计算时差
    local time_diff=$((server_offset_hours - user_offset_hours))

    # 计算服务器时间
    local server_hour=$((local_hour + time_diff))
    local server_day="Sun"

    # 处理跨日期
    if [[ $server_hour -lt 0 ]]; then
        server_hour=$((server_hour + 24))
        server_day="Sat"
    elif [[ $server_hour -ge 24 ]]; then
        server_hour=$((server_hour - 24))
        server_day="Mon"
    fi

    printf "%s *-*-* %02d:%02d:00" "$server_day" "$server_hour" "$local_min"
}

# 自动更新功能
setup_auto_update() {
    log "设置自动更新功能..."

    # 尝试下载独立的自动更新脚本
    local updater_url="https://raw.githubusercontent.com/simtelboy/eye/main/caddy-auto-updater/caddy-auto-updater.sh"
    local temp_updater="/tmp/caddy-auto-updater.sh"

    log "尝试下载独立的自动更新脚本..."
    if download_with_retry "$updater_url" "$temp_updater"; then
        log "✅ 下载独立脚本成功，使用独立版本"
        cp "$temp_updater" /usr/local/bin/caddy-auto-updater.sh
        chmod +x /usr/local/bin/caddy-auto-updater.sh
        rm -f "$temp_updater"
    else
        log "⚠️ 下载独立脚本失败，使用内嵌版本"
        # 创建内嵌的自动更新脚本
        cat > /usr/local/bin/caddy-auto-updater.sh << 'EOF'
#!/bin/bash
# Caddy 自动更新脚本

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/caddy-auto-update.log
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

# 下载并更新
update_caddy() {
    local filename=$(get_latest_filename)
    local download_url="https://github.com/simtelboy/eye/releases/latest/download/$filename"
    local temp_file="/tmp/caddy_update_$$"

    log "下载最新版本: $filename"

    if wget --timeout=30 --tries=3 -O "$temp_file" "$download_url"; then
        log "下载成功，开始更新..."

        # 停止服务
        systemctl stop caddy

        # 备份当前版本
        cp /usr/bin/caddy "/usr/bin/caddy.backup.$(date +%s)" 2>/dev/null || true

        # 安装新版本
        cp "$temp_file" /usr/bin/caddy
        chmod +x /usr/bin/caddy

        # 启动服务
        systemctl start caddy

        # 清理临时文件
        rm -f "$temp_file"

        log "✅ Caddy 更新完成"
        return 0
    else
        log "❌ 下载失败"
        rm -f "$temp_file"
        return 1
    fi
}

# 主逻辑
main() {
    log "开始检查 Caddy 更新..."

    local_version=$(get_local_version)
    latest_version=$(get_latest_version)

    log "本地版本: $local_version"
    log "最新版本: $latest_version"

    if [[ "$local_version" == "not_installed" ]]; then
        log "Caddy 未安装，跳过更新"
        exit 0
    fi

    if [[ "$local_version" == "unknown" || "$latest_version" == "unknown" ]]; then
        log "无法获取版本信息，跳过更新"
        exit 0
    fi

    # 比较版本
    if [[ $(echo -e "$local_version\n$latest_version" | sort -V | head -n1) == "$local_version" ]] && [[ "$local_version" != "$latest_version" ]]; then
        log "发现新版本，开始更新..."
        if update_caddy; then
            log "✅ 自动更新成功"
        else
            log "❌ 自动更新失败"
        fi
    else
        log "当前版本为最新，无需更新"
    fi
}

main "$@"
EOF
        chmod +x /usr/local/bin/caddy-auto-updater.sh
    fi

    # 创建 systemd 服务
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
    local server_time=$(calculate_server_time_for_local 4 0)  # 本地时间4:00

    # 创建 systemd 定时器
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
    systemctl daemon-reload
    systemctl enable caddy-auto-update.timer
    systemctl start caddy-auto-update.timer

    log "✅ 自动更新设置完成"
    log "定时器将在每周日凌晨4点检查更新"
    log "查看定时器状态: systemctl status caddy-auto-update.timer"
    log "查看更新日志: tail -f /var/log/caddy-auto-update.log"
}

# 删除自动更新
remove_auto_update() {
    log "删除自动更新功能..."

    # 停止并禁用定时器
    systemctl stop caddy-auto-update.timer 2>/dev/null || true
    systemctl disable caddy-auto-update.timer 2>/dev/null || true

    # 删除文件
    rm -f /etc/systemd/system/caddy-auto-update.service
    rm -f /etc/systemd/system/caddy-auto-update.timer
    rm -f /usr/local/bin/caddy-auto-updater.sh

    # 重新加载 systemd
    systemctl daemon-reload

    log "✅ 自动更新功能已删除"
}

# 安装天神之眼（单文件版本）
install_caddy() {
    echo -e "${yellow}开始安装天神之眼单文件版...${none}"

    # 执行脚本带参数处理
    if [ $# -ge 1 ]; then
        naive_domain=${1}
        case ${2} in
        4) netstack=4 ;;
        6) netstack=6 ;;
        *) netstack="i" ;;
        esac
        naive_port=${3:-443}
        naive_user="haoge"
        naive_pass="123456789kt"
        naive_fakeweb=${6}

        echo -e "域名:${naive_domain}"
        echo -e "网域栈:${netstack}"
        echo -e "端口:${naive_port}"
        echo -e "用户名:${naive_user}"
        echo -e "密码:${naive_pass}"
        echo -e "伪装:${naive_fakeweb}"
    else
        naive_user="DivineEye"
        naive_pass="DivineEye"
    fi

    pause

    # 准备
    log "更新系统包..."
    apt update
    apt install -y sudo curl wget git jq qrencode

    echo
    echo -e "$yellow下载并安装天神之眼$none"
    echo "----------------------------------------------------------------"

    # 使用天神之眼一键安装
    if download_caddy_for_install; then
        echo -e "${green}✅ 天神之眼安装成功！${none}"

        # 询问是否设置自动更新
        echo
        echo -e "${yellow}是否设置自动更新功能？${none}"
        echo "自动更新将在每周日凌晨4点检查并更新到最新版本"
        read -p "$(echo -e "输入 ${cyan}y${none} 设置自动更新，${cyan}n${none} 跳过 [y/n]: ")" setup_auto
        if [[ "$setup_auto" == "y" || "$setup_auto" == "Y" ]]; then
            setup_auto_update
        fi

        return 0
    else
        echo -e "${red}❌ 天神之眼安装失败，请检查错误信息${none}"
        return 1
    fi

    # 天神之眼单文件版本已经完成安装，无需额外配置
}

# 天神之眼单文件版本不需要手动配置，所有配置都通过 caddy install 自动完成

# 升级天神之眼 Caddy
upgrade_caddy() {
    pause
    echo -e "${yellow}开始检查天神之眼版本...${none}"

    local_version=$(get_local_caddy_version)
    latest_version=$(get_latest_caddy_version)

    echo -e "本地版本: ${cyan}$local_version${none}"
    echo -e "服务器最新版本: ${cyan}$latest_version${none}"

    comparison_result=$(compare_versions "$local_version" "$latest_version")

    if [[ "$comparison_result" == "1" ]]; then
        echo -e "${yellow}发现新版本，开始升级天神之眼...${none}"
        if download_and_install_caddy; then
            systemctl daemon-reload
            systemctl restart caddy
            echo -e "${green}天神之眼升级完成！${none}"
        else
            echo -e "${red}天神之眼升级失败！${none}"
        fi
    else
        echo -e "${green}当前版本为最新，无需升级。${none}"
        echo -e "${yellow}是否强制重新安装最新版本？${none}"
        read -p "$(echo -e "输入 ${cyan}y${none} 强制升级，${cyan}n${none} 退出 [y/n]: ")" force_upgrade
        if [[ "$force_upgrade" == "y" || "$force_upgrade" == "Y" ]]; then
            echo -e "${yellow}开始强制升级天神之眼...${none}"
            if download_and_install_caddy; then
                systemctl daemon-reload
                systemctl restart caddy
                echo -e "${green}天神之眼强制升级完成！${none}"
            else
                echo -e "${red}天神之眼强制升级失败！${none}"
            fi
        else
            echo -e "${yellow}取消升级，返回菜单。${none}"
        fi
    fi
}

# 天神之眼单文件版本：升级核心程序（与选项2相同，因为配置已嵌入）
upgrade_caddy_and_files() {
    echo -e "${yellow}天神之眼单文件版本，配置文件已嵌入，执行核心程序升级...${none}"
    upgrade_caddy
}

# 卸载所有
uninstall_all() {
    pause
    echo -e "${yellow}开始卸载相关文件...${none}"

    # 停止服务
    systemctl stop caddy 2>/dev/null || true
    systemctl disable caddy 2>/dev/null || true

    # 删除自动更新
    remove_auto_update

    # 删除用户和组
    userdel caddy 2>/dev/null || true
    groupdel caddy 2>/dev/null || true

    # 删除文件
    rm -rf /etc/caddy 2>/dev/null || true
    rm -f /etc/systemd/system/caddy.service 2>/dev/null || true
    rm -f /usr/bin/caddy 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/caddy-stable.list 2>/dev/null || true
    rm -rf /var/lib/caddy 2>/dev/null || true
    rm -rf /var/www/xkcdpw-html 2>/dev/null || true
    rm -f ~/_naive_url_ 2>/dev/null || true

    # 清理包
    apt remove -y caddy 2>/dev/null || true

    systemctl daemon-reload
    echo -e "${green}卸载已完成！${none}"
}

# 主逻辑
while true; do
    show_menu
    case $choice in
        1)
            install_caddy
            ;;
        2)
            upgrade_caddy
            ;;
        3)
            upgrade_caddy_and_files
            ;;
        4)
            uninstall_all
            ;;
        5)
            check_caddy_status
            ;;
        6)
            setup_auto_update
            ;;
        7)
            remove_auto_update
            ;;
        8)
            echo -e "${yellow}退出脚本...${none}"
            exit 0
            ;;
        *)
            error
            ;;
    esac
    pause
done
