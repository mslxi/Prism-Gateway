# 🚀 Prism Gateway 全新发布：重新定义网络流量管理

![Prism Gateway](https://img.shields.io/badge/Prism-Gateway-blue) ![Version](https://img.shields.io/badge/version-1.0.0-green) ![License](https://img.shields.io/badge/license-MIT-orange)

**Prism Gateway** 是一个现代化的分布式 DNS 与代理管理平台，专为灵活、高效的流量调度而生。通过直观的 Web 面板与高性能 Agent，让复杂的网络规则配置变得触手可及。

---

## 📑 目录

- [核心亮点](#核心亮点)  
- [极速上手指南](#⚡-prism-gateway-极速上手指南)  
  - [注册与登录](#1-注册与登录)  
  - [创建节点 (Get Token)](#1-创建节点-get-token)  
  - [一键接入 (Run Script)](#2-一键接入-run-script)  
  - [配置生效 (Connect)](#3-配置生效-connect)  
- [部署优势](#prism-gateway-——-部署仅需-10-秒流量调度从此随心所欲-✨)

---

## ✨ 核心亮点

### 🌐 智能分流引擎  
支持自定义 **DOMAIN、SUFFIX、KEYWORD** 及 **Rule-Set (YAML)** 等多种规则匹配模式，精准控制 DNS 解析路径与流量转发目标。

### 🛡️ 双模管理架构  
- ~~托管模式 (Managed)：管理员统一维护节点与规则，用户零配置接入。~~  
- **公开模式 (Public)：** 用户拥有独立空间，可自由部署私有节点并定义专属路由规则。

### ⚡ GOST 编写高性能 Agent  
单二进制文件极速部署，支持 **DNS (劫持/解析)** 与 **Proxy (流量转发)** 双重角色，内置自动心跳保活与掉线检测。

### 🎨 极致交互体验  
全新的 **流体玻璃 (Liquid Glass) UI** 设计，完美适配移动端操作。管理网络也能赏心悦目。

### 🧩 扩展能力增强  
- **解锁机器支持添加为 Group 组**，组内的多台解锁机器可按照设定的优先级进行 **FALLBACK 切换**，保证主节点异常时流量自动切换到备用节点，实现高可用与负载均衡。  
- **解锁机器自动将接入的 DNS Client IP 加入白名单**，任何未在白名单中的 IP 都会被拒绝访问，从而保证网络流量安全，防止非授权访问。

---

## Prism Gateway —— 掌控您的网络边界，从未如此简单

立即体验：  
[🌐 访问官网](https://prism.ciii.club)  

---

# ⚡ Prism Gateway 极速上手指南

欢迎使用 **Prism Gateway —— 您的下一代网络流量调度中心**。  
只需简单几步，即可构建属于您的私有全球加速网络与 DNS 策略组。

---

## 1. 注册与登录

访问官方控制台：  
🔗 [https://prism.ciii.club](https://prism.ciii.club)

1. 点击 **"Register"** 创建您的个人账户。  
2. 登录后，您将进入直观的 **流体玻璃 (Liquid Glass) 仪表盘**。

> 注：公开模式下，每位用户拥有独立的空间，您的节点与规则完全私有隔离。

---

## 1. 创建节点 (Get Token)

进入控制台 **Nodes** 页面，点击 **"Deploy"**。

- **Proxy Node：** 用于解锁服务器。  
- **DNS Client：** 接入解锁服务器进行流量分流。

创建成功后，复制系统生成的一键安装命令。

---

## 2. 一键接入 (Run Script)

在您的服务器或设备终端中，粘贴并运行该命令：

```bash
# 示例（请使用控制台生成的实际命令）
curl -sL https://.../install.sh | sudo bash -s -- --master https://prism.ciii.club --secret <您的密钥>
```

脚本将自动完成：

- ✅ 自动识别系统架构 (AMD64/ARM64)  
- ✅ 下载最新版高性能 Agent  
- ✅ 配置 Systemd 进程守护与开机自启  
- ✅ 智能识别节点类型并输出配置指引

---

## 3. 配置生效 (Connect)

- **Proxy 节点：** 安装完成后即可在控制台 Rules 页被调用。  
- **DNS 节点：** 脚本运行后，请将您的 VPS 的 DNS 服务器修改为 `127.0.0.1`。

---

# Prism Gateway —— 部署仅需 10 秒，流量调度从此随心所欲 ✨

---

## 🔗 快速链接

- [官网](https://prism.ciii.club)  
- [GitHub](https://github.com/mslxi/prism-gateway)  
