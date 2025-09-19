#!/bin/bash

# Caddy Auto Build System - 一键安装脚本
# 作者: Your Name
# 用途: 快速部署Caddy自动编译系统
# bash <(curl -L https://raw.githubusercontent.com/simtelboy/eye/refs/heads/main/quick-install.sh)

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
    log "下载Caddy自动编译系统..."
    
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
    log "开始安装Caddy自动编译系统..."
    
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

# 显示安装后信息
show_post_install_info() {
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Caddy自动编译系统安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${YELLOW}下一步操作:${NC}"
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
    echo -e "• 编译检查: 每周六上午11点"
    echo -e "• 查看日志: ${BLUE}tail -f /var/log/caddy-auto-build.log${NC}"
    echo
    echo -e "${GREEN}安装完成！感谢使用 Caddy Auto Build System${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "    Caddy Auto Build System - 一键安装脚本"
    echo "=================================================="
    echo -e "${NC}"
    
    check_root
    check_system
    create_temp_dir
    download_project
    run_installation
    show_post_install_info
}

# 运行主函数
main "$@"
