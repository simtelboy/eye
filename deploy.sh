#!/bin/bash

# 快速部署脚本

echo "========== Caddy 自动编译系统快速部署 =========="

# 检查是否为 root
if [[ $EUID -ne 0 ]]; then
   echo "错误: 此脚本需要 root 权限运行"
   echo "请使用: sudo ./deploy.sh"
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

# 设置文件权限
echo "设置文件权限..."
chmod +x install.sh
chmod +x caddy-auto-build.sh
chmod +x clean-install.sh
chmod +x install-dependencies.sh
chmod +x remove-dependencies.sh
chmod +x upload-caddy.sh
chmod +x check-timezone.sh

# 运行安装
echo "开始安装..."
./install.sh

echo ""
echo "========== 部署完成 =========="
echo ""
echo "下一步操作:"
echo "1. 编辑配置文件设置 GitHub Token:"
echo "   nano /root/caddy-build-config.json"
echo ""
echo "2. 手动测试运行:"
echo "   ./caddy-auto-build.sh"
echo ""
echo "3. 查看系统状态:"
echo "   systemctl status caddy-auto-build.timer"
echo ""
echo "GitHub Token 获取地址:"
echo "https://github.com/settings/tokens"
echo ""
echo "需要的权限: repo (完整仓库权限)"
