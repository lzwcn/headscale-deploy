# GitHub 发布建议

本文档整理这个仓库在发布到 GitHub 前后的推荐设置，包括：

- `LICENSE` 建议
- 仓库简介描述
- 推荐 Topics
- 发布前验证建议
- 首个提交信息模板
- 首个 Release Note 模板

## LICENSE 建议

当前仓库已附带：

- [MIT License](../LICENSE)

为什么这里推荐 MIT：

- 对使用者约束最少
- 适合脚本、部署辅助工具、模板类项目
- 便于别人 fork、修改和传播
- 对 GitHub 上的公开小工具项目比较友好

如果你的目标是：

- 鼓励更多人直接复用和二次开发
- 不想增加过多法律约束

那 MIT 是比较稳妥的选择。

如果你以后想更强调专利授权或更明确的贡献规则，再考虑 Apache-2.0 也可以。

## GitHub 仓库简介描述

### 英文版建议

```text
Template-driven Headscale deployment helper for Docker, with interactive install, runtime state management, API key tooling, and optional private/public embedded DERP modes.
```

### 中文版建议

```text
一个基于模板的 Headscale Docker 部署与运维辅助项目，支持交互式安装、运行时状态管理、API Key 管理，以及可切换的私有/公开 Embedded DERP 模式。
```

如果你想写得更短一点，可以用：

```text
Template-driven Headscale deploy helper with install, manage, API key, and DERP support.
```

## GitHub Topics 建议

建议设置这些 Topics：

```text
headscale
tailscale
docker
docker-compose
vpn
self-hosted
networking
derp
shell
bash
```

如果你后面加入了 Traefik 示例，也可以补：

```text
traefik
reverse-proxy
```

## 发布前验证建议

建议把下面两步作为发布前最低验证：

```bash
bash tests/validate-local.sh
```

如果当前机器有可用 Docker 环境，再补一轮：

```bash
sudo -E bash tests/validate-docker.sh
```

这两项分别覆盖：

- shell 语法检查
- 本地配置解析和状态文件安全性检查
- 渲染流程检查
- 真实 Docker 安装、状态、停机、启动、卸载链路

如果你后面接入 GitHub Actions，建议至少让 `tests/validate-local.sh` 和 `shellcheck` 在 PR 阶段自动执行。

## 首个提交信息建议

推荐首个提交信息：

```text
feat: initialize template-driven headscale deploy toolkit
```

如果你想写得更偏“发布仓库”的风格，也可以用：

```text
chore: bootstrap headscale-deploy repository
```

如果你更喜欢中文：

```text
feat: 初始化基于模板的 headscale 部署工具仓库
```

## 首个 Release Tag 建议

如果这是第一次公开发布，建议从：

```text
v0.1.0
```

开始比较合适。

原因：

- 功能已经可用
- 但还处于持续打磨阶段
- 用 `0.x` 更符合“可用但仍在演进”的语义

## 首个 Release Note 模板

可以直接使用下面这个模板。

```md
# headscale-deploy v0.1.0

Initial public release of `headscale-deploy`.

## Highlights

- Template-driven Headscale deployment for Docker
- Interactive and non-interactive install workflows
- Project-local runtime state and generated config management
- Unified CLI for install, manage, upgrade, repair, and uninstall
- Pre-auth key and API key management
- Optional embedded DERP with `disabled`, `private`, and `public` modes
- Chinese client onboarding documentation

## Included Commands

- `install`
- `render`
- `up`
- `down`
- `status`
- `logs`
- `user`
- `node`
- `key`
- `apikey`
- `upgrade`
- `repair`
- `uninstall`

## Notes

- Default image tag follows the current Headscale release configured in the repository
- Runtime files are kept under `runtime/`
- Example config is provided in `templates/install.env.example`

## Documentation

- `README.md`
- `README.zh-CN.md`
- `docs/CLIENT_ONBOARDING.zh-CN.md`
```

## GitHub 发布前建议检查项

发布前建议再确认一次：

- `.gitignore` 已忽略运行时文件
- 文档中没有真实域名、真实 API key、真实 pre-auth key
- `runtime/state.env` 没有被提交
- `runtime/instance/` 没有被提交
- 本地 IDE 文件没有被提交
- `bash tests/validate-local.sh` 已通过
- `sudo -E bash tests/validate-docker.sh` 已通过（如果当前环境可用 Docker）
- README 中的命令可直接运行

## 推荐发布顺序

```bash
git init
git add .
git commit -m "feat: initialize template-driven headscale deploy toolkit"
git tag v0.1.0
```

然后再推送到 GitHub 并填写 Release Note。
