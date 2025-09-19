#!/bin/bash

# 时区检查和定时器配置脚本

echo "========== 时区和定时器检查 =========="

# 显示当前服务器时间
echo "当前服务器时间:"
echo "  日期时间: $(date)"
echo "  时区: $(date +%Z)"
echo "  UTC偏移: $(date +%z)"

# 显示UTC时间
echo ""
echo "UTC时间: $(date -u)"

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
else
    echo "定时器配置文件不存在"
fi

# 显示下次执行时间
echo ""
echo "下次执行时间:"
systemctl list-timers caddy-auto-build.timer --no-pager 2>/dev/null || echo "无法获取定时器信息"

echo ""
echo "========== 时区配置建议 =========="

# 计算时区差异（避免八进制问题）
current_hour=$(date +%H | sed 's/^0//')
utc_hour=$(date -u +%H | sed 's/^0//')
timezone_diff=$((current_hour - utc_hour))

# 处理跨日期的情况
if [[ $timezone_diff -gt 12 ]]; then
    timezone_diff=$((timezone_diff - 24))
elif [[ $timezone_diff -lt -12 ]]; then
    timezone_diff=$((timezone_diff + 24))
fi

echo "服务器与UTC时差: ${timezone_diff}小时"

# 从 date 命令获取更准确的时区偏移
timezone_offset=$(date +%z)
timezone_hours=$((${timezone_offset:1:2}))
if [[ "${timezone_offset:0:1}" == "-" ]]; then
    timezone_hours=$((0 - timezone_hours))
fi
echo "时区偏移: ${timezone_offset} (${timezone_hours}小时)"

# 提供常见时区的转换（基于服务器时区 ${timezone_hours}小时）
echo ""
echo "如果您希望在以下本地时间执行，对应的服务器时间为:"
echo ""

# 计算函数
calculate_server_time() {
    local local_hour=$1
    local local_timezone=$2
    local target_day="周日"

    # 计算服务器时间 = 本地时间 - 本地时区偏移 + 服务器时区偏移
    local server_hour=$(( (local_hour - local_timezone + timezone_hours + 24) % 24 ))

    # 检查是否跨日期
    local day_diff=$(( (local_hour - local_timezone + timezone_hours) / 24 ))
    if [[ $day_diff -lt 0 ]]; then
        target_day="周六"
    elif [[ $day_diff -gt 0 ]]; then
        target_day="周一"
    fi

    echo "$target_day $(printf "%02d" $server_hour):00"
}

# 中国时间 (UTC+8)
china_server_time=$(calculate_server_time 2 8)
echo "中国时间 (UTC+8) 周日 02:00 → 服务器时间 $china_server_time"

# 日本时间 (UTC+9)
japan_server_time=$(calculate_server_time 2 9)
echo "日本时间 (UTC+9) 周日 02:00 → 服务器时间 $japan_server_time"

# 美国东部时间 (UTC-5)
us_east_server_time=$(calculate_server_time 2 -5)
echo "美国东部 (UTC-5) 周日 02:00 → 服务器时间 $us_east_server_time"

# 欧洲中部时间 (UTC+1)
eu_server_time=$(calculate_server_time 2 1)
echo "欧洲中部 (UTC+1) 周日 02:00 → 服务器时间 $eu_server_time"

# 美国西部时间 (UTC-8，与服务器相同)
us_west_server_time=$(calculate_server_time 2 -8)
echo "美国西部 (UTC-8) 周日 02:00 → 服务器时间 $us_west_server_time"

echo ""
echo "========== 修改定时器时间 =========="
echo ""
echo "如需修改定时器时间，请编辑配置文件:"
echo "  sudo nano /etc/systemd/system/caddy-auto-build.timer"
echo ""
echo "修改 OnCalendar 行，格式为:"
echo "  OnCalendar=DayOfWeek *-*-* HH:MM:SS"
echo ""
echo "例如:"
echo "  OnCalendar=Sat *-*-* 11:00:00  # 周六上午11点"
echo "  OnCalendar=Sun *-*-* 02:00:00  # 周日凌晨2点"
echo "  OnCalendar=Mon *-*-* 14:30:00  # 周一下午2点30分"
echo ""
echo "修改后需要重新加载:"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl restart caddy-auto-build.timer"
echo ""
echo "验证修改:"
echo "  systemctl list-timers caddy-auto-build.timer"

echo ""
echo "========== 检查完成 =========="
