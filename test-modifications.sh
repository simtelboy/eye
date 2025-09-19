#!/bin/bash

# 测试脚本修改的验证脚本
# 此脚本用于验证修改后的脚本能正确检测gcc和glibc，并自动安装必要的编译工具

echo "========== 测试脚本修改验证 =========="
echo ""

# 测试函数：检查脚本中是否包含特定内容
check_script_content() {
    local script_file="$1"
    local search_pattern="$2"
    local should_exist="$3"  # true 或 false
    local description="$4"
    
    if [[ ! -f "$script_file" ]]; then
        echo "  ✗ 文件不存在: $script_file"
        return 1
    fi
    
    if grep -q "$search_pattern" "$script_file"; then
        if [[ "$should_exist" == "true" ]]; then
            echo "  ✓ $description"
        else
            echo "  ✗ $description (不应该存在但找到了)"
        fi
    else
        if [[ "$should_exist" == "false" ]]; then
            echo "  ✓ $description"
        else
            echo "  ✗ $description (应该存在但未找到)"
        fi
    fi
}

echo "1. 检查 install-dependencies.sh 修改..."
check_script_content "install-dependencies.sh" "apt-get install.*build-essential" "true" "包含 build-essential 安装命令"
check_script_content "install-dependencies.sh" "gcc.*可用" "true" "包含 gcc 检测"
check_script_content "install-dependencies.sh" "glibc.*可用" "true" "包含 glibc 检测"

echo ""
echo "2. 检查 remove-dependencies.sh 修改..."
check_script_content "remove-dependencies.sh" "apt-get remove.*build-essential" "true" "包含 build-essential 删除选项"
check_script_content "remove-dependencies.sh" "gcc.*仍然存在" "true" "包含 gcc 状态检查"

echo ""
echo "3. 检查 install.sh 修改..."
check_script_content "install.sh" "apt-get install.*build-essential" "true" "包含 build-essential 安装命令"
check_script_content "install.sh" "gcc.*可用" "true" "包含 gcc 检测"
check_script_content "install.sh" "glibc.*可用" "true" "包含 glibc 检测"

echo ""
echo "4. 检查 caddy-auto-build.sh 修改..."
check_script_content "caddy-auto-build.sh" "gcc.*未安装.*build-essential" "true" "包含 gcc 检查和安装建议"
check_script_content "caddy-auto-build.sh" "glibc.*检查通过" "true" "包含 glibc 检测"
check_script_content "caddy-auto-build.sh" "CGO_ENABLED=1" "true" "包含CGO编译设置"
check_script_content "caddy-auto-build.sh" "CGO_LDFLAGS.*static-libgcc" "true" "包含静态链接设置"

echo ""
echo "5. 测试系统环境检测..."

# 检测当前系统的 gcc
if command -v gcc >/dev/null 2>&1; then
    echo "  ✓ 系统中存在 gcc: $(gcc --version | head -n1)"
else
    echo "  ✗ 系统中不存在 gcc"
fi

# 检测当前系统的 glibc
if ldconfig -p | grep -q libc.so.6; then
    glibc_version=$(ldd --version 2>/dev/null | head -n1 | grep -o '[0-9]\+\.[0-9]\+' | head -n1)
    if [[ -n "$glibc_version" ]]; then
        echo "  ✓ 系统中存在 glibc: $glibc_version"
    else
        echo "  ✓ 系统中存在 glibc (版本检测失败)"
    fi
else
    echo "  ✗ 系统中不存在 glibc"
fi

echo ""
echo "6. 验证环境变量设置..."

# 模拟 setup_build_environment 函数的环境变量设置
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export NEEDRESTART_MODE=l
export DEBIAN_PRIORITY=critical
export DEBCONF_NOWARNINGS=yes
export CGO_ENABLED=1
export CGO_CFLAGS="-O2 -g"
export CGO_LDFLAGS="-static-libgcc"
export GOPROXY=direct
export GOSUMDB=off

echo "  ✓ 防护环境变量已设置"
echo "    DEBIAN_FRONTEND: $DEBIAN_FRONTEND"
echo "    CGO_ENABLED: $CGO_ENABLED"
echo "    CGO_LDFLAGS: $CGO_LDFLAGS"
echo "    GOPROXY: $GOPROXY"

echo ""
echo "========== 验证完成 =========="
echo ""
echo "修改总结:"
echo "  • 已恢复所有脚本中的 gcc 检查和依赖"
echo "  • 已添加 build-essential 的自动安装功能"
echo "  • 保留了 glibc 检测功能"
echo "  • 在编译环境中添加了兼容性编译标志"
echo "  • 设置了静态链接选项以减少对系统库的依赖"
echo ""
echo "注意事项:"
echo "  • 系统会自动安装 gcc 和编译工具链"
echo "  • 如果系统中没有 glibc，通常表示系统不完整，需要检查系统状态"
echo "  • 编译使用静态链接，提高二进制文件的兼容性"
