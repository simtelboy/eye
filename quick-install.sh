#!/bin/bash

# 天神之眼 Auto Build System - 一键安装脚本
# 作者: hotyi
# 用途: 快速部署天神之眼自动编译系统
#         bash <(curl -fsSL https://raw.githubusercontent.com/simtelboy/eye/main/quick-install.sh)

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本需要root权限运行"
        echo "请使用: curl -fsSL https://raw.githubusercontent.com/simtelboy/eye/main/quick-install.sh | sudo bash"
        exit 1
    fi
}

# 检查并设置北京时区
check_and_set_timezone() {
    log "检查系统时区设置..."
    
    current_timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")
    
    if [[ "$current_timezone" != "Asia/Shanghai" ]]; then
        warning "当前时区: $current_timezone"
        warning "天神之眼自动编译系统需要设置为北京时间 (Asia/Shanghai)"
        
        echo -n "是否设置为北京时间? (y/N): "
        read -r set_timezone
        if [[ "$set_timezone" == "y" || "$set_timezone" == "Y" ]]; then
            log "设置时区为北京时间..."
            if timedatectl set-timezone Asia/Shanghai; then
                log "时区设置成功"
            else
                error "设置时区失败，请手动执行: timedatectl set-timezone Asia/Shanghai"
                exit 1
            fi
        else
            error "安装已取消。请先设置时区为北京时间后再安装。"
            echo "手动设置命令: timedatectl set-timezone Asia/Shanghai"
            exit 1
        fi
    else
        log "时区已设置为北京时间"
    fi
    
    log "当前时间: $(date)"
    echo "----------------------------------------------------------------"
}

# 检查系统兼容性
check_system() {
    log "检查系统兼容性..."
    
    if [[ -f /etc/debian_version ]]; then
        OS="debian"
        VERSION=$(cat /etc/debian_version)
        log "检测到 Debian $VERSION"
    elif [[ -f /etc/lsb-release ]]; then
        OS="ubuntu"
        VERSION=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d'=' -f2)
        log "检测到 Ubuntu $VERSION"
    else
        error "不支持的操作系统。仅支持 Debian 11+ 和 Ubuntu 20.04+"
        exit 1
    fi
}

# 创建临时目录
create_temp_dir() {
    TEMP_DIR=$(mktemp -d)
    log "创建临时目录: $TEMP_DIR"
    
    # 确保退出时清理临时目录
    trap "rm -rf $TEMP_DIR" EXIT
}

# 下载项目文件
download_project() {
    log "下载天神之眼自动编译系统..."
    
    cd "$TEMP_DIR"
    
    # 下载主要文件
    local base_url="https://raw.githubusercontent.com/simtelboy/eye/main"
    
    local files=(
        "deploy.sh"
        "install.sh"
        "install-dependencies.sh"
        "caddy-auto-build.sh"
        "upload-caddy.sh"
        "clean-install.sh"
        "remove-dependencies.sh"
        "check-timezone.sh"
        "test-modifications.sh"
        "caddy-build-config.json"
    )
    
    for file in "${files[@]}"; do
        info "下载 $file..."
        if ! curl -fsSL "$base_url/$file" -o "$file"; then
            error "下载 $file 失败"
            exit 1
        fi
        chmod +x "$file" 2>/dev/null || true
    done
    
    # 注意：caddy-auto-updater 目录在此项目中不存在，已移除相关下载
    
    log "项目文件下载完成"
}

# 运行安装
run_installation() {
    log "开始安装天神之眼自动编译系统..."
    
    cd "$TEMP_DIR"
    
    # 运行部署脚本
    if [[ -f "deploy.sh" ]]; then
        log "运行部署脚本..."
        ./deploy.sh
    else
        error "deploy.sh 文件不存在"
        exit 1
    fi
}


# 显示主菜单
show_main_menu() {
    clear
    echo -e "${BLUE}"
    echo "=================================================="
    echo "    天神之眼自动编译 - 管理菜单"
    echo "=================================================="
    echo -e "${NC}"
    echo
    echo -e "${GREEN}系统管理:${NC}"
    echo -e "  ${YELLOW}1)${NC} 快速部署"
    echo -e "  ${YELLOW}2)${NC} 清理安装"
    echo
    echo -e "${GREEN}依赖管理:${NC}"
    echo -e "  ${YELLOW}3)${NC} 安装依赖"
    echo -e "  ${YELLOW}4)${NC} 删除依赖"
    echo
    echo -e "${GREEN}编译和上传:${NC}"
    echo -e "  ${YELLOW}5)${NC} 自动编译"
    echo -e "  ${YELLOW}6)${NC} 上传文件"
    echo
    echo -e "${GREEN}系统检查:${NC}"
    echo -e "  ${YELLOW}7)${NC} 检查时区"
    echo
    echo -e "${GREEN}其他操作:${NC}"
    echo -e "  ${YELLOW}8)${NC} 查看配置文件"
    echo -e "  ${YELLOW}9)${NC} 查看系统状态"
    echo -e "  ${YELLOW}10)${NC} 查看日志"
    echo -e "  ${YELLOW}11)${NC} 重启编译服务（修改配置后使用）" 
    echo
    echo -e "  ${RED}0)${NC} 退出"
    echo
    echo -e "${BLUE}=================================================${NC}"
}

# 执行菜单选择
execute_menu_choice() {
    local choice=$1
    
    case $choice in
        1)
            log "执行快速部署..."
            if [[ -f "$TEMP_DIR/deploy.sh" ]]; then
                cd "$TEMP_DIR"
                ./deploy.sh
                # 部署完成后显示安装信息
                show_post_install_info
            else
                error "deploy.sh 文件不存在"
            fi
            ;;
        2)
            log "执行清理安装..."
            if [[ -f "$TEMP_DIR/clean-install.sh" ]]; then
                cd "$TEMP_DIR"
                ./clean-install.sh
                echo -e "${GREEN}清理完成！${NC}"
            else
                error "clean-install.sh 文件不存在"
            fi
            ;;
        3)
            log "安装系统依赖..."
            if [[ -f "$TEMP_DIR/install-dependencies.sh" ]]; then
                cd "$TEMP_DIR"
                ./install-dependencies.sh
                echo -e "${GREEN}依赖安装完成！${NC}"
            else
                error "install-dependencies.sh 文件不存在"
            fi
            ;;
        4)
            log "删除系统依赖..."
            if [[ -f "$TEMP_DIR/remove-dependencies.sh" ]]; then
                cd "$TEMP_DIR"
                ./remove-dependencies.sh
                echo -e "${GREEN}依赖删除完成！${NC}"
            else
                error "remove-dependencies.sh 文件不存在"
            fi
            ;;
        5)
            log "执行自动编译..."
            if [[ -f "$TEMP_DIR/caddy-auto-build.sh" ]]; then
                cd "$TEMP_DIR"
                ./caddy-auto-build.sh
                echo -e "${GREEN}编译任务完成！${NC}"
            else
                error "caddy-auto-build.sh 文件不存在"
            fi
            ;;
        6)
            log "上传天神之眼文件..."
            echo -n "请输入天神之眼文件路径: "
            read -r caddy_file_path
            echo -n "请输入版本号 (可选): "
            read -r version
            
            if [[ -f "$TEMP_DIR/upload-caddy.sh" ]]; then
                cd "$TEMP_DIR"
                if [[ -n "$version" ]]; then
                    ./upload-caddy.sh "$caddy_file_path" "$version"
                else
                    ./upload-caddy.sh "$caddy_file_path"
                fi
                echo -e "${GREEN}上传任务完成！${NC}"
            else
                error "upload-caddy.sh 文件不存在"
            fi
            ;;
        7)
            log "检查系统时区..."
            if [[ -f "$TEMP_DIR/check-timezone.sh" ]]; then
                cd "$TEMP_DIR"
                ./check-timezone.sh
            else
                error "check-timezone.sh 文件不存在"
            fi
            ;;
        8)
            log "查看配置文件..."
            if [[ -f "/root/caddy-build-config.json" ]]; then
                echo -e "${GREEN}配置文件内容:${NC}"
                cat /root/caddy-build-config.json
            else
                warning "配置文件不存在: /root/caddy-build-config.json"
                if [[ -f "$TEMP_DIR/caddy-build-config.json" ]]; then
                    echo -e "${GREEN}模板配置文件内容:${NC}"
                    cat "$TEMP_DIR/caddy-build-config.json"
                fi
            fi
            ;;
        9)
            log "查看系统状态..."
            echo -e "${GREEN}定时器状态:${NC}"
            systemctl status caddy-auto-build.timer --no-pager 2>/dev/null || echo "定时器未安装"
            echo
            echo -e "${GREEN}服务状态:${NC}"
            systemctl status caddy-auto-build.service --no-pager 2>/dev/null || echo "服务未安装"
            echo
            echo -e "${GREEN}下次执行时间:${NC}"
            systemctl list-timers caddy-auto-build.timer --no-pager 2>/dev/null || echo "无定时器信息"
            ;;
        10)
            log "查看系统日志..."
            if [[ -f "/var/log/caddy-auto-build.log" ]]; then
                echo -e "${GREEN}最近20行日志:${NC}"
                tail -20 /var/log/caddy-auto-build.log
            else
                warning "日志文件不存在: /var/log/caddy-auto-build.log"
            fi
            ;;
        11)
            log "重启编译服务..."
            systemctl daemon-reload
            systemctl restart caddy-auto-build.timer
            echo -e "${GREEN}编译服务已重启！${NC}"
            ;;    
        0)
            log "退出程序"
            exit 0
            ;;
        *)
            error "无效选择: $choice"
            ;;
    esac
}

# 交互式菜单主循环
interactive_menu() {
    while true; do
        show_main_menu
        echo -n "请选择操作 (0-11): "
        read -r choice
        
        echo
        execute_menu_choice "$choice"
        
        echo
        echo -e "${YELLOW}按任意键继续...${NC}"
        read -n 1 -s
    done
}

# 显示安装后信息
show_post_install_info() {
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  操作完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${YELLOW}重要提醒:${NC}"
    echo -e "1. 编辑配置文件设置 GitHub Token:"
    echo -e "   ${BLUE}nano /root/caddy-build-config.json${NC}"
    echo
    echo -e "2. 手动测试编译:"
    echo -e "   ${BLUE}/usr/local/bin/caddy-auto-build.sh${NC}"
    echo
    echo -e "3. 查看系统状态:"
    echo -e "   ${BLUE}systemctl status caddy-auto-build.timer${NC}"
    echo
    echo -e "${YELLOW}GitHub Token 获取方法:${NC}"
    echo -e "1. 访问: ${BLUE}https://github.com/settings/tokens${NC}"
    echo -e "2. 点击 'Generate new token (classic)'"
    echo -e "3. 选择权限: ${BLUE}repo${NC} (完整仓库权限)"
    echo -e "4. 复制生成的 token 到配置文件中"
    echo
    echo -e "${YELLOW}定时任务:${NC}"
    echo -e "• 编译检查: 每周日凌晨2点（北京时间）"
    echo -e "• 查看日志: ${BLUE}tail -f /var/log/caddy-auto-build.log${NC}"
    echo
    echo -e "${GREEN}返回主菜单继续其他操作...${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "    天神之眼 Auto Build System - 一键安装脚本"
    echo "=================================================="
    echo -e "${NC}"
    
    check_root
    check_system
    check_and_set_timezone
    create_temp_dir
    download_project
    
     # 显示交互式菜单而不是直接安装
    interactive_menu
}

# 运行主函数
main "$@"
