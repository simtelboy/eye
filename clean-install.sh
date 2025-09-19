#!/bin/bash

# 清理 Caddy 自动编译系统脚本
# 只清理本程序相关文件，不删除 Go 和 xcaddy

echo "========== 清理 Caddy 自动编译系统 =========="

# 检查是否为 root
if [[ $EUID -ne 0 ]]; then
   echo "错误: 此脚本需要 root 权限运行"
   echo "请使用: sudo ./clean-install.sh"
   exit 1
fi

echo "1. 停止并删除系统服务..."

# 停止并禁用定时器
systemctl stop caddy-auto-build.timer 2>/dev/null || true
systemctl disable caddy-auto-build.timer 2>/dev/null || true

# 停止服务（如果正在运行）
systemctl stop caddy-auto-build.service 2>/dev/null || true

# 删除 systemd 文件
if [[ -f "/etc/systemd/system/caddy-auto-build.service" ]]; then
    rm -f /etc/systemd/system/caddy-auto-build.service
    echo "  ✓ 删除服务文件"
fi

if [[ -f "/etc/systemd/system/caddy-auto-build.timer" ]]; then
    rm -f /etc/systemd/system/caddy-auto-build.timer
    echo "  ✓ 删除定时器文件"
fi

# 重新加载 systemd
systemctl daemon-reload
echo "  ✓ 重新加载 systemd"

echo "2. 删除程序文件..."

# 删除安装到系统的脚本文件
if [[ -f "/usr/local/bin/caddy-auto-build.sh" ]]; then
    rm -f /usr/local/bin/caddy-auto-build.sh
    echo "  ✓ 删除 /usr/local/bin/caddy-auto-build.sh"
fi

if [[ -f "/usr/local/bin/upload-caddy.sh" ]]; then
    rm -f /usr/local/bin/upload-caddy.sh
    echo "  ✓ 删除 /usr/local/bin/upload-caddy.sh"
fi

echo "3. 备份和清理配置文件..."

# 备份配置文件（如果存在）
if [[ -f "/root/caddy-build-config.json" ]]; then
    backup_file="/root/caddy-build-config.json.backup.$(date +%s)"
    cp /root/caddy-build-config.json "$backup_file"
    echo "  ✓ 配置文件已备份到: $backup_file"

    # 删除当前配置文件
    rm -f /root/caddy-build-config.json
    echo "  ✓ 删除当前配置文件"
fi

echo "4. 清理日志文件..."

# 清理日志文件（保留最近的）
if [[ -f "/var/log/caddy-auto-build.log" ]]; then
    # 备份最近的日志
    if [[ -s "/var/log/caddy-auto-build.log" ]]; then
        cp /var/log/caddy-auto-build.log "/var/log/caddy-auto-build.log.backup.$(date +%s)"
        echo "  ✓ 日志文件已备份"
    fi

    # 清空日志文件
    > /var/log/caddy-auto-build.log
    echo "  ✓ 清空日志文件"
fi

echo "5. 清理编译临时文件..."

# 清理可能的编译文件
rm -f /root/caddy-v*-linux-amd64 2>/dev/null || true
rm -rf /root/caddy-build-tmp 2>/dev/null || true
rm -f /root/caddy 2>/dev/null || true
echo "  ✓ 清理编译临时文件"

echo "6. 清理定时任务..."

# 检查并清理可能的 crontab 条目
if crontab -l 2>/dev/null | grep -q "caddy-auto-build"; then
    echo "发现 crontab 中的相关条目，请手动检查:"
    crontab -l | grep "caddy-auto-build" || true
    echo "如需删除，请运行: crontab -e"
fi

echo ""
echo "========== 清理完成 =========="
echo ""
echo "已清理的内容:"
echo "  ✓ systemd 服务和定时器"
echo "  ✓ 安装到系统的程序文件"
echo "  ✓ 配置文件（已备份）"
echo "  ✓ 日志文件（已备份）"
echo "  ✓ 编译临时文件"
echo ""
echo "保留的内容:"
echo "  ✓ Go 安装 (/usr/local/go/)"
echo "  ✓ xcaddy (/usr/local/bin/xcaddy)"
echo "  ✓ 系统依赖包 (curl, jq, git 等)"
echo ""
echo "备份文件位置:"
if ls /root/caddy-build-config.json.backup.* 2>/dev/null; then
    echo "  配置文件备份:"
    ls -la /root/caddy-build-config.json.backup.*
fi
if ls /var/log/caddy-auto-build.log.backup.* 2>/dev/null; then
    echo "  日志文件备份:"
    ls -la /var/log/caddy-auto-build.log.backup.*
fi
echo ""
echo "下一步操作:"
echo "1. 重新部署系统:"
echo "   sudo ./deploy.sh"
echo ""
echo "2. 恢复配置文件（如果需要）:"
echo "   cp /root/caddy-build-config.json.backup.XXXXX /root/caddy-build-config.json"
echo ""
echo "3. 如果需要重新安装依赖:"
echo "   sudo ./install-dependencies.sh"
