#!/bin/bash

# 时区检查和定时器配置脚本（简化版）

echo "========== 时区和定时器检查 =========="

# 显示当前服务器时间
echo "当前服务器时间:"
echo "  日期时间: $(date)"
echo "  时区: $(date +%Z)"
echo "  UTC偏移: $(date +%z)"

# 显示UTC时间
echo ""
echo "UTC时间: $(date -u)"

# 检查时区设置
echo ""
echo "========== 时区设置检查 =========="
current_timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")
if [[ "$current_timezone" == "Asia/Shanghai" ]]; then
    echo "✓ 时区设置正确: $current_timezone"
else
    echo "✗ 时区设置错误: $current_timezone"
    echo "  建议设置为北京时间: timedatectl set-timezone Asia/Shanghai"
fi

# 检查定时器状态
echo ""
echo "========== 定时器状态 =========="
if systemctl is-active --quiet caddy-auto-build.timer; then
    echo "✓ 定时器正在运行"
else
    echo "✗ 定时器未运行"
fi

# 显示定时器配置
echo ""
echo "当前定时器配置:"
if [[ -f "/etc/systemd/system/caddy-auto-build.timer" ]]; then
    grep "OnCalendar" /etc/systemd/system/caddy-auto-build.timer
    echo "  执行时间: 每周日凌晨2点（北京时间）"
else
    echo "定时器配置文件不存在"
fi

# 显示下次执行时间
echo ""
echo "下次执行时间:"
systemctl list-timers caddy-auto-build.timer --no-pager 2>/dev/null || echo "无法获取定时器信息"

echo ""
echo "========== 管理命令 =========="
echo "启动定时器: systemctl start caddy-auto-build.timer"
echo "停止定时器: systemctl stop caddy-auto-build.timer"
echo "查看日志:   tail -f /var/log/caddy-auto-build.log"
echo "手动执行:   /usr/local/bin/caddy-auto-build.sh"

echo ""
echo "========== 检查完成 =========="
