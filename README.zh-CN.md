# headscale-deploy

[English](README.md) | 简体中文

一个基于模板的 Headscale Docker 部署辅助项目。

这个仓库主要面向两类使用场景：

- 想要更清晰地安装、升级和管理 Headscale 的自建用户
- 希望把整个目录直接上传到服务器即可使用的人

项目将模板、运行时文件和 shell 逻辑分离，方便维护和二次扩展。

## 项目作用

- 使用官方 Headscale 容器镜像进行部署
- 从外部模板渲染 `config.yaml` 和 `compose.yaml`
- 同时支持交互式安装和非交互式安装
- 将运行时状态保存在项目目录内
- 通过统一入口完成安装、管理、升级、修复和卸载
- 支持可切换的嵌入式 DERP 模式：
  - `disabled`
  - `private`
  - `public`

## 目录结构

```text
headscale-deploy/
├─ bin/
│  └─ hsctl
├─ lib/
│  ├─ common.sh
│  ├─ state.sh
│  ├─ validate.sh
│  ├─ render.sh
│  ├─ install.sh
│  ├─ manage.sh
│  ├─ upgrade.sh
│  ├─ repair.sh
│  └─ legacy.sh
├─ templates/
│  ├─ config.yaml.tpl
│  ├─ compose.host.yaml.tpl
│  ├─ compose.network.yaml.tpl
│  ├─ compose.portmap.yaml.tpl
│  └─ install.env.example
├─ tests/
│  ├─ validate-local.sh
│  └─ validate-docker.sh
├─ runtime/
│  └─ instance/
└─ headscale-install.sh
```

## 运行要求

- Linux
- `bash`
- Docker Engine
- Docker Compose v2 插件
- 安装、升级、修复、卸载时需要 root 权限

这个项目不会自动帮你安装 Docker。

## 已验证环境

- 已按 `ghcr.io/juanfont/headscale:0.28.0` 做过本地验证
- 本地安全性和渲染检查可通过 `bash tests/validate-local.sh` 运行
- 真实 Docker 生命周期验证可通过 `sudo -E bash tests/validate-docker.sh` 运行
- 当前设计目标是一个仓库工作目录只管理一个活动实例

## 快速开始

### 1. 复制示例配置

```bash
cp templates/install.env.example runtime/install.env
```

### 2. 修改部署参数

至少需要检查这些配置：

- `HS_ROOT`
- `SERVER_URL`
- `DOCKER_MODE`
- `HS_DOCKER_NETWORK`（仅 `DOCKER_MODE=network` 时）
- `HEADSCALE_TAG`
- `DERP_MODE`
- `DNS_GLOBAL_NAMESERVERS`（可选）

`runtime/install.env` 使用简单的 `KEY=value` 语法，可选单引号或双引号。配置值只按数据解析，不会按 shell 代码执行。如果值里包含空格，需要加引号。

### 3. 先渲染配置文件

```bash
bash bin/hsctl render --auto --config runtime/install.env
```

会生成：

- `runtime/instance/config/config.yaml`
- `runtime/instance/compose.yaml`

### 4. 执行安装

```bash
bash bin/hsctl install --auto --config runtime/install.env
```

## 验证方式

发布前建议至少执行：

```bash
bash tests/validate-local.sh
```

如果手头有可用的 Docker Linux 主机，再执行：

```bash
sudo -E bash tests/validate-docker.sh
```

Docker 验证脚本会把状态文件和安装目录隔离到 `/tmp` 下，不会动默认的 `runtime/` 实例。

## 命令说明

```bash
bash bin/hsctl install [--auto] [--config FILE]
bash bin/hsctl render [--auto] [--config FILE]
bash bin/hsctl up
bash bin/hsctl down
bash bin/hsctl status
bash bin/hsctl logs

bash bin/hsctl user add NAME
bash bin/hsctl user delete NAME
bash bin/hsctl user list

bash bin/hsctl node list [--user NAME]
bash bin/hsctl node register --user NAME --key NODEKEY
bash bin/hsctl node delete ID

bash bin/hsctl key create --user NAME
bash bin/hsctl key list

bash bin/hsctl apikey create [--expiration DURATION]
bash bin/hsctl apikey list
bash bin/hsctl apikey expire --prefix PREFIX

bash bin/hsctl upgrade [--image-tag TAG] [--no-backup]
bash bin/hsctl repair db
bash bin/hsctl uninstall [-y]
bash bin/hsctl paths
bash bin/hsctl legacy [old flat flags]
```

## 安装模式

### 交互式

```bash
bash bin/hsctl install
```

适合第一次手动部署。

### 非交互式

```bash
bash bin/hsctl install --auto --config runtime/install.env
```

适合重复部署和自动化。

常用安装参数还包括 `--listenaddr`、`--docker-mode`、`--docker-network`、`--container-name`、`--derp-stun-addr`。
如果想查看当前受管实例的路径，可以执行 `bash bin/hsctl paths`。

## Docker 模式

### `DOCKER_MODE=network`

适合 Headscale 放在 Traefik 之类反向代理后面。

行为：

- Headscale 自身不直接暴露宿主机 TCP 端口
- 容器会加入一个外部 Docker 网络
- 反向代理需要把 HTTPS 请求转发到 `headscale` 容器
- 如果启用嵌入式 DERP，Compose 还会额外发布 `3478/udp`

注意：

- 这种模式下 `3478/udp` 仍然经过 Docker 网络层
- 如果你需要 Embedded DERP 的 IPv6/STUN，`DOCKER_MODE=network` 不是首选

### `DOCKER_MODE=portmap`

适合直接从宿主机暴露服务。

行为：

- 发布 `${PORT}:8080`
- 如果启用嵌入式 DERP，还会额外发布 `${DERP_STUN_PORT}/udp`

注意：

- `3478/udp` 同样经过 Docker 端口发布
- 如果客户端需要 Embedded DERP 的 IPv6，优先改用 `DOCKER_MODE=host`

### `DOCKER_MODE=host`

适合需要 Embedded DERP IPv6/STUN 稳定性的场景。

行为：

- Compose 不再使用 `ports`
- Compose 不再加入外部 Docker 网络
- 容器直接使用宿主机网络栈
- Headscale 直接绑定宿主机 `LISTEN_ADDR:8080`
- Embedded DERP 的 `3478/udp` 不再经过 Docker 端口发布

监听地址语义：

- `LISTEN_ADDR=0.0.0.0` 表示保留 IPv4 监听
- `LISTEN_ADDR=::` 会渲染成 `[::]:8080`，更适合作为双栈友好的宿主监听写法
- `DERP_STUN_LISTEN_ADDR=:3478` 仍是推荐默认值
- `DERP_STUN_LISTEN_ADDR=[::]:3478` 适合你需要显式表达 IPv6 wildcard 监听时使用

适用建议：

- 如果你启用了 Embedded DERP，并且希望 `tailscale netcheck` 能稳定得到 `IPv6: yes`
- 如果你已经确认 `443/TCP` 正常，但 `3478/udp` 的 IPv6 STUN 仍异常

## Embedded DERP IPv6 说明

请特别注意以下几点：

- `443/TCP` 正常不代表 Embedded DERP 的 STUN 正常
- `tailscale netcheck` 才是最直接的客户端检查方式
- 如果要做 Embedded DERP 的 IPv6，优先使用 `DOCKER_MODE=host`
- `DERP_STUN_LISTEN_ADDR` 推荐使用 `:3478`
- 建议显式填写 `DERP_IPV4` 和 `DERP_IPV6`

## DERP 模式

### `DERP_MODE=disabled`

默认值，也是最安全的模式。

- 不启用嵌入式 DERP
- 客户端继续使用默认 DERP 地图

### `DERP_MODE=private`

推荐用于个人自用或团队内部。

- 启用嵌入式 DERP
- 渲染为 `verify_clients: true`
- 只有你自己的 Headscale 环境中的有效客户端才应当被允许使用
- 相比公开模式，滥用风险明显更低

如果你的目标是在中国大陆放一个更近的 DERP 节点给自己的 tailnet 使用，这个模式最合适。

### `DERP_MODE=public`

只在你明确打算提供公共中继服务时使用。

- 启用嵌入式 DERP
- 渲染为 `verify_clients: false`
- 未知客户端不会在 DERP 校验阶段被拒绝
- 会产生真实的带宽暴露风险

需要注意：

- 仅仅设置为 `public`，并不会自动让全网都使用你的 DERP
- 客户端仍然需要拿到包含你 region 的 DERP map
- 但一旦你公开 region 且关闭校验，流量损耗风险就存在了

## DERP 风险控制

如果你是自用部署，关键配置是：

```text
DERP_MODE=private
```

这样可以得到：

- 启用嵌入式 DERP
- 打开客户端校验
- 自己的用户可以受益
- 降低被外部随机用户滥用的风险

如果你以后想切换到公益或公开模式，只需要改成：

```text
DERP_MODE=public
```

然后再有意识地把你的 DERP region 发布给目标客户端。

可以简单理解为：

- `private` = 自用优先
- `public` = 公益/开放中继

## 中国大陆部署建议

如果你的服务器位于中国大陆，比较实用的起始配置是：

```bash
DOCKER_MODE=host
SERVER_URL="https://<your-headscale-domain>"
DERP_MODE=private
DERP_IPV4=你的公网 IPv4
DERP_IPV6=你的公网 IPv6
DERP_STUN_LISTEN_ADDR=:3478
DERP_INCLUDE_DEFAULTS=true
DNS_GLOBAL_NAMESERVERS=223.5.5.5,223.6.6.6,119.29.29.29,2400:3200::1,2400:3200:baba::1,1.1.1.1,2606:4700:4700::1111
```

同时确认：

- 域名解析正确
- HTTPS 反向代理已经正常工作
- 防火墙或安全组已经放行 `3478/udp`
- 反代能够把 HTTPS 请求转发给宿主机上的 `127.0.0.1:8080` 或对应监听地址

这样配置的好处：

- 自己的用户可以优先使用更近的 DERP
- 默认 DERP 仍然保留为回退路径
- 不会一开始就进入公开带宽池模式

## 非交互式安装示例

```bash
bash bin/hsctl install --auto \
  --config runtime/install.env \
  --docker-mode host \
  --serverurl "https://<your-headscale-domain>" \
  --derp-mode private \
  --derp-ipv4 203.0.113.10 \
  --derp-ipv6 2001:db8::10
```

## 部署后建议自检

服务端建议至少执行：

```bash
bash bin/hsctl status
docker compose -f runtime/instance/compose.yaml logs --tail=100 headscale
ss -lunp | grep 3478
```

客户端建议执行：

```bash
tailscale netcheck
```

如果启用了 Embedded DERP 且希望检查 IPv6 STUN，还可以在服务端抓包：

```bash
tcpdump -ni any udp port 3478
```

判断思路：

- 如果 `tailscale netcheck` 显示 `IPv6: yes`，说明 DERP/STUN 的 IPv6 路径已经正常
- 如果显示 `IPv6: no, but OS has support`，优先检查 Docker 网络方式、`DERP_IPV6`、`DERP_STUN_LISTEN_ADDR` 和 `3478/udp`

## 兼容旧脚本

旧的平铺参数接口仍然可用：

```bash
bash headscale-install.sh --listusers
bash headscale-install.sh --upgrade --image-tag 0.28.0
```

现在它内部会转发到 `bin/hsctl` 的兼容层。
新的部署和自动化场景优先使用 `bash bin/hsctl ...`；`headscale-install.sh` 和 `hsctl legacy` 仅建议保留给旧调用链兼容使用。

## 说明

- 运行时状态保存在 `runtime/state.env`
- 渲染后的文件在 `runtime/instance/` 下
- 安装流程会在服务成功启动后再写入状态文件
- 配置渲染基于模板，后续扩展更多选项会更容易
- 一个仓库工作目录当前只管理一个活动实例
- 安装输出里会打印初始 pre-auth key，应该按敏感信息处理

## 附加文档

- [客户端接入手册](docs/CLIENT_ONBOARDING.zh-CN.md)

## 后续规划

- 增加 policy 文件模板支持
- 增加 PostgreSQL 模板支持
- 增加更清晰的反向代理示例
- 增加更完整的 DERP 公益部署说明
