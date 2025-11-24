#!/bin/bash

# ==========================================
# Prism Agent 一键安装脚本 (Auto-Update Version)
# 仓库: https://github.com/mslxi/Prism-Gateway
# ==========================================

set -e

REPO="mslxi/Prism-Gateway"
BINARY_NAME="prism-agent"
INSTALL_DIR="/usr/local/bin"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- 1. 检查 Root 权限 ---
if [ "$EUID" -ne 0 ]; then
  error "请使用 sudo 运行此脚本"
fi

# --- 2. 参数解析 ---
MASTER_ADDR=""
SECRET_TOKEN=""
SERVICE_NAME="prism-agent"

while [[ $# -gt 0 ]]; do
  case $1 in
    --master) MASTER_ADDR="$2"; shift 2 ;;
    --secret) SECRET_TOKEN="$2"; shift 2 ;;
    --name)   SERVICE_NAME="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$MASTER_ADDR" ] || [ -z "$SECRET_TOKEN" ]; then
    error "参数缺失！\n用法: curl ... | bash -s -- --master http://IP:8080 --secret YOUR_TOKEN"
fi

# --- 3. 自动探测架构 ---
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

case "$ARCH" in
  x86_64)
    ARCH_SUFFIX="amd64"
    ;;
  aarch64|arm64)
    ARCH_SUFFIX="arm64"
    ;;
  *)
    error "不支持的系统架构: $ARCH"
    ;;
esac

ASSET_NAME="${BINARY_NAME}_${OS}_${ARCH_SUFFIX}"
info "检测到系统环境: ${CYAN}${OS}/${ARCH_SUFFIX}${NC}"

# --- 4. 获取最新版本号 (新增逻辑) ---
info "正在检查 GitHub 最新版本..."

# 请求 GitHub API
LATEST_RESP=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")

# 尝试提取 tag_name (例如 v1.0.20240101)
# grep 匹配 "tag_name": "..." 然后 cut 提取引号中间的内容
VERSION=$(echo "$LATEST_RESP" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)

# 尝试提取下载链接
DOWNLOAD_URL=$(echo "$LATEST_RESP" | grep "browser_download_url" | grep "$ASSET_NAME" | head -n 1 | cut -d '"' -f 4)

if [ -n "$VERSION" ]; then
    info "发现最新版本: ${CYAN}${VERSION}${NC}"
else
    warn "无法获取版本号 (可能受限于 GitHub API 速率)，尝试使用 latest 链接盲装..."
fi

# 如果 API 没拿到链接，使用固定的 latest 结构进行回退
if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$ASSET_NAME"
fi

# --- 5. 下载与更新 ---
# 逻辑：总是下载最新版覆盖，确保版本一致性
info "准备下载: $DOWNLOAD_URL"
curl -L -o "/tmp/$BINARY_NAME" "$DOWNLOAD_URL" --progress-bar

if [ ! -f "/tmp/$BINARY_NAME" ]; then
    error "下载失败，文件 /tmp/$BINARY_NAME 不存在，请检查网络或文件名。"
fi

# 安装
chmod +x "/tmp/$BINARY_NAME"
# 停止旧服务(如果存在)以释放文件锁
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
mv "/tmp/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
info "二进制文件已安装到: $INSTALL_DIR/$BINARY_NAME"

# --- 6. 配置 Systemd ---
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
info "更新服务配置: $SERVICE_FILE"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Prism Agent ($SERVICE_NAME)
After=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=5s
# 强制复写启动参数
ExecStart=$INSTALL_DIR/$BINARY_NAME --master "$MASTER_ADDR" --secret "$SECRET_TOKEN"
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# --- 7. 启动服务 ---
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# --- 8. 状态检查与提示 ---
sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo ""
    info "✅ 安装成功！服务 [${CYAN}$SERVICE_NAME${NC}] 已启动。"
    info "当前版本: ${VERSION:-Unknown}"
    echo ""
    echo "---------------------------------------------------"
    echo "🛑 [DNS 节点提示]"
    echo "如果这是 DNS 节点，请修改系统 DNS 指向本机:"
    echo "   sudo sed -i 's/^nameserver.*/nameserver 127.0.0.1/' /etc/resolv.conf"
    echo ""
    echo "🔍 [日志查看]"
    echo "   journalctl -u $SERVICE_NAME -f"
    echo "---------------------------------------------------"
else
    error "服务启动失败，请运行: systemctl status $SERVICE_NAME"
fi
