#!/bin/bash

# ==========================================
# Prism Agent 一键安装脚本
# 仓库: https://github.com/mslxi/Prism-Gateway
# ==========================================

set -e # 遇到错误立即退出

# --- 1. 全局变量与配置 ---
REPO="mslxi/Prism-Gateway"
BINARY_NAME="prism-agent"
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/prism-agent.service"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- 2. 检查 Root 权限 ---
if [ "$EUID" -ne 0 ]; then
  error "请使用 root 权限运行此脚本 (sudo bash install.sh ...)"
fi

# --- 3. 参数解析 (--master, --secret, --smart) ---
MASTER_ADDR=""
SECRET_TOKEN=""
ENABLE_SMART=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --master)
      MASTER_ADDR="$2"
      shift 2
      ;;
    --secret)
      SECRET_TOKEN="$2"
      shift 2
      ;;
    --smart)
      ENABLE_SMART="true"
      shift 1 # --smart 是开关参数，不需要吃掉下一个值
      ;;
    *)
      shift # 忽略未知参数
      ;;
  esac
done

if [ -z "$MASTER_ADDR" ] || [ -z "$SECRET_TOKEN" ]; then
    error "必须提供 --master 和 --secret 参数。\n示例: curl -sL ... | bash -s -- --master http://1.2.3.4:8080 --secret mytoken [--smart]"
fi

# 构建启动参数
AGENT_ARGS="--master \"$MASTER_ADDR\" --secret \"$SECRET_TOKEN\""
if [ -n "$ENABLE_SMART" ]; then
    AGENT_ARGS="$AGENT_ARGS --smart"
    info "🌟 已启用 Smart Mode (智能区域解锁)"
fi

# --- 4. 自动探测系统架构 ---
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
    error "不支持的架构: $ARCH"
    ;;
esac

# 假设您的 Release 文件命名格式为: prism-agent_linux_amd64
ASSET_NAME="${BINARY_NAME}_${OS}_${ARCH_SUFFIX}"

info "检测到系统环境: $OS / $ARCH_SUFFIX"

# --- 5. 获取 GitHub 最新版本 ---
info "正在查询最新版本..."

# 使用 GitHub API 获取最新 release 的下载链接
# 如果是在国内环境，可能需要考虑 API 访问问题，这里保持原逻辑
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | \
  grep "browser_download_url" | \
  grep "$ASSET_NAME" | \
  cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
  # Fallback: 如果 API 限制或找不到，尝试拼接 URL (假设 latest 标签存在)
  warn "无法通过 API 获取下载链接 (可能受限于 API 速率)，尝试直接拼接 URL..."
  DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$ASSET_NAME"
fi

info "下载链接: $DOWNLOAD_URL"

# --- 6. 下载与安装 ---
info "开始下载..."
curl -L -o "/tmp/$BINARY_NAME" "$DOWNLOAD_URL" --progress-bar

if [ ! -f "/tmp/$BINARY_NAME" ]; then
    error "下载失败，文件不存在。"
fi

info "安装二进制文件到 $INSTALL_DIR..."
chmod +x "/tmp/$BINARY_NAME"
mv "/tmp/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"

# --- 7. 配置 Systemd 服务 ---
info "配置 Systemd 服务..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Prism Agent Service
After=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=5s
# 使用动态构建的参数，包含可能存在的 --smart
ExecStart=$INSTALL_DIR/$BINARY_NAME $AGENT_ARGS
# 增加文件描述符限制，避免高并发连接失败
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# --- 8. 启动服务 ---
info "重载并启动服务..."
systemctl daemon-reload
systemctl enable prism-agent
systemctl restart prism-agent

# --- 9. 验证状态 ---
sleep 2
if systemctl is-active --quiet prism-agent; then
    info "✅ Prism Agent 安装并启动成功！"
    info "查看日志命令: journalctl -u prism-agent -f"
else
    error "❌ 服务启动失败，请检查日志: systemctl status prism-agent"
fi
