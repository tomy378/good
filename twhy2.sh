#!/bin/bash

set -e

# ====================================================================================
# Sing-box Hysteria2 (台湾流媒体分流) 安装脚本
# 功能:
# 1. 自动申请 Let's Encrypt 证书。
# 2. 使用固定端口和密码，并集成台湾流媒体分流规则。
# 3. 自动安装 Sing-box 并创建 Systemd 服务。
# 注意: 此版本已移除防火墙管理，请手动在云平台放行端口。
# ====================================================================================

# --- 1. 定义固定配置 ---
PORT1=45678
PORT2=56789
PORT3=23456
PASSWORD="Kn1cLcpk9YYcSpB3D1zKhQ=="

# --- 2. 准备工作 ---
# 检查是否以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "错误：请以 root 权限运行此脚本"
    exit 1
fi

# 获取用户输入的域名
read -p "请输入你的域名 (例如 hk.8238683.xyz): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    echo "❌ 域名不能为空，脚本终止"
    exit 1
fi

# 定义路径变量
CONFIG_DIR="/usr/local/etc/sing-box"
SINGBOX_CONFIG="$CONFIG_DIR/config.json"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
INFO_FILE="$CONFIG_DIR/info.conf"

# --- 3. 安装依赖与申请证书 ---
echo "📦 正在安装基本依赖..."
apt update && apt install -y curl wget socat unzip jq nginx qrencode lsb-release openssl

# 停止可能冲突的服务
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

echo "🔐 正在安装 certbot 并申请 Let's Encrypt 证书..."
apt install -y certbot
certbot certonly --standalone -d "$DOMAIN" --email "admin@$DOMAIN" --agree-tos --no-eff-email

if [ $? -ne 0 ]; then
    echo "❌ 错误：证书申请失败，请检查域名解析或端口 80 是否开放"
    exit 1
fi
echo "✅ 证书申请成功！"

# --- 4. 安装与配置 Sing-box ---
echo "🚀 正在安装 Sing-box..."
curl -sSL https://sing-box.app/install.sh | bash
echo "✅ Sing-box 安装完成！"

echo "📝 正在创建 Sing-box 配置文件..."
mkdir -p "$CONFIG_DIR"

# 使用 Heredoc 创建配置文件 (集成台湾流媒体分流规则)
cat > "$SINGBOX_CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in-1",
      "listen": "::",
      "listen_port": $PORT1,
      "up_mbps": 50,
      "down_mbps": 800,
      "users": [
        { "password": "$PASSWORD" }
      ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CERT_PATH",
        "key_path": "$KEY_PATH"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in-2",
      "listen": "::",
      "listen_port": $PORT2,
      "up_mbps": 50,
      "down_mbps": 800,
      "users": [
        { "password": "$PASSWORD" }
      ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CERT_PATH",
        "key_path": "$KEY_PATH"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in-3",
      "listen": "::",
      "listen_port": $PORT3,
      "up_mbps": 50,
      "down_mbps": 800,
      "users": [
        { "password": "$PASSWORD" }
      ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CERT_PATH",
        "key_path": "$KEY_PATH"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-out"
    },
    {
      "type": "socks",
      "tag": "tw_proxy",
      "server": "127.0.0.1",
      "server_port": 40000,
      "version": "5"
    }
  ],
  "route": {
    "rules": [
      {
        "domain_suffix": [
          "linetv.tw", "api.linetv.tw", "d3c7rimkq79yfu.cloudfront.net",
          "myvideo.net.tw", "api.myvideo.net.tw", "hichannel.hinet.net",
          "friday.tw", "video.friday.tw", "api.friday.tw", "vod.friday.tw",
          "kktv.me", "api.kktv.me", "kktv.com.tw", "kktv.videohub.tv",
          "ptsplus.tv", "api.ptsplus.tv", "ottstream.ptsplus.tv",
          "hamivideo.hinet.net", "hamivideo.net", "hamivideo.ott.hinet.net",
          "hamivideo.ctitv.com.tw", "hamivideo.api.hinet.net",
          "4gtv.tv", "ip.me"
        ],
        "outbound": "tw_proxy"
      }
    ],
    "final": "direct-out"
  }
}
EOF

echo "✅ 配置文件创建成功！"

# --- 5. 服务管理 ---
echo "🔧 正在创建 Systemd 服务文件..."
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.app
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/usr/local/etc/sing-box
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=/usr/bin/sing-box run -c /usr/local/etc/sing-box/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
echo "✅ Systemd 服务文件创建成功！"

echo "▶️ 正在重载、启动并启用 Sing-box 服务..."
systemctl daemon-reload
systemctl enable --now sing-box

# 检查服务状态
if systemctl is-active --quiet sing-box; then
    echo "✅ Sing-box 服务已成功启动！"
else
    echo "❌ 错误：Sing-box 服务启动失败，请使用 'journalctl -u sing-box -f' 查看日志"
    exit 1
fi


# --- 6. 保存信息并创建快捷方式 ---
echo "💾 正在保存配置信息用于快捷方式..."
cat > "$INFO_FILE" <<EOF
DOMAIN="$DOMAIN"
PORT1="$PORT1"
PORT2="$PORT2"
PORT3="$PORT3"
PASSWORD="$PASSWORD"
EOF

echo "✨ 正在创建快捷命令 'sing-box-info'..."
cat > /usr/local/bin/sing-box-info <<'EOF'
#!/bin/bash
# 快捷方式: 用于显示 sing-box 连接信息

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

INFO_FILE="/usr/local/etc/sing-box/info.conf"

if [ ! -f "$INFO_FILE" ]; then
    echo -e "${YELLOW}❌ 配置文件 ${INFO_FILE} 未找到!${NC}"
    exit 1
fi

# 加载保存的变量
source "$INFO_FILE"

# 检查 qrencode 是否安装
if ! command -v qrencode &> /dev/null; then
    echo -e "${YELLOW}警告: qrencode 未安装，无法显示二维码。${NC}"
    echo "您可以使用 'apt install qrencode' 来安装它。"
fi

# 生成分享链接
SHARE_LINK_1="hysteria2://$PASSWORD@$DOMAIN:$PORT1?sni=$DOMAIN#${DOMAIN}_$PORT1"
SHARE_LINK_2="hysteria2://$PASSWORD@$DOMAIN:$PORT2?sni=$DOMAIN#${DOMAIN}_$PORT2"
SHARE_LINK_3="hysteria2://$PASSWORD@$DOMAIN:$PORT3?sni=$DOMAIN#${DOMAIN}_$PORT3"

# 显示配置信息
echo -e "${GREEN}🎉🎉� Hysteria2 服务器配置信息 🎉🎉🎉${NC}"
echo "=================================================="
echo -e "${YELLOW}以下是您的客户端连接信息：${NC}"
echo ""
echo -e "地址 (Address):         ${CYAN}$DOMAIN${NC}"
echo -e "端口 (Port):            ${CYAN}$PORT1, $PORT2, $PORT3${NC} (三个任选其一)"
echo -e "密码 (Password):        ${CYAN}$PASSWORD${NC}"
echo -e "SNI / Server Name:      ${CYAN}$DOMAIN${NC}"
echo -e "允许不安全 (AllowInsecure): ${CYAN}不勾选${NC}（因为使用的是有效证书）"
echo ""
echo -e "${YELLOW}----------------- 分享链接 (可用于 V2RayN, NekoBox 等) -----------------${NC}"
echo ""
echo -e "端口 ${CYAN}$PORT1${NC}:"
command -v qrencode &> /dev/null && qrencode -t ANSIUTF8 "$SHARE_LINK_1"
echo -e "链接: ${GREEN}$SHARE_LINK_1${NC}"
echo ""
echo -e "端口 ${CYAN}$PORT2${NC}:"
command -v qrencode &> /dev/null && qrencode -t ANSIUTF8 "$SHARE_LINK_2"
echo -e "链接: ${GREEN}$SHARE_LINK_2${NC}"
echo ""
echo -e "端口 ${CYAN}$PORT3${NC}:"
command -v qrencode &> /dev/null && qrencode -t ANSIUTF8 "$SHARE_LINK_3"
echo -e "链接: ${GREEN}$SHARE_LINK_3${NC}"
echo "=================================================="
EOF

# 赋予快捷方式执行权限
chmod +x /usr/local/bin/sing-box-info
echo "✅ 快捷方式创建成功！"

# --- 7. 最终显示 ---
# 调用一次快捷方式来显示最终结果
/usr/local/bin/sing-box-info

# 额外提示
echo -e "${YELLOW}💡 快捷提示：您可以随时在服务器上运行 'sing-box-info' 命令来重新显示此信息。${NC}"