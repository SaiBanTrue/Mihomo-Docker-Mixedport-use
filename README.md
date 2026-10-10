# Mihomo-Docker-Mixedport 介绍


一个基于 Alpine Linux 的轻量化 Mihomo (Clash Meta) 容器构建方案。支持自动化依赖预处理、多环境变量动态配置以及 GitHub Actions 自动化容器构建。  


## 特性

- **高效流水线构建**：依赖准备与镜像构建解耦，借助本地或 CI/CD 预处理脚本，打包核心文件和分发。  
- **参数动态化注入**：通过容器环境变量覆盖配置，免除手动修改配置文件，运行时即可动态调整网络策略。  
- **多重请求头订阅**：多 User-Agent 轮询订阅与回退，内置失败容错与历史归档，提升订阅更新成功率。  
- **高可用守护进程**：内置防崩溃与轻量级进程守护机制，在定时更新或核心异常退出时无缝自动完成重载。  
- **全平台容器兼容**：规范基础镜像路径声明，消除工具链差异，兼容 Docker 与 Podman 等主流环境。  
- **实时追踪与构建**：实现内核与面板的永久自动保鲜。(__新增特性__)


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
  -e SUB_URL="https://da.x3a.com/api/v1/pq/697d62f=26d523,https://kuacaej.117.xyz/f53ea7bc68f1ab362" \
  -e UPDATE_INTERVAL=24 \
  -e MIXED_PORT=7777 \
  -e ALLOW_LAN="true" \
  -e IPV6="false" \
  -e MIHOMO_MODE="rule" \
  -e WEBUI_LISTEN_ADDR="0.0.0.0:9089" \
  ghcr.io/saibantrue/mihomo:latest
```

# 环境变量说明

变量用于控制容器的行为（如更新频率、订阅源、WebUI 设置等）。  
变量会直接修改并应用到 `/config/config.yaml` 配置文件中。 

| 环境变量 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `SUB_URL` | 无 | 机场节点订阅链接。支持单个链接或多链接聚合，多个链接用英文逗号 `,` 分隔（例如：`"URL1,URL2"`）。 |
| `UPDATE_INTERVAL` | `24` | 订阅节点自动更新周期（单位：小时）。例如填 `12`，系统将自动换算为 43200 秒写入配置。 |
| `GEO_UPDATE` | `false` | 路由规则库开关。设为 `true` 时复制内置规则库至 `/config` 并启用自动更新；设为 `false` 时完全排除复制并保持禁用。 |
| `MIXED_PORT` | `7890` | 混合代理端口（同时支持 HTTP 与 SOCKS5 协议，例如：`7777`）。 |
| `MIHOMO_MODE` | `rule` | 核心工作分流模式（可选：`rule` 规则分流、`global` 全局代理、`direct` 全局直连）。 |
| `ALLOW_LAN` | `true` | 是否允许局域网设备连接代理（可选：`true` / `false`）。 |
| `IPV6` | `true` | 是否开启 IPv6 代理支持（可选：`true` / `false`）。 |
| `WEBUI_LISTEN_ADDR` | `0.0.0.0:9090` | Web UI 面板与 RESTful API 的监听地址及端口（例如：`0.0.0.0:9089`）。 |
| `WEBUI_SECRET` | 无 | Web UI 控制面板访问密钥。留空、不传或设置为 `"none"` 均为免密直接访问模式。 |
| `AUTHENTICATION` | 无 | 代理连接身份验证（SOCKS5/HTTP 账密）。支持多账号，逗号分隔（例如：`"user1:pwd1,user2:pwd2"`）。 |
| `SKIP_AUTH_PREFIXES` | 无 | 免身份验证的白名单 IP 网段。支持多网段，逗号分隔（例如：`"127.0.0.1/8,::1/128"`）。 |

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
- **更新时间**：`2026-10-10 15:16:04 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.32-v3.29.1`
- **更新时间**：`2026-10-10 17:58:18 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.32-v3.29.1`
- **更新时间**：`2026-10-10 18:16:07 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.32-v3.29.1`
- **更新时间**：`2026-10-10 18:23:49 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.32-v3.29.1`
- **更新时间**：`2026-10-10 18:26:22 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.32-v3.29.1`
<!-- BUILD_INFO_END -->