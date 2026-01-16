#!/bin/bash

# ==========================================
# Prism Agent 一键安装脚本 (Smart Log Analysis)
# 仓库: https://github.com/mslxi/Prism-Gateway
# 更新: 支持 --uninstall, --beta, --smart
# ==========================================

set -e

# --- 全局配置 ---
REPO="mslxi/Prism-Gateway"
BINARY_NAME="prism-agent"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="prism-agent"
SCRIPT_URL="https://raw.githubusercontent.com/mslxi/Prism-Gateway/refs/heads/main/install.sh"

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
    UNINSTALL_MODE=false
    BETA_MODE=false
    SMART_MODE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --master) MASTER_ADDR="$2"; shift 2 ;;
            --secret) SECRET_TOKEN="$2"; shift 2 ;;
            --name)   SERVICE_NAME="$2"; shift 2 ;;
            --uninstall) UNINSTALL_MODE=true; shift ;;
            --beta)   BETA_MODE=true; shift ;;
            --smart)  SMART_MODE=true; shift ;; # 🟢 新增 Smart 参数
            *) shift ;;
        esac
    done

    # 卸载模式跳过检查
    if [ "$UNINSTALL_MODE" = true ]; then
        return
    fi

    if [ -z "$MASTER_ADDR" ] || [ -z "$SECRET_TOKEN" ]; then
        echo -e "${YELLOW}参数缺失！${NC}"
        echo -e "用法: ... | bash -s -- --master URL --secret TOKEN [--beta] [--smart]"
        exit 1
    fi
}

# 3. 卸载逻辑
uninstall_prism() {
    step "正在卸载 Prism Agent ($SERVICE_NAME)..."
    
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    
    if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        rm "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
    fi
    
    if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
        rm "$INSTALL_DIR/$BINARY_NAME"
    fi
    
    info "✅ 卸载完成。"
    exit 0
}

# 4. 系统探测
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

# 5. 下载二进制文件
download_binary() {
    step "正在获取版本信息..."

    # 确定 API 地址
    if [ "$BETA_MODE" = true ]; then
        # Beta 模式：获取所有 Release 列表
        API_URL="https://api.github.com/repos/$REPO/releases"
        info "模式: ${YELLOW}Beta Channel (Pre-release)${NC}"
    else
        # 默认模式：仅获取 Latest Stable
        API_URL="https://api.github.com/repos/$REPO/releases/latest"
        info "模式: ${GREEN}Stable Channel (Official)${NC}"
    fi
    
    # 获取版本信息
    RESP=$(curl -s --connect-timeout 5 "$API_URL")

    # 解析 Tag 和 下载链接
    VERSION=$(echo "$RESP" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
    DOWNLOAD_URL=$(echo "$RESP" | grep "browser_download_url" | grep "$ASSET_NAME" | head -n 1 | cut -d '"' -f 4)

    if [ -n "$VERSION" ]; then
        info "发现版本: ${CYAN}${VERSION}${NC}"
    else
        warn "无法通过 API 获取版本信息，尝试使用通用链接..."
    fi

    # 回退策略
    if [ -z "$DOWNLOAD_URL" ]; then
        if [ "$BETA_MODE" = true ]; then
            warn "Beta 版本获取失败，回退到最新稳定版 (Latest Stable)..."
        fi
        DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$ASSET_NAME"
    fi

    info "下载地址: $DOWNLOAD_URL"
    curl -L -o "/tmp/$BINARY_NAME" "$DOWNLOAD_URL" --progress-bar

    if [ ! -f "/tmp/$BINARY_NAME" ]; then
        error "下载失败，请检查网络或 GitHub 访问。"
    fi

    chmod +x "/tmp/$BINARY_NAME"
    
    # 停止旧服务
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        info "停止旧服务..."
        systemctl stop "$SERVICE_NAME"
    fi

    mv "/tmp/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
}

# 6. 配置服务
configure_service() {
    step "配置系统服务..."
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    # 🟢 动态构建启动参数
    EXEC_ARGS="--master \"$MASTER_ADDR\" --secret \"$SECRET_TOKEN\""
    if [ "$SMART_MODE" = true ]; then
        EXEC_ARGS="$EXEC_ARGS --smart"
    fi

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Prism Agent ($SERVICE_NAME)
After=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=5s
ExecStart=$INSTALL_DIR/$BINARY_NAME $EXEC_ARGS
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
}

# 7. 启动与检测
start_service() {
    step "启动服务..."
    systemctl restart "$SERVICE_NAME"
    
    info "等待初始化..."
    sleep 3

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        error "启动失败！请查看日志: journalctl -u $SERVICE_NAME -n 20"
    fi
}

analyze_mode_and_prompt() {
    LOGS=$(journalctl -u "$SERVICE_NAME" -n 50 --no-pager)
    echo ""
    echo "---------------------------------------------------"
    info "✅ 安装成功！[$SERVICE_NAME] 正在运行。"
    
    if [ "$BETA_MODE" = true ]; then
        echo -e "⚠️  当前为 ${YELLOW}Beta 测试版${NC}，如遇 Bug 请反馈。"
    fi
    
    # 🟢 显示 Smart Mode 状态
    if [ "$SMART_MODE" = true ]; then
        echo -e "🌟 特性: ${CYAN}Smart Mode 已启用${NC} (区域流媒体解锁)"
    fi
    echo "---------------------------------------------------"

    if echo "$LOGS" | grep -q "DNS Mode Started"; then
        echo -e "🌐 模式: ${CYAN}DNS Client${NC} (请设置 DNS 为 127.0.0.1)"
    elif echo "$LOGS" | grep -q "Proxy Mode Started"; then
        echo -e "🚀 模式: ${CYAN}Proxy Node${NC} (请放行 80/443 端口)"
    else
        warn "正在同步配置，请稍后查看日志。"
    fi
    
    echo ""
    echo -e "🗑️  卸载命令: ${GREEN}curl -sL $SCRIPT_URL | sudo bash -s -- --uninstall${NC}"
    echo ""
}

# --- 主程序 ---
main() {
    check_root
    parse_args "$@"
    
    if [ "$UNINSTALL_MODE" = true ]; then
        uninstall_prism
    fi

    detect_system
    download_binary
    configure_service
    start_service
    analyze_mode_and_prompt
}

main "$@"
