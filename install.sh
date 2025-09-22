#!/bin/bash

# Caddy 自动编译系统安装脚本

set -e

echo "========== Caddy 自动编译系统安装 =========="

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
   echo "此脚本需要 root 权限运行"
   exit 1
fi

# 检查并设置北京时区
check_and_set_timezone() {
    echo "检查系统时区设置..."
    
    current_timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")
    
    if [[ "$current_timezone" != "Asia/Shanghai" ]]; then
        echo "当前时区: $current_timezone"
        echo "Caddy自动编译系统需要设置为北京时间 (Asia/Shanghai)"
        
        echo -n "是否设置为北京时间? (y/N): "
        read -r set_timezone
        if [[ "$set_timezone" == "y" || "$set_timezone" == "Y" ]]; then
            echo "设置时区为北京时间..."
            if timedatectl set-timezone Asia/Shanghai; then
                echo "时区设置成功"
            else
                echo "错误: 设置时区失败，请手动执行: timedatectl set-timezone Asia/Shanghai"
                exit 1
            fi
        else
            echo "错误: 安装已取消。请先设置时区为北京时间后再安装。"
            echo "手动设置命令: timedatectl set-timezone Asia/Shanghai"
            exit 1
        fi
    else
        echo "时区已设置为北京时间"
    fi
    
    echo "当前时间: $(date)"
    echo "----------------------------------------------------------------"
}

# 调用时区检查
check_and_set_timezone

# 更新系统包
echo "更新系统包..."
apt-get update

# 安装必要的依赖
echo "安装依赖包..."
apt-get install -y curl jq git wget build-essential

# 检查编译环境
echo ""
echo "检查编译环境..."

# 检查 gcc
if command -v gcc >/dev/null 2>&1; then
    echo "  ✓ gcc 可用: $(gcc --version | head -n1)"
else
    echo "  ✗ gcc 不可用 - 需要 C 编译器才能编译 Caddy"
    echo "    build-essential 安装可能失败，请检查网络连接"
    exit 1
fi

# 检查 glibc
if ldconfig -p | grep -q libc.so.6; then
    glibc_version=$(ldd --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+')
    echo "  ✓ glibc 可用: $glibc_version"
else
    echo "  ✗ glibc 不可用 - Caddy 编译需要 glibc"
    echo "    glibc 通常随系统安装，如果缺失请检查系统完整性"
    exit 1
fi

# 安装 Go (如果未安装或版本不正确)
install_go() {
    echo "安装 Go 1.25.1..."
    # 删除旧版本
    rm -rf /usr/local/go

    GO_VERSION="1.25.1"
    wget -q "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
    rm "go${GO_VERSION}.linux-amd64.tar.gz"

    # 清理旧的环境变量
    sed -i '/\/usr\/local\/go\/bin/d' /etc/profile ~/.bashrc 2>/dev/null || true

    # 添加 Go 到 PATH
    echo 'export PATH=/usr/local/go/bin:$PATH' >> /etc/profile
    echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.bashrc
    echo 'export GOPATH=$HOME/go' >> ~/.bashrc
    echo 'export PATH=$GOPATH/bin:$PATH' >> ~/.bashrc

    export PATH=/usr/local/go/bin:$PATH
    export GOPATH=$HOME/go
    export PATH=$GOPATH/bin:$PATH

    mkdir -p $GOPATH/bin
}

# 检查 Go 版本并安装
if ! command -v go &> /dev/null; then
    install_go
else
    current_version=$(go version | grep -o 'go[0-9]\+\.[0-9]\+\.[0-9]\+' | sed 's/go//')
    required_version="1.25.0"

    # 简单的版本比较
    if [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" != "$required_version" ]]; then
        echo "当前 Go 版本 ($current_version) 不满足要求 (>= $required_version)"
        install_go
    else
        echo "Go 版本满足要求: $current_version"
    fi
fi

# 安装 xcaddy
echo "安装 xcaddy..."
# 清理旧的 xcaddy
rm -f /usr/local/bin/xcaddy

# 使用新的 Go 安装 xcaddy
/usr/local/go/bin/go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# 确保 xcaddy 在 PATH 中
if [[ -f "$GOPATH/bin/xcaddy" ]]; then
    cp "$GOPATH/bin/xcaddy" /usr/local/bin/
    chmod +x /usr/local/bin/xcaddy
    echo "xcaddy 安装成功"
else
    echo "警告: xcaddy 安装可能失败"
fi

# 复制脚本到系统目录
echo "安装脚本文件..."
cp caddy-auto-build.sh /usr/local/bin/
cp upload-caddy.sh /usr/local/bin/
chmod +x /usr/local/bin/caddy-auto-build.sh
chmod +x /usr/local/bin/upload-caddy.sh
echo "  ✓ 主脚本: /usr/local/bin/caddy-auto-build.sh"
echo "  ✓ 上传脚本: /usr/local/bin/upload-caddy.sh"

# 复制配置文件
cp caddy-build-config.json /root/
echo "配置文件已复制到 /root/caddy-build-config.json"

# 创建日志目录
mkdir -p /var/log
touch /var/log/caddy-auto-build.log

# 创建 systemd 定时器
echo "创建 systemd 服务和定时器..."

# 创建服务文件
cat > /etc/systemd/system/caddy-auto-build.service << 'EOF'
[Unit]
Description=Caddy Auto Build Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/caddy-auto-build.sh
User=root
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF

# 创建定时器文件 (每周日凌晨2点执行)
cat > /etc/systemd/system/caddy-auto-build.timer << 'EOF'
[Unit]
Description=Run Caddy Auto Build Weekly
Requires=caddy-auto-build.service

[Timer]
OnCalendar=Sat *-*-* 11:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 重新加载 systemd 并启用定时器
systemctl daemon-reload
systemctl enable caddy-auto-build.timer
systemctl start caddy-auto-build.timer

echo ""
echo "========== 安装完成 =========="
echo ""
echo "接下来的步骤："
echo "1. 编辑配置文件: nano /root/caddy-build-config.json"
echo "2. 设置您的 GitHub Token (需要 repo 权限)"
echo "3. 如需修改天神之眼代码的哈希值，请编辑配置文件"
echo ""
echo "定时任务已设置为每周六上午11点执行（服务器时间）"
echo "  对应本地时间: 根据您的时区而定"
echo "  运行 ./check-timezone.sh 查看详细时区对照"
echo ""
echo "手动测试运行: /usr/local/bin/caddy-auto-build.sh"
echo "单独测试上传: /usr/local/bin/upload-caddy.sh <文件路径> [版本]"
echo "查看定时器状态: systemctl status caddy-auto-build.timer"
echo "查看日志: tail -f /var/log/caddy-auto-build.log"
echo ""
echo "GitHub Token 获取方法："
echo "1. 访问 https://github.com/settings/tokens"
echo "2. 点击 'Generate new token (classic)'"
echo "3. 选择权限: repo (完整仓库权限)"
echo "4. 复制生成的 token 到配置文件中"
