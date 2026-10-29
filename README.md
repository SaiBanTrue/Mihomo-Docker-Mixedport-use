# Mihomo-Docker-Mixedport 介绍（仅支持armbian）


一个基于 Alpine Linux 的轻量化 Mihomo (Clash Meta) 容器构建方案。支持自动化依赖预处理、多环境变量动态配置以及 GitHub Actions 自动化容器构建。  


## 特性

- **实时追踪与构建**：实现内核与面板的永久自动保鲜。(每3天检查一次mihomo内核和zashboard面板)
- **实现自定义yaml**：自定义yaml
- **macvlan+tun模式**：macvlan+tun模式下隔离宿主机网络和容器网络，稳定宿主机网络环境


## 致谢与参考

本项目基于以下等开源项目：
- [Dancying/Mihomo-Docker-Build](https://github.com/Dancying/Mihomo-Docker-Build)
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
- [Zephyruso/zashboard](https://github.com/Zephyruso/zashboard)


# 容器运行


**示例：macvlan模式+tun模式+自定义yaml文件**

步骤 1：查看宿主机当前默认物理网卡与网关信息
```text
# ----------------------------------------------------------------------
# 步骤 1：查看宿主机当前默认物理网卡与网关信息
# ----------------------------------------------------------------------
ip route show default
# 示例输出可能为：default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.100 metric 100
# 请确认物理网卡名称（如 eth0、enp3s0 等）以及网关地址（如 192.168.1.1）

# ----------------------------------------------------------------------
# 步骤 2：宿主机开启网卡混杂模式与 IP 转发
# ----------------------------------------------------------------------
# 开启混杂模式（以 eth0 为例，请替换为实际网卡名）
sudo ip link set eth0 promisc on

# NetworkManager 提供了原生 dispatcher 机制，混杂模式持久化：
sudo tee /etc/NetworkManager/dispatcher.d/99-eth0-promisc.sh << 'EOF'
#!/bin/bash
IFACE=$1
ACTION=$2

if [ "$IFACE" = "eth0" ] && [ "$ACTION" = "up" ]; then
    # 开启混杂模式
    ip link set eth0 promisc on
    # 强制锁定 eth0 在转发模式下接收 RA 通告
    sysctl -w net.ipv6.conf.eth0.accept_ra=2
fi
EOF

sudo chmod +x /etc/NetworkManager/dispatcher.d/99-eth0-promisc.sh

# ----------------------------------------------------------------------
# 步骤 3：IPv4 转发持久化
# ----------------------------------------------------------------------
sudo tee /etc/sysctl.d/99-network-forward.conf << 'EOF'
# 1. 彻底解禁系统 IPv6（防止新建虚拟网卡被默认禁用）
# net.ipv6.conf.all.disable_ipv6 = 0
# net.ipv6.conf.default.disable_ipv6 = 0

# 2. 开启 IPv4 与 IPv6 数据包转发
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# 3. 强制在转发模式下接收 RA 路由通告，防止 eth0 丢失默认 IPv6 网关
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2
net.ipv6.conf.eth0.accept_ra = 2
EOF

# 使配置立即生效
sudo sysctl --system

# ----------------------------------------------------------------------
# 步骤 4：reboot后混杂模式IPv4 和 转发持久化 验证
# ----------------------------------------------------------------------
ip link show eth0
# 第一行尖括号 <...> 中必须包含 PROMISC 标志。

sysctl net.ipv4.ip_forward \
       net.ipv6.conf.all.forwarding \
       net.ipv6.conf.default.forwarding \
       net.ipv6.conf.all.accept_ra \
       net.ipv6.conf.eth0.accept_ra
# 输出结果应与持久化配置完全一致：
# net.ipv4.ip_forward = 1
# net.ipv6.conf.all.forwarding = 1
# net.ipv6.conf.default.forwarding = 1
# net.ipv6.conf.all.accept_ra = 2
# net.ipv6.conf.eth0.accept_ra = 2

# 删除上面的持久化设置
sudo rm -f /etc/sysctl.d/99-network-forward.conf
sudo rm -f /etc/NetworkManager/dispatcher.d/99-eth0-promisc.sh

# ----------------------------------------------------------------------
# 步骤 5：清理同名旧网络并创建 Docker Macvlan 网络
# ----------------------------------------------------------------------
# 如果之前已经建过同名网络，先删除
docker network rm mihomo-macvlan 2>/dev/null || true

# 创建 Macvlan 网络（不加 --ip-range 限制，方便自由分配任意固定 IP）
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  -o parent=eth0 \
  mihomo-macvlan

# 验证网络是否创建成功
docker network ls | grep mihomo-macvlan

# ----------------------------------------------------------------------
# 步骤 6：mihomo部署
# 注：USE_CUSTOM_CONFIG="true"情况下+Tun
# 启动容器并指定固定IP
# ----------------------------------------------------------------------
docker run -d \
  --name mihomo \
  --restart always \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  --network mihomo-macvlan \
  --ip 192.168.1.250 \
  --device /dev/net/tun \
  -v /mnt/docker/mihomoconfig:/config \
  -e TZ=Asia/Shanghai \
  ghcr.io/saibantrue/mihomo:latest



# ----------------------------------------------------------------------
# 步骤 7：宿主机登录zashboard管理面板
# ----------------------------------------------------------------------

# 1. 重新创建 macvlan 子接口（物理网卡如不是 eth0 请替换）
sudo ip link add macvlan-host link eth0 type macvlan mode bridge

# 2. 分配 192.168.1.x 网段的未占用 IP 并启动网卡
sudo ip addr add 192.168.1.249/24 dev macvlan-host
sudo ip link set macvlan-host up

# 3. 将前往容器真实 IP 的流量引导到该接口
sudo ip route add 192.168.1.250/32 dev macvlan-host

# 4. 测试是否能ping通
ping -c 3 192.168.1.250

# 5. 安装redir
sudo apt install -y redir

# 6. 设置端口转发
# 映射控制面板 API 端口 (9090)
redir --lport=9090 --caddr=192.168.1.250 --cport=9090 &

sudo killall -9 redir socat 2>/dev/null

###### 上面6个部分，重启后失效

# 连通性测试
for i in $(seq 1 100); do
  curl -x http://127.0.0.1:7890 -o /dev/null -s -w "序号 $i: HTTP状态 %{http_code} | 延迟: %{time_total} 秒\n" https://www.google.com
  sleep 1
done


```

# 环境变量说明

变量用于控制容器的行为（如更新频率、订阅源、WebUI 设置等）。  
变量会直接修改并应用到 `/config/config.yaml` 配置文件中。 

| 环境变量 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `GEO_UPDATE` | `false` | 路由规则库开关。设为 `true` 时复制内置规则库至 `/config` 并启用自动更新；设为 `false` 时完全排除复制并保持禁用。 |

注：USE_CUSTOM_CONFIG="true"情况下, 仅WEBUI_LISTEN_ADDR, WEBUI_SECRET设置有效
# 文件结构

## Git 原始项目文件结构（源码库）

```text
Mihomo-Docker-Mixedport/
├── .github/
│   └── workflows/
│       └── docker-build.yml        # GitHub Actions 自动化构建与推送工作流
├── app/
│   ├── entrypoint.sh               # 容器主进程守护与拉起脚本
│   └──  mihomo_init.sh              # 容器环境初始化、资源挂载同步脚本
├── CoreUiGeo_download.sh           # CI 构建前置下载脚本（拉取上游内核、规则库、WebUI）
├── Dockerfile_image                # 镜像构建定义文件
├── LICENSE                         # 开源协议
└── README.md                       # 说明文档
```


## CI 预构建后的工作区文件结构（ghcrio_build.sh 执行后）

```text
Mihomo-Docker-Mixedport/
├── .github/ ...
├── app/
│   ├── entrypoint.sh
│   ├── mihomo_init.sh
│   ├── mihomo                      # 从 MetaCubeX 下载并解压的 arm64 核心二进制
│   └── res/                        # 外部静态资源目录
│       ├── geoip.metadb            # 从 meta-rules-dat 下载的 IP 分流规则库
│       ├── geosite.dat             # 从 meta-rules-dat 下载的域名分流规则库
│       └── WEBUI/                  # 从 Zephyruso/zashboard 下载解压的前端面板
│           ├── index.html
│           ├── assets/
│           │   ├── index-*.js
│           │   └── index-*.css
│           └── favicon.ico ...
├── CoreUiGeo_download.sh
├── Dockerfile_image
└── ...
```


## ghcr.io镜像仓库 / Docker 镜像内部静态文件结构

```text
/                                   # 容器根目录 (基于 Alpine Linux)
├── app/                            # 【只读核心区】(镜像固化，无需用户干预)
│   ├── mihomo                      # Mihomo 核心二进制可执行程序 (chmod +x)
│   ├── entrypoint.sh               # 容器主启动入口 (ENTRYPOINT)
│   ├── mihomo_init.sh              # 初始化脚本
│   └── res/                        # 随镜像打包的原始静态资产仓库
│       ├── geoip.metadb            # IP 分流规则库原始副本
│       ├── geosite.dat             # 域名分流规则库原始副本
│       └── WEBUI/                  # Zashboard 前端面板原始副本
│           └── ...
├── config/                         # 【数据卷挂载点】 (VOLUME 声明，VOLUME [ "/config" ] )
├── bin/                            # Alpine 基础命令工具箱 (bash, curl, tzdata, sed, awk)
├── etc/                            # 系统配置 (含 /etc/localtime 时区 Shanghai)
└── ...                             # (其他标准 Linux 根系统目录: /lib, /usr, /proc, /sys 等)
```


## 容器启动后（config_update.sh 运行后的文件变化）

```text
宿主机挂载目录（如 /mnt/data/docker/mihomoconfig）  # -v /mnt/data/docker/mihomoconfig:/config
├── config.yaml                     # 用户挂载的主配置文件（需自行提供）
├── geoip.metadb                    # 路由 IP 分流数据库（GEO_UPDATE=true 时复制）
├── geosite.dat                     # 路由域名分流数据库（GEO_UPDATE=true 时复制）
└── ui/                             # Web 控制面板主目录
    └── zashboard/                  # Zashboard 静态网页资源（浏览器直接访问），来自于WEBUI
        ├── index.html
        └── assets/
```

# ghcr.io构建更新记录

<!-- BUILD_INFO_START -->
- **更新时间**：`2026-10-22 15:11:37 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.33-v3.29.1`
- **更新时间**：`2026-10-25 15:29:35 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.33-v3.29.1`
- **更新时间**：`2026-10-25 15:34:55 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.33-v3.29.1`
- **更新时间**：`2026-10-25 20:58:42 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.33-v3.29.1`
- **更新时间**：`2026-10-29 16:07:28 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.33-v3.30.0`
<!-- BUILD_INFO_END -->