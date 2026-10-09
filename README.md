# Mihomo-Docker-Mixedport 介绍


一个基于 Alpine Linux 的轻量化 Mihomo (Clash Meta) 容器构建方案。支持自动化依赖预处理、多环境变量动态配置以及 GitHub Actions 自动化容器构建。  


## 特性

- **高效流水线构建**：依赖准备与镜像构建解耦，借助本地或 CI/CD 预处理脚本，打包核心文件和分发。  
- **参数动态化注入**：通过容器环境变量覆盖配置，免除手动修改配置文件，运行时即可动态调整网络策略。  
- **多重请求头订阅**：多 User-Agent 轮询订阅与回退，内置失败容错与历史归档，提升订阅更新成功率。  
- **高可用守护进程**：内置防崩溃与轻量级进程守护机制，在定时更新或核心异常退出时无缝自动完成重载。  
- **全平台容器兼容**：规范基础镜像路径声明，消除工具链差异，兼容 Docker 与 Podman 等主流环境。  
- **自动化实时追踪与构建机制**：实现内核与面板的永久自动保鲜(__新增特性__)。


## 致谢与参考

本项目基于以下等开源项目：
- [Dancying/Mihomo-Docker-Build](https://github.com/Dancying/Mihomo-Docker-Build)
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
- [Zephyruso/zashboard](https://github.com/Zephyruso/zashboard)


# 容器运行

```bash
docker run -d \
  --name mihomo \
  --restart always \
  --network host \
  -v /opt/mihomo/config:/config \
  -e SUB_URL="https://dash.xn--cp3a08l.com/api/v1/pq/697d62f66d7b523,https://kuacdejfhaej.317.xyz/f53eac68f1ab362" \
  -e UPDATE_INTERVAL=12 \
  -e MIXED_PORT=7777 \
  -e ALLOW_LAN="true" \
  -e IPV6="false" \
  -e MIHOMO_MODE="rule" \
  -e AUTHENTICATION="user1:pwd1,user2:pwd2" \
  -e SKIP_AUTH_PREFIXES = 127.0.0.1/8,::1/128 \
  -e WEBUI_LISTEN_ADDR="0.0.0.0:9089" \
  -e WEBUI_SECRET=none \
  ghcr.io/saibantrue/mihomo:latest
```

# 环境变量说明

所有环境变量均为**可选**参数。  

## 1. 容器运行配置

以下变量用于控制容器的行为（如更新频率、订阅源、WebUI 设置等）。  

| 环境变量 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `SUB_URL` | 无 | 订阅链接地址（例如：`http://192.168.1.1/sub?token=123456`）。 |
| `UPDATE_INTERVAL` | 无 | 订阅配置文件定时更新周期（单位：小时）。 |
| `WEBUI_LISTEN_ADDR`| `0.0.0.0:9089` | Web UI 控制面板的外部监听地址与端口。 |
| `WEBUI_SECRET` | Web UI 控制面板的访问密钥。默认随机生成（查看日志获取）。 |

## 2. 配置文件覆写

以下变量会直接修改并应用到 `/config/config.yaml` 配置文件中。  

| 环境变量 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `MIXED_PORT` | 无 | 混合代理端口（例如：`7890`） |
| `ALLOW_LAN` | 无 | 是否允许局域网外部设备访问（可选：`true` / `false`）。 |
| `IPV6` | 无 | 是否开启 IPv6 支持（可选：`true` / `false`）。 |
| `MIHOMO_MODE` | 无 | 运行模式（可选：`rule`, `global`, `direct`）。 |
| `AUTHENTICATION` | 无 | 代理身份验证。多账号用逗号分隔（例如：`"user1:pwd1,user2:pwd2"`）。 |
| `SKIP_AUTH_PREFIXES` | 无 | 免身份验证的网段范围。多网段用逗号分隔（例如：`127.0.0.1/8,::1/128`）。 |


# 文件结构

## Git 原始项目文件结构（源码库）

```text
Mihomo-Docker-Mixedport/
├── .github/
│   └── workflows/
│       └── docker-build.yml        # GitHub Actions 自动化构建与推送工作流
├── app/
│   ├── entrypoint.sh               # 容器主进程守护与拉起脚本
│   ├── mihomo_init.sh              # 容器环境初始化、资源挂载同步脚本
│   ├── config_update.sh            # 订阅注入、环境变量动态替换核心脚本
│   └── template_config.yaml        # yaml配置模板（永远保留 PROVIDERS_PLACEHOLDER 占位符）
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
│   ├── config_update.sh
│   ├── template_config.yaml
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
│   ├── config_update.sh            # 配置更新脚本
│   ├── template_config.yaml        # 内置的纯净配置模板底座
│   └── res/                        # 随镜像打包的原始静态资产仓库
│       ├── geoip.metadb            # IP 分流规则库原始副本
│       ├── geosite.dat             # 域名分流规则库原始副本
│       └── WEBUI/                  # Zashboard 前端面板原始副本
│           └── ...
├── config/                         # 📁【数据卷挂载点】 (VOLUME 声明，VOLUME [ "/config" ] )
├── bin/                            # Alpine 基础命令工具箱 (bash, curl, tzdata, sed, awk)
├── etc/                            # 系统配置 (含 /etc/localtime 时区 Shanghai)
└── ...                             # (其他标准 Linux 根系统目录: /lib, /usr, /proc, /sys 等)
```


## 容器启动后（config_update.sh 运行后的文件变化）

```text
/config/  or  /opt/mihomo/config/   #  -v /opt/mihomo/config:/config \
├── config.yaml                     # 🌟 用户当前生效的主配置（包含注入的订阅和端口参数）
├── geoip.metadb                    # 路由 IP 分流数据库
├── geosite.dat                     # 路由域名分流数据库
└── WEBUI/                          # Zashboard 网页控制台资源（浏览器直接访问此目录）
    ├── index.html
    └── assets/
```


# 构建更新记录

<!-- BUILD_INFO_START -->
- **更新时间**：`2026-10-09 18:05:43 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.32-v3.29.1`
- **更新时间**：`2026-10-09 18:11:27 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.32-v3.29.1`
- **更新时间**：`2026-10-09 18:13:37 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.32-v3.29.1`
- **更新时间**：`2026-10-09 19:05:33 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.32-v3.29.1`
- **更新时间**：`2026-10-09 19:08:12 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.32-v3.29.1`
<!-- BUILD_INFO_END -->