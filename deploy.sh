#!/bin/bash

# 快速部署脚本

echo "========== Caddy 自动编译系统快速部署 =========="

# 检查是否为 root
if [[ $EUID -ne 0 ]]; then
   echo "错误: 此脚本需要 root 权限运行"
   echo "请使用: sudo ./deploy.sh"
   exit 1
fi

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
