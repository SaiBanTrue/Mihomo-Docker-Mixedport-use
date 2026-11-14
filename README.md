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


本指南介绍如何在 Linux 宿主机上通过 **Docker Macvlan** 网络模式部署 `mihomo`（原 Clash Meta），实现独立的局域网 IP 接入。同时，通过挂载独立的 `internal` 内部桥接网络配合 `socat` 端口转发，解决 Macvlan 模式下宿主机与容器之间默认网络隔离的问题，确保宿主机可直接访问 `7890` 代理端口及 `9090`（Zashboard）控制面板。

> **注意事项**：本文档所有命令均默认物理网卡为 `eth0`、局域网网段为 `192.168.6.0/24`。执行前请根据**步骤 1** 的实际查询结果按需替换。

---

## 步骤 1：查看宿主机当前默认物理网卡与网关信息

在配置网络前，需要确认宿主机当前连接局域网的物理网卡名称以及默认网关地址。

```bash
# 查看默认路由信息
ip route show default

# 示例输出：
# default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.100 metric 100
# 请记录其中的物理网卡名称（如 eth0、enp3s0 等）以及网关地址（如 192.168.1.1）
```

---

## 步骤 2：宿主机开启网卡混杂模式与 IP 转发（含持久化）

Macvlan 需要物理网卡开启**混杂模式（Promiscuous Mode）**以接收多个 MAC 地址的数据帧，同时需要开启内核的 **IPv4 / IPv6 转发**功能。通过 NetworkManager 的 `dispatcher.d` 脚本可实现开机或网卡重载时自动生效。

```bash
# 1. 临时立即开启物理网卡混杂模式（请将 eth0 替换为步骤 1 查到的实际网卡名）
sudo ip link set eth0 promisc on

# 2. 清理可能存在的旧版持久化脚本
sudo rm -f /etc/NetworkManager/dispatcher.d/99-eth0-promisc.sh

# 3. 写入 NetworkManager 网络事件触发脚本，实现混杂模式与内核转发持久化
sudo tee /etc/NetworkManager/dispatcher.d/99-mihomo-network.sh << 'EOF'
#!/bin/bash

INTERFACE="$1"
ACTION="$2"

# 当指定物理网卡启动或 IPv6 DHCP 状态变化时自动应用以下网络参数
if [ "$INTERFACE" = "eth0" ] && { [ "$ACTION" = "up" ] \vert{}\vert{} [ "$ACTION" = "dhcp6-change" ]; }; then
    # 开启物理网卡混杂模式
    ip link set eth0 promisc on
    
    # 开启 IPv4 路由转发
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w net.ipv4.conf.all.forwarding=1
    sysctl -w net.ipv4.conf.default.forwarding=1
    sysctl -w net.ipv4.conf.eth0.forwarding=1

    # 开启 IPv6 路由转发，并将 accept_ra 设为 2（确保开启转发后依然接收路由通告以获取 IPv6 地址）
    sysctl -w net.ipv6.conf.all.forwarding=1
    sysctl -w net.ipv6.conf.default.forwarding=1
    sysctl -w net.ipv6.conf.eth0.forwarding=1
    sysctl -w net.ipv6.conf.all.accept_ra=2
    sysctl -w net.ipv6.conf.default.accept_ra=2
    sysctl -w net.ipv6.conf.eth0.accept_ra=2
fi
EOF

# 4. 赋予脚本可执行权限
sudo chmod 755 /etc/NetworkManager/dispatcher.d/99-mihomo-network.sh
```

---

## 步骤 3：重启后验证混杂模式与转发持久化

建议执行 `sudo reboot` 重启宿主机，随后运行以下命令验证持久化配置是否正常生效。

```bash
# 1. 检查网卡状态标志
# 输出结果第一行的尖括号中必须包含 PROMISC 标志
ip link show eth0

# 2. 检查内核 IPv4 / IPv6 转发及 RA 参数
sysctl net.ipv4.ip_forward \
       net.ipv6.conf.all.forwarding \
       net.ipv6.conf.default.forwarding \
       net.ipv6.conf.all.accept_ra \
       net.ipv6.conf.eth0.accept_ra

# 预期输出结果应与脚本配置完全一致：
# net.ipv4.ip_forward = 1
# net.ipv6.conf.all.forwarding = 1
# net.ipv6.conf.default.forwarding = 1
# net.ipv6.conf.all.accept_ra = 2
# net.ipv6.conf.eth0.accept_ra = 2
```

---

## 步骤 4：创建 Docker Macvlan 网络

清理可能残留的同名网络，并基于宿主机物理网卡创建 `macvlan` 网络。此处不限制 `--ip-range`，方便后续为容器自由指定局域网内的静态 IP。

```bash
# 1. 如果之前已经建过同名网络，先删除
docker network rm mihomo-macvlan 2>/dev/null || true

# 2. 创建 Macvlan 网络（请确保 subnet、gateway 和 parent 网卡与你的局域网环境一致）
docker network create -d macvlan \
  --subnet=192.168.6.0/24 \
  --gateway=192.168.6.1 \
  -o parent=eth0 \
  mihomo-macvlan

# 3. 验证网络是否创建成功
docker network ls | grep mihomo-macvlan
```

---

## 步骤 5：部署并启动 Mihomo 容器

使用自定义配置（`USE_CUSTOM_CONFIG="true"`）并挂载 `/dev/net/tun` 设备以支持 TUN 模式，同时为容器分配独立的局域网固定 IP（示例为 `192.168.6.250`）。

```bash
# 启动 mihomo-core 容器
docker run -d \
  --name mihomo-core \
  --restart always \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  --network mihomo-macvlan \
  --ip 192.168.6.250 \
  --device /dev/net/tun \
  -v /mnt/docker/mihomoconfig:/config \
  -e TZ=Asia/Shanghai \
  ghcr.io/saibantrue/mihomo:latest
```

---

## 步骤 6：打通宿主机与容器通信（Zashboard 管理与 7890 代理访问）

由于 Linux 内核安全机制，宿主机无法直接访问挂载在自身网卡上的 Macvlan 子接口 IP。通过为容器额外挂载一个固定子网的 `internal` 内部网络，即可建立宿主机与容器的直连通道。

### 6.1 为容器绑定固定 IP 的内部网络

```bash
# 1. 断开容器可能连接的旧内部网络
docker network disconnect mihomo-bridge-internal mihomo-core 2>/dev/null || true

# 2. 删除没有固定子网的旧网络
docker network rm mihomo-bridge-internal 2>/dev/null || true

# 3. 重新创建内部隔离网络，并明确指定子网为 172.18.0.0/24
docker network create --internal --subnet=172.18.0.0/24 mihomo-bridge-internal

# 4. 将内部网络附加到 mihomo-core 容器，并固定分配 IP 为 172.18.0.2
docker network connect --ip 172.18.0.2 mihomo-bridge-internal mihomo-core

# 5. 重启容器使双网卡路由生效
docker restart mihomo-core
```

### 6.2 验证容器内双网卡路由表

检查容器默认路由是否依然走 Macvlan 网关（`192.168.6.1`），避免内网接口抢占默认出口。

```bash
# 查看容器内部路由表
docker exec -it mihomo-core ip route show

# 预期输出：
# default via 192.168.6.1 dev eth0
# 172.18.0.0/24 dev eth1 scope link  src 172.18.0.2
# 192.168.6.0/24 dev eth0 scope link  src 192.168.6.250
# 198.18.0.0/30 dev Meta scope link  src 198.18.0.0
```

### 6.3 按需启动 Socat 端口转发（将容器端口映射至宿主机本地）

需要通过宿主机 `127.0.0.1` 或宿主机局域网 IP 访问 Zashboard（`9090`）及代理端口（`7890`）时，手动运行此转发容器：

```bash
# 清理旧的转发容器（如有）
docker rm -f mihomo-socat 2>/dev/null || true

# 启动临时 socat 转发容器（--restart no 表示按需手动运行，不随开机自启）
docker run -d \
  --name mihomo-socat \
  --restart no \
  --network host \
  --entrypoint /bin/sh \
  alpine/socat \
  -c "socat tcp-listen:9090,fork,reuseaddr tcp-connect:172.18.0.2:9090 & socat tcp-listen:7890,fork,reuseaddr tcp-connect:172.18.0.2:7890"
```

---

## 步骤 7：代理连通性与延迟稳定性测试

在容器内（或已运行 `mihomo-socat` 的宿主机上）循环请求目标地址，验证代理链路是否畅通及延迟表现。

```bash
# 循环测试 100 次通过本地 7890 端口访问外部网络的 HTTP 状态码与耗时
for i in $(seq 1 100); do
  curl -x [http://127.0.0.1:7890](http://127.0.0.1:7890) -o /dev/null -s -w "序号 $i: HTTP状态 %{http_code} | 延迟: %{time_total} 秒\n" [https://www.google.com](https://www.google.com)
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
- **更新时间**：`2026-10-25 15:29:35 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.33-v3.29.1`
- **更新时间**：`2026-10-25 15:34:55 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.33-v3.29.1`
- **更新时间**：`2026-10-25 20:58:42 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.33-v3.29.1`
- **更新时间**：`2026-10-29 16:07:28 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.33-v3.30.0`
- **更新时间**：`2026-11-11 16:55:47 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.34-v3.30.0`
<!-- BUILD_INFO_END -->