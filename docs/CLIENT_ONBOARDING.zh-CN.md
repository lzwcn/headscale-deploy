# Headscale 客户端接入手册

本文档说明如何让 Linux、macOS、Windows 客户端接入你自建的 Headscale。

适用前提：

- Headscale 服务已经可用
- 你的服务地址，例如 `https://<your-headscale-domain>`
- 你已经有一个可用用户，例如 `admin`

## 接入方式

常用有两种方式：

- 预授权密钥接入
  - 最简单
  - 适合个人自用、批量发给自己的设备
- 手动注册接入
  - 先让客户端生成 node key
  - 再由服务端手动批准
  - 适合想保留人工审核的场景

## 方式一：预授权密钥接入

### 1. 在服务端创建 pre-auth key

```bash
bash bin/hsctl key create --user admin
```

会输出一条可直接用于接入的密钥。

注意：

- 这条 key 一般只会在创建时显示
- 建议当场保存
- 默认是可复用且 90 天过期

### 2. 在客户端安装 Tailscale

Linux:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

macOS:

- 安装官方 Tailscale 客户端

Windows:

- 安装官方 Tailscale 客户端

## 3. 客户端执行接入命令

```bash
sudo tailscale up --login-server https://你的域名 --authkey 你的预授权密钥
```

例如：

```bash
sudo tailscale up --login-server "https://<your-headscale-domain>" --authkey <your-preauth-key>
```

如果客户端之前连过官方 Tailscale 或其他 Headscale，建议先执行：

```bash
sudo tailscale logout
```

然后再重新执行 `tailscale up`。

### 4. 服务端确认节点是否已接入

```bash
bash bin/hsctl node list
```

## 方式二：手动注册接入

如果你不想直接发 pre-auth key，可以让客户端先生成 node key，再在服务端批准。

### 1. 客户端执行登录命令

```bash
sudo tailscale up --login-server "https://<your-headscale-domain>"
```

客户端会输出一段需要登录/注册的提示信息，或者生成等待批准的 node key。

### 2. 服务端查看待处理节点

```bash
bash bin/hsctl node list
```

### 3. 手动批准节点

如果你已经拿到了客户端的 node key，可以执行：

```bash
bash bin/hsctl node register --user admin --key <NODE_KEY>
```

注册成功后，客户端就会加入你的 Headscale 网络。

## 常用客户端命令

查看当前状态：

```bash
tailscale status
```

查看本机分配到的 IP：

```bash
tailscale ip
```

断开当前登录：

```bash
sudo tailscale logout
```

重新连接到你的 Headscale：

```bash
sudo tailscale up --login-server "https://<your-headscale-domain>"
```

## Windows 示例

如果已经安装了 Tailscale 客户端，可以在管理员 PowerShell 中执行：

```powershell
tailscale logout
tailscale up --login-server "https://<your-headscale-domain>" --authkey <your-preauth-key>
```

## macOS 示例

如果已经安装 Tailscale，可以在终端执行：

```bash
tailscale logout
tailscale up --login-server "https://<your-headscale-domain>" --authkey <your-preauth-key>
```

## Linux 示例

```bash
sudo tailscale logout
sudo tailscale up --login-server "https://<your-headscale-domain>" --authkey <your-preauth-key>
```

## 如何判断是直连还是中继

查看当前状态：

Windows:

```powershell
.\tailscale.exe status
```

macOS:

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale status
```

Linux:

```bash
tailscale status
```

判断规则：

- 显示 `direct 公网IP:端口`，表示已经直连，打洞成功
- 显示 `relay "hkg"` 或其他 region，表示当前通过 DERP 中继

也可以用 ping 判断：

Windows:

```powershell
.\tailscale.exe ping <peer-ip>
```

macOS:

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale ping <peer-ip>
```

Linux:

```bash
tailscale ping <peer-ip>
```

判断规则：

- 显示 `via 公网IP:端口`，表示直连
- 显示 `via DERP(region)`，表示中继

## 常见问题

### 1. 客户端连接不上

先检查：

- `SERVER_URL` 是否正确
- 域名证书是否正常
- 反向代理是否能正确转发到 Headscale
- 如果启用了 DERP，自用场景下 `3478/udp` 是否已放行

### 2. 提示认证失败

先确认：

- pre-auth key 是否过期
- pre-auth key 是否复制错
- 客户端是否仍保留旧的登录状态

建议先执行：

```bash
sudo tailscale logout
```

再重新接入。

### 3. 节点已经接入，但通信不稳定

检查：

- DERP 是否启用
- 如果你在中国大陆，是否启用了私有 DERP
- 防火墙是否开放 `3478/udp`

## 服务端常用配套命令

创建 pre-auth key：

```bash
bash bin/hsctl key create --user admin
```

列出节点：

```bash
bash bin/hsctl node list
```

列出用户：

```bash
bash bin/hsctl user list
```

查看部署状态：

```bash
bash bin/hsctl status
```
