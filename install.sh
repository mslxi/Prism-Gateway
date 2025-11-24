#!/bin/bash

# ==========================================
# Prism Agent 安装脚本 (Multi-Instance Support)
# ==========================================

set -e

REPO="mslxi/Prism-Gateway"
BINARY_NAME="prism-agent"
INSTALL_DIR="/usr/local/bin"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
  error "请使用 sudo 运行"
fi

# --- 参数解析 ---
MASTER_ADDR=""
SECRET_TOKEN=""
SERVICE_NAME="prism-agent" # 默认服务名

while [[ $# -gt 0 ]]; do
  case $1 in
    --master) MASTER_ADDR="$2"; shift 2 ;;
    --secret) SECRET_TOKEN="$2"; shift 2 ;;
    --name)   SERVICE_NAME="$2"; shift 2 ;; # 支持自定义服务名
    *) shift ;;
  esac
done

if [ -z "$MASTER_ADDR" ] || [ -z "$SECRET_TOKEN" ]; then
    error "必须提供参数: --master 和 --secret\n可选参数: --name (用于同机部署多个Agent)"
fi

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
info "准备部署服务: $SERVICE_NAME"

# --- 架构检测 ---
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$ARCH" in
  x86_64) ARCH_SUFFIX="amd64" ;;
  aarch64|arm64) ARCH_SUFFIX="arm64" ;;
  *) error "不支持架构: $ARCH" ;;
esac
ASSET_NAME="${BINARY_NAME}_${OS}_${ARCH_SUFFIX}"

# --- 下载二进制 (如果是第一次安装或强制更新) ---
# 只要二进制文件存在，我们就假设它是可用的。
# 如果需要强制更新，用户可以手动删掉 /usr/local/bin/prism-agent
if [ ! -f "$INSTALL_DIR/$BINARY_NAME" ]; then
    info "正在从 GitHub 下载最新版本..."
    DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep "browser_download_url" | grep "$ASSET_NAME" | cut -d '"' -f 4)
    
    if [ -z "$DOWNLOAD_URL" ]; then
        # Fallback
        DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$ASSET_NAME"
    fi
    
    curl -L -o "/tmp/$BINARY_NAME" "$DOWNLOAD_URL" --progress-bar
    chmod +x "/tmp/$BINARY_NAME"
    mv "/tmp/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
else
    info "二进制文件已存在，跳过下载..."
fi

# --- 配置 Systemd (支持多实例) ---
info "配置 Systemd: $SERVICE_FILE"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Prism Agent ($SERVICE_NAME)
After=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=5s
# 关键：指向同一个二进制文件，但使用不同的参数
ExecStart=$INSTALL_DIR/$BINARY_NAME --master "$MASTER_ADDR" --secret "$SECRET_TOKEN"
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# --- 启动 ---
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
    info "✅ 安装成功! 服务名: $SERVICE_NAME"
    info "日志: journalctl -u $SERVICE_NAME -f"
else
    error "启动失败，请检查日志"
fi

# --- 8. 启动服务 ---
info "重载并启动服务..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# --- 9. 验证状态与后续引导 ---
sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
    info "✅ 安装成功! 服务名: $SERVICE_NAME"
    
    # 智能提示：检测是否为 DNS 节点
    # 我们简单通过日志 grep 一下，或者提示用户
    echo ""
    echo "---------------------------------------------------"
    echo "🛑 后续步骤 (针对 DNS 节点):"
    echo "---------------------------------------------------"
    echo "Agent 已经启动，但为了让本机流量生效，您需要修改系统 DNS。"
    echo ""
    echo "👉 1. 测试 Agent 是否正常工作:"
    echo "   dig @127.0.0.1 google.com"
    echo "   (如果返回 IP，说明 Agent 正常)"
    echo ""
    echo "👉 2. 全局生效 (修改 /etc/resolv.conf):"
    echo "   sudo sed -i 's/^nameserver.*/nameserver 127.0.0.1/' /etc/resolv.conf"
    echo "   (注意：某些云厂商会自动重置此文件，请使用 chattr +i 锁定或修改 netplan)"
    echo ""
    echo "🔍 查看实时日志:"
    echo "   journalctl -u $SERVICE_NAME -f"
    echo "---------------------------------------------------"

else
    error "❌ 服务启动失败，请检查日志: systemctl status $SERVICE_NAME"
fi
