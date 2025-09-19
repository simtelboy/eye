#!/bin/bash

# 删除依赖脚本 - 删除 Go、xcaddy 和 C 编译器
# 用于干净测试主程序的依赖安装功能

echo "========== 删除系统依赖 =========="

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
   echo "错误: 此脚本需要 root 权限运行"
   echo "请使用: sudo ./remove-dependencies.sh"
   exit 1
fi

echo "警告: 此脚本将删除以下组件:"
echo "  • Go 编程语言 (/usr/local/go/)"
echo "  • xcaddy 工具 (/usr/local/bin/xcaddy)"
echo "  • Go 相关的环境变量和缓存"
echo ""
echo "这将影响系统中所有依赖这些工具的程序！"
echo ""
read -p "确认删除? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "已取消删除操作"
    exit 0
fi

echo ""
echo "开始删除依赖..."

# 1. 删除 Go 安装
echo "1. 删除 Go 安装..."
if [[ -d "/usr/local/go" ]]; then
    rm -rf /usr/local/go
    echo "  ✓ 删除 /usr/local/go/"
else
    echo "  - Go 安装目录不存在"
fi

# 2. 删除 xcaddy
echo "2. 删除 xcaddy..."
if [[ -f "/usr/local/bin/xcaddy" ]]; then
    rm -f /usr/local/bin/xcaddy
    echo "  ✓ 删除 /usr/local/bin/xcaddy"
else
    echo "  - xcaddy 不存在"
fi

# 3. 删除 GOPATH 目录
echo "3. 清理 Go 工作目录..."
if [[ -d "/root/go" ]]; then
    rm -rf /root/go
    echo "  ✓ 删除 /root/go/"
fi

if [[ -d "$HOME/go" ]]; then
    rm -rf "$HOME/go"
    echo "  ✓ 删除 $HOME/go/"
fi

# 4. 清理 Go 缓存
echo "4. 清理 Go 缓存..."
rm -rf ~/.cache/go-build 2>/dev/null || true
rm -rf /root/.cache/go-build 2>/dev/null || true
echo "  ✓ 清理 Go 缓存"

# 5. 清理环境变量
echo "5. 清理环境变量..."

# 从 /etc/profile 中删除 Go 相关的环境变量
if [[ -f "/etc/profile" ]]; then
    sed -i '/\/usr\/local\/go\/bin/d' /etc/profile 2>/dev/null || true
    sed -i '/GOPATH/d' /etc/profile 2>/dev/null || true
    echo "  ✓ 清理 /etc/profile"
fi

# 从 ~/.bashrc 中删除 Go 相关的环境变量
if [[ -f "$HOME/.bashrc" ]]; then
    sed -i '/\/usr\/local\/go\/bin/d' ~/.bashrc 2>/dev/null || true
    sed -i '/GOPATH/d' ~/.bashrc 2>/dev/null || true
    echo "  ✓ 清理 ~/.bashrc"
fi

if [[ -f "/root/.bashrc" ]]; then
    sed -i '/\/usr\/local\/go\/bin/d' /root/.bashrc 2>/dev/null || true
    sed -i '/GOPATH/d' /root/.bashrc 2>/dev/null || true
    echo "  ✓ 清理 /root/.bashrc"
fi

# 6. 检查 C/C++ 编译器状态
echo "6. 检查 C/C++ 编译器状态..."
if command -v gcc >/dev/null 2>&1; then
    echo "  ℹ gcc 仍然存在: $(gcc --version | head -n1)"
    echo "  ℹ 如需删除 gcc，请手动运行: apt-get remove build-essential"
else
    echo "  ✓ gcc 不存在"
fi

# 7. 可选：删除编译工具（询问用户）
echo ""
echo "是否删除 C/C++ 编译工具? (build-essential)"
echo "注意: 这些工具可能被其他程序使用"
read -p "删除编译工具? (y/N): " remove_build_tools

if [[ "$remove_build_tools" == "y" || "$remove_build_tools" == "Y" ]]; then
    echo "删除 build-essential..."
    apt-get remove -y build-essential 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    echo "  ✓ 删除 build-essential"
else
    echo "保留 build-essential"
fi

# 8. 可选：删除其他开发工具（询问用户）
echo ""
echo "是否同时删除其他开发工具? (curl, jq, git, wget)"
echo "注意: 这些工具可能被其他程序使用"
read -p "删除其他工具? (y/N): " remove_tools

if [[ "$remove_tools" == "y" || "$remove_tools" == "Y" ]]; then
    echo "7. 删除其他开发工具..."
    apt-get remove -y curl jq git wget 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    echo "  ✓ 删除 curl, jq, git, wget"
else
    echo "7. 保留其他开发工具 (curl, jq, git, wget)"
fi

echo ""
echo "========== 依赖删除完成 =========="
echo ""
echo "已删除的组件:"
echo "  ✓ Go 编程语言"
echo "  ✓ xcaddy 工具"
echo "  ✓ Go 工作目录和缓存"
echo "  ✓ Go 相关环境变量"

if [[ "$remove_tools" == "y" || "$remove_tools" == "Y" ]]; then
    echo "  ✓ 其他开发工具 (curl, jq, git, wget)"
fi

echo ""
echo "验证删除结果:"

# 验证删除结果
for tool in go xcaddy gcc; do
    if command -v $tool >/dev/null 2>&1; then
        echo "  ✗ $tool 仍然存在"
    else
        echo "  ✓ $tool 已删除"
    fi
done

echo ""
echo "注意事项:"
echo "1. 环境变量更改需要重新登录或运行 'source ~/.bashrc' 生效"
echo "2. 如需重新安装依赖，请运行:"
echo "   sudo ./install-dependencies.sh"
echo "3. 或者直接运行完整安装:"
echo "   sudo ./deploy.sh"
echo ""
echo "现在可以测试主程序的依赖安装功能了！"
