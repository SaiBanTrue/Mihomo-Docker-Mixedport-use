# Mihomo-Docker-Mixedport


一个基于 Alpine Linux 的轻量化 Mihomo (Clash Meta) 容器构建方案。支持自动化依赖预处理、多环境变量动态配置以及 GitHub Actions 自动化容器构建。  

---

## 🚀 特性

- **高效流水线构建**：依赖准备与镜像构建解耦，借助本地或 CI/CD 预处理脚本，打包核心文件和分发。  
- **参数动态化注入**：通过容器环境变量覆盖配置，免除手动修改配置文件，运行时即可动态调整网络策略。  
- **多重请求头订阅**：多 User-Agent 轮询订阅与回退，内置失败容错与历史归档，提升订阅更新成功率。  
- **高可用守护进程**：内置防崩溃与轻量级进程守护机制，在定时更新或核心异常退出时无缝自动完成重载。  
- **全平台容器兼容**：规范基础镜像路径声明，消除工具链差异，兼容 Docker 与 Podman 等主流环境。  

---

## 🛠️ 项目结构

```text
├── .github/workflows/
│   └── docker-build.yml   # GitHub Actions 自动化构建工作流
├── app/
│   ├── app_init.sh        # 容器初始化脚本（环境变量与资源目录准备）
│   ├── config_update.sh   # 订阅更新与配置参数修改核心脚本
│   ├── config_loop.sh     # 订阅更新定时循环与重载监控脚本
│   └── entrypoint.sh      # 容器主入口守护脚本
├── Dockerfile             # 容器镜像构建文件
└── pre_build.sh           # 容器构建前置依赖下载脚本
```

---

## 📦 构建与部署

### 1. 本地构建流程

在构建镜像之前，必须先运行预处理脚本以准备二进制程序和数据：  

```bash
# 执行前置脚本（下载 Mihomo 核心、规则数据、Web UI）
bash pre_build.sh

# 使用 Docker 构建镜像
docker build -t mihomo:latest .
```

### 2. 自动化构建 (GitHub Actions)

项目内置 GitHub Actions 工作流。只需将代码推送到 `main` 分支， GitHub Actions 便会自动触发构建并将镜像托管至 GitHub Container Registry (`ghcr.io`)。  

---

## ⚙️ 容器运行

```bash
docker run -d \
  --name mihomo \
  --restart always \
  -p 7890:7890 \
  -p 9090:9090 \
  -v /opt/mihomo/config:/config \
  -e SUB_URL="http://192.168.1.1/sub?token=123456" \
  -e USE_PROXYSCOTCH="false" \
  -e UPDATE_INTERVAL=12 \
  -e MIXED_PORT=7890 \
  -e ALLOW_LAN="true" \
  -e IPV6="false" \
  -e MIHOMO_MODE="rule" \
  -e BIND_ADDRESS="0.0.0.0" \
  -e AUTHENTICATION="username:password123" \
  -e WEBUI_LISTEN_ADDR="0.0.0.0:9090" \
  -e WEBUI_SECRET="secret123456" \
  ghcr.io/SaiBanTrue/mihomo:latest
```

---

## 📌 环境变量说明

所有环境变量均为**可选**参数。  

### 1. 容器运行配置

以下变量用于控制容器的行为（如更新频率、订阅源、WebUI 设置等）。  

| 环境变量 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `SUB_URL` | 无 | 订阅链接地址（例如：`http://192.168.1.1/sub?token=123456`）。 |
| `USE_PROXYSCOTCH` | 无 | 是否使用 Proxyscotch 下载订阅配置（可选：`true`）。 |
| `UPDATE_INTERVAL` | 无 | 订阅配置文件定时更新周期（单位：小时）。 |
| `WEBUI_LISTEN_ADDR`| `0.0.0.0:9090` | Web UI 控制面板的外部监听地址与端口。 |
| `WEBUI_SECRET` | 随机生成 | Web UI 控制面板的访问密钥。默认随机生成（查看日志获取）。 |
| `WEBUI_OVERWRITE` | `true` | 是否在启动时强制覆盖 Web UI 控制面板资源（可选：`true` / `false`）。 |

### 2. 配置文件重写

以下变量会直接修改并应用到 `/config/config.yaml` 配置文件中。  

| 环境变量 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `MIXED_PORT` | 无 | 混合代理端口（例如：`7890`） |
| `ALLOW_LAN` | 无 | 是否允许局域网外部设备访问（可选：`true` / `false`）。 |
| `IPV6` | 无 | 是否开启 IPv6 支持（可选：`true` / `false`）。 |
| `MIHOMO_MODE` | 无 | 运行模式（可选：`rule`, `global`, `direct`）。 |
| `BIND_ADDRESS` | 无 | 局域网监听地址（一般设置为 `"*"` ）。 |
| `AUTHENTICATION` | 无 | 代理身份验证。多账号用逗号分隔（例如：`"user1:pwd1,user2:pwd2"`）。 |
| `SKIP_AUTH_PREFIXES` | 无 | 免身份验证的网段范围。多网段用逗号分隔（例如：`127.0.0.1/8,::1/128`）。 |

---

## 📂 挂载卷说明

`/config`：核心工作目录。容器启动后会自动在此目录下生成配置文件、控制面板（`WEBUI` 子目录）以及更新历史记录（`history` 子目录）。  

```txt
/config
├── config.yaml                 # 当前使用的配置文件
├── WEBUI/                      # Metacubexd 控制面板文件
└── history/                    # 历史配置文件归档目录
    ├── config_*.yaml           # 更新成功前使用的配置文件
    └── config_*_failed_*.yaml  # 下载更新校验失败的配置文件
```

## 📦 Docker 镜像内部结构

本项目的镜像基于超轻量级的 Alpine Linux 构建，并在 GitHub Actions 阶段通过预构建脚本自动拉取上游的最新核心组件和前端面板。

最终推送到 `ghcr.io` 的镜像内部文件系统结构如下：

```text

/
├── app/                             # 核心应用及资源目录（镜像工作目录）
│   ├── entrypoint.sh                # 容器启动入口脚本，负责调度和启动服务
│   ├── app_init.sh                  # 辅助初始化脚本
│   ├── config_update.sh             # 配置文件更新脚本
│   ├── temporaryconfiguration.yaml  # 临时yaml文件
│   ├── mihomo                       # Mihomo 核心二进制文件 (linux/arm64 架构)
│   └── res/                         # 外部依赖资源目录
│       ├── geoip.metadb             # 路由分流数据库 (GeoIP)
│       ├── geosite.dat              # 路由分流数据库 (GeoSite)
│       └── WEBUI/                   # Web 控制面板前端目录 (Zashboard)
│           ├── index.html           # 面板主页
│           ├── assets/              # 面板静态资源 (JS/CSS 等)
│           └── ... 
│
├── config/                          # 持久化数据卷挂载点 (Volume)
│                                    # 用于存放用户的 yaml 配置文件及运行日志
│
├── bin/                             # 预装的必备基础工具
│   ├── bash                         # 用于执行复杂的 shell 脚本逻辑
│   ├── curl                         # 用于网络请求（如下载更新、拉取订阅）
│   ├── yq                           # 用于解析和动态修改 YAML 配置文件
│   └── ... 
│
└── ... (其他 Alpine Linux 基础系统目录)
```

# 📂 运行文件结构

容器启动后，核心程序与数据的读写权限被严格分离。
`/app` 目录作为核心环境保持静默（只读），而所有业务相关的动态文件均在 `/config` 目录中进行（可读写，持久化映射至宿主机）。
```text
/
├── app/                             # 【只读核心区】(随镜像固化，无需用户干预)
│   └── mihomo                       # Mihomo 核心二进制可执行程序本体
│
└── config/                          # 【核心数据舞台】(挂载至宿主机，持久化存放)
    ├── config.yaml                  # 🌟 用户主配置文件，存储节点与核心路由参数
    ├── geoip.metadb                 # IP 路由规则数据库 (每次启动由镜像自动同步更新至此)
    ├── geosite.dat                  # 域名路由规则数据库 (每次启动由镜像自动同步更新至此)
    ├── WEBUI/                       # Web 面板控制台前端目录 (Zashboard)
    └── history/                     # 历史备份配置目录 (保存每次订阅更新被替换下的旧配置)
```

# ⏱️ 构建更新记录

<!-- BUILD_INFO_START -->
- **更新时间**：`2026-10-08 20:40:36 (CST)` &nbsp;|&nbsp; **镜像版本**：`v1.19.32-v3.29.1`
<!-- BUILD_INFO_END -->