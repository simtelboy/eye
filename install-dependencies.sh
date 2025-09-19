#!/bin/bash

# 依赖安装脚本 - 安装 Go、xcaddy 和其他必要依赖

set -e

echo "========== 安装系统依赖 =========="

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
   echo "错误: 此脚本需要 root 权限运行"
   echo "请使用: sudo ./install-dependencies.sh"
   exit 1
fi

# 更新系统包
echo "1. 更新系统包..."
apt-get update

# 安装必要的依赖
echo "2. 安装系统依赖包..."
apt-get install -y curl jq git wget build-essential

echo "依赖包安装完成:"
echo "  ✓ curl - 网络请求工具"
echo "  ✓ jq - JSON 处理工具"
echo "  ✓ git - 版本控制工具"
echo "  ✓ wget - 文件下载工具"
echo "  ✓ build-essential - C/C++ 编译工具链"

# 检查编译环境
echo ""
echo "3. 检查编译环境..."

# 检查 gcc
if command -v gcc >/dev/null 2>&1; then
    echo "  ✓ gcc 可用: $(gcc --version | head -n1)"
else
    echo "  ✗ gcc 不可用 - build-essential 安装可能失败"
    echo "    请检查网络连接或手动安装: apt-get install build-essential"
fi

# 检查 glibc
if ldconfig -p | grep -q libc.so.6; then
    glibc_version=$(ldd --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+')
    echo "  ✓ glibc 可用: $glibc_version"
else
    echo "  ✗ glibc 不可用 - Caddy 编译需要 glibc"
    echo "    glibc 通常随系统安装，如果缺失请检查系统完整性"
fi

# 安装 Go (如果未安装或版本不正确)
install_go() {
    echo "4. 安装 Go 1.25.1..."
    
    # 删除旧版本
    if [[ -d "/usr/local/go" ]]; then
        echo "删除旧的 Go 安装..."
        rm -rf /usr/local/go
    fi

    GO_VERSION="1.25.1"
    echo "下载 Go $GO_VERSION..."
    wget -q "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    
    echo "解压 Go..."
    tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
    rm "go${GO_VERSION}.linux-amd64.tar.gz"

    # 清理旧的环境变量
    sed -i '/\/usr\/local\/go\/bin/d' /etc/profile ~/.bashrc 2>/dev/null || true

    # 添加 Go 到 PATH
    echo 'export PATH=/usr/local/go/bin:$PATH' >> /etc/profile
    echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.bashrc
    echo 'export GOPATH=$HOME/go' >> ~/.bashrc
    echo 'export PATH=$GOPATH/bin:$PATH' >> ~/.bashrc

    # 设置当前会话的环境变量
    export PATH=/usr/local/go/bin:$PATH
    export GOPATH=$HOME/go
    export PATH=$GOPATH/bin:$PATH

    # 创建 GOPATH 目录
    mkdir -p $GOPATH/bin

    echo "Go $GO_VERSION 安装完成"
}

# 检查 Go 版本并安装
echo "3. 检查 Go 安装..."
if ! command -v go &> /dev/null; then
    echo "Go 未安装，开始安装..."
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
        # 确保环境变量正确设置
        export PATH=/usr/local/go/bin:$PATH
        export GOPATH=$HOME/go
        export PATH=$GOPATH/bin:$PATH
        mkdir -p $GOPATH/bin
    fi
fi

# 安装 xcaddy
echo "4. 安装 xcaddy..."

# 清理旧的 xcaddy
if [[ -f "/usr/local/bin/xcaddy" ]]; then
    echo "删除旧的 xcaddy..."
    rm -f /usr/local/bin/xcaddy
fi

if [[ -f "$GOPATH/bin/xcaddy" ]]; then
    echo "删除旧的 xcaddy (GOPATH)..."
    rm -f "$GOPATH/bin/xcaddy"
fi

# 使用 Go 安装 xcaddy
echo "使用 Go 安装 xcaddy..."
/usr/local/go/bin/go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# 确保 xcaddy 在系统 PATH 中
if [[ -f "$GOPATH/bin/xcaddy" ]]; then
    cp "$GOPATH/bin/xcaddy" /usr/local/bin/
    chmod +x /usr/local/bin/xcaddy
    echo "xcaddy 安装成功"
else
    echo "警告: xcaddy 安装可能失败"
    echo "请检查网络连接和 Go 环境"
fi

# 验证安装
echo ""
echo "========== 安装验证 =========="

echo "验证 Go 安装:"
if /usr/local/go/bin/go version; then
    echo "  ✓ Go 安装成功"
else
    echo "  ✗ Go 安装失败"
fi

echo ""
echo "验证 xcaddy 安装:"
if /usr/local/bin/xcaddy version; then
    echo "  ✓ xcaddy 安装成功"
else
    echo "  ✗ xcaddy 安装失败"
fi

echo ""
echo "验证其他工具:"
for tool in curl jq git gcc; do
    if command -v $tool >/dev/null 2>&1; then
        echo "  ✓ $tool 可用"
    else
        echo "  ✗ $tool 不可用"
    fi
done

echo ""
echo "========== 依赖安装完成 =========="
echo ""
echo "已安装的组件:"
echo "  • Go 1.25.1 - /usr/local/go/"
echo "  • xcaddy - /usr/local/bin/xcaddy"
echo "  • 系统依赖 - curl, jq, git, wget, build-essential"
echo ""
echo "环境变量已设置到:"
echo "  • /etc/profile"
echo "  • ~/.bashrc"
echo ""
echo "重新登录或运行以下命令使环境变量生效:"
echo "  source ~/.bashrc"
echo ""
echo "现在可以运行 deploy.sh 来部署 Caddy 自动编译系统"
