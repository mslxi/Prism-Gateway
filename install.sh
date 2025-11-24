#!/bin/bash

# ==========================================
# Prism Agent 一键安装脚本 (Smart Log Analysis)
# 仓库: https://github.com/mslxi/Prism-Gateway
# ==========================================

set -e

# --- 全局配置 ---
REPO="mslxi/Prism-Gateway"
BINARY_NAME="prism-agent"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="prism-agent"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 辅助函数 ---
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 1. 权限检查
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "请使用 sudo 或 root 权限运行此脚本"
    fi
}

# 2. 参数解析
parse_args() {
    MASTER_ADDR=""
    SECRET_TOKEN=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --master) MASTER_ADDR="$2"; shift 2 ;;
            --secret) SECRET_TOKEN="$2"; shift 2 ;;
            --name)   SERVICE_NAME="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [ -z "$MASTER_ADDR" ] || [ -z "$SECRET_TOKEN" ]; then
        echo -e "${YELLOW}参数缺失！${NC}"
        echo -e "用法: curl ... | bash -s -- --master http://IP:8080 --secret YOUR_TOKEN [--name my-agent]"
        exit 1
    fi
}

# 3. 系统探测
detect_system() {
    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')

    case "$ARCH" in
        x86_64) ARCH_SUFFIX="amd64" ;;
        aarch64|arm64) ARCH_SUFFIX="arm64" ;;
        *) error "不支持的系统架构: $ARCH" ;;
    esac

    ASSET_NAME="${BINARY_NAME}_${OS}_${ARCH_SUFFIX}"
    info "环境检测: ${OS} / ${ARCH_SUFFIX}"
}

# 4. 下载二进制文件
download_binary() {
    step "正在获取版本信息..."
    
    # 尝试通过 GitHub API 获取最新版
    LATEST_RESP=$(curl -s --connect-timeout 5 "https://api.github.com/repos/$REPO/releases/latest")
    VERSION=$(echo "$LATEST_RESP" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
    DOWNLOAD_URL=$(echo "$LATEST_RESP" | grep "browser_download_url" | grep "$ASSET_NAME" | head -n 1 | cut -d '"' -f 4)

    if [ -n "$VERSION" ]; then
        info "目标版本: ${CYAN}${VERSION}${NC}"
    else
        warn "无法获取版本号，尝试使用 latest 通用链接..."
    fi

    # 回退链接
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$ASSET_NAME"
    fi

    info "下载地址: $DOWNLOAD_URL"
    curl -L -o "/tmp/$BINARY_NAME" "$DOWNLOAD_URL" --progress-bar

    if [ ! -f "/tmp/$BINARY_NAME" ]; then
        error "下载失败，请检查网络连接。"
    fi

    chmod +x "/tmp/$BINARY_NAME"
    
    # 尝试停止服务以释放文件锁
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        info "停止旧服务..."
        systemctl stop "$SERVICE_NAME"
    fi

    mv "/tmp/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    info "安装路径: $INSTALL_DIR/$BINARY_NAME"
}

# 5. 配置 Systemd 服务
configure_service() {
    step "配置系统服务..."
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Prism Agent ($SERVICE_NAME)
After=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=5s
ExecStart=$INSTALL_DIR/$BINARY_NAME --master "$MASTER_ADDR" --secret "$SECRET_TOKEN"
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    info "服务已配置并设置开机自启"
}

# 6. 启动服务
start_service() {
    step "启动服务..."
    systemctl restart "$SERVICE_NAME"
    
    # 等待服务初始化并产生日志
    info "等待 Agent 初始化 (5秒)..."
    sleep 5

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        error "服务启动失败！请检查日志: journalctl -u $SERVICE_NAME -n 20"
    fi
}

# 7. 智能日志分析与提示 (核心新功能)
analyze_mode_and_prompt() {
    step "分析节点运行模式..."
    
    # 读取最近的日志
    LOGS=$(journalctl -u "$SERVICE_NAME" -n 50 --no-pager)

    echo ""
    echo "---------------------------------------------------"
    info "✅ 安装成功！服务 [${CYAN}$SERVICE_NAME${NC}] 正在运行。"
    echo "---------------------------------------------------"

    # 匹配 Go 代码中的日志关键词
    if echo "$LOGS" | grep -q "DNS Mode Started"; then
        # --- DNS 模式提示 ---
        echo -e "🌐 检测到模式: ${CYAN}DNS Client (接入端)${NC}"
        echo ""
        echo -e "${YELLOW}👉 [必须执行] 请修改系统 DNS 指向本机:${NC}"
        echo -e "   临时生效: ${GREEN}sudo echo 'nameserver 127.0.0.1' > /etc/resolv.conf${NC}"
        echo -e "   (建议根据您的 Linux 发行版配置永久 DNS)"
        echo ""
        echo "   此节点将作为局域网或其他设备的 DNS 网关。"

    elif echo "$LOGS" | grep -q "Proxy Mode Started"; then
        # --- Proxy 模式提示 ---
        echo -e "🚀 检测到模式: ${CYAN}Proxy Node (出口端)${NC}"
        echo ""
        echo -e "${YELLOW}👉 [注意事项] 请确保防火墙放行端口:${NC}"
        echo -e "   TCP: ${GREEN}80, 443${NC}"
        echo ""
        echo "   该节点现已准备好接收并转发流量。"
    
    else
        # --- 未知/等待中 ---
        warn "暂未检测到明确的模式日志 (可能正在同步配置或端口被占用)。"
        echo "请稍后通过以下命令查看详细状态:"
        echo "   journalctl -u $SERVICE_NAME -f"
    fi
    echo "---------------------------------------------------"
}

# --- 主程序流程 ---
main() {
    check_root
    parse_args "$@"
    detect_system
    download_binary
    configure_service
    start_service
    analyze_mode_and_prompt
}

# 执行主程序
main "$@"
