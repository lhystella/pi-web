# 使用 Cloudflare 安全访问 pi-web

目标地址：<https://pi.example.com>

本方案使用 **Cloudflare Access + Cloudflare Tunnel**：Access 在所有页面、API
和 SSE 连接前检查登录，Tunnel 从本机主动连接 Cloudflare，不需要公网 IP，
也不需要在路由器开放端口。

```text
iPhone / 其他电脑
        │ HTTPS
        ▼
pi.example.com
        │
Cloudflare Access（仅允许指定邮箱）
        │
Cloudflare Tunnel
        │
cloudflared ── http://pi-web:30141
        │
本机 Docker
```

> pi-web 不只是静态前端。登录后的用户可以驱动 agent、执行工具并编辑挂载的
> 文件，所以不要只隐藏网页，也不要直接把 `30141` 暴露到公网。Cloudflare
> Access 必须覆盖整个 hostname。

## 0. 准备工作

- `example.com` 的注册商账号和 DNS 修改权限。
- 一个 Cloudflare 账号，建议先为它开启 MFA。
- 安装并启动 Docker Desktop；如果 macOS 提示共享 `/Volumes/Life`，请允许该目录，
  并确保外接磁盘始终挂载在相同路径。
- 准备一个只允许登录的邮箱；最简单的方式是邮箱一次性验证码。
- 运行 pi-web 的 Mac 必须保持开机、联网且 Docker Desktop 正在运行。

不要把 Cloudflare Tunnel token 发到聊天、截图或提交到 Git。

## 1. 将域名接入 Cloudflare

如果 Cloudflare 控制台已经显示 `example.com` 为 **Active**，直接跳到
下一节。

1. 登录 <https://dash.cloudflare.com>。
2. 点击 **Add a domain / Add a site**。
3. 输入 `example.com`，选择适合个人使用的计划。
4. Cloudflare 会扫描已有 DNS 记录。域名若还承担网站或邮箱用途，请仔细确认
   原有的 `A`、`CNAME`、`MX` 和 `TXT` 记录均已导入，不要删除它们。
5. Cloudflare 会给出两条 nameserver。在域名注册商后台，把原 nameserver
   替换成这两条。
6. 等 Cloudflare 状态变为 **Active**。

如果注册商此前启用了 DNSSEC，应按照 Cloudflare 的迁移提示处理旧 DS 记录，
否则 nameserver 切换后可能出现 DNS 解析失败。

此方案不需要给家庭公网 IP 添加 `A` 记录，也不需要端口转发。

## 2. 配置登录方式

1. 在 Cloudflare 控制台进入 **Zero Trust**。首次进入时需要创建一个 team name。
2. 打开 **Settings → Authentication → Login methods**。
3. 最简单的方式是启用 **One-time PIN**。登录时 Cloudflare 会向邮箱发送验证码。
4. 如果希望用 Google 或 GitHub 登录，也可以在这里增加对应 Identity Provider；
   请为该账号启用 MFA。

建议先用 One-time PIN 完成部署，确认正常后再增加其他登录方式。

## 3. 先创建 Access 应用和白名单

应当先完成 Access 策略，再创建公开 hostname，避免域名短暂处于无保护状态。
Cloudflare 菜单名称可能随控制台版本略有变化。

1. 进入 **Zero Trust → Access → Applications**。
2. 点击 **Add an application**，选择 **Self-hosted**。
3. 填写：
   - Application name：`pi-web`
   - Session duration：建议 `24 hours`；个人设备也可以选择 `7 days`
   - Application domain：`pi.example.com`
   - Path：留空，以保护整个 hostname
4. 创建一条策略：
   - Policy name：`Only me`
   - Action：`Allow`
   - Include selector：`Emails`
   - Value：填写你自己的完整邮箱地址
5. 保存应用。

检查策略时确保：

- 没有 `Everyone` 允许规则。
- 没有绕过整个 hostname 的 `Bypass` 规则。
- 不需要额外的 `Block everyone`；未匹配 Allow 策略的用户默认会被拒绝。
- 如果允许多个账号，应逐个添加准确邮箱，而不是允许整个公共邮箱域名。

Cloudflare 显示的是外部登录页，这是有意设计：它会同时保护 UI、
`/api/*` 和事件流，而不是只保护一个前端页面。

## 4. 创建 Tunnel

1. 进入 **Zero Trust → Networks → Tunnels**。部分新版控制台显示为
   **Networks → Connectors → Cloudflare Tunnels**。
2. 点击 **Create a tunnel**。
3. Connector 选择 **Cloudflared**。
4. Tunnel name 填写 `pi-web-home`。
5. 环境选择 **Docker**。Cloudflare 会显示类似下面的命令：

   ```text
   docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token <TOKEN>
   ```

6. 复制 `--token` 后的 token，保留这个页面，暂时不要把 token 放入任何 Git 文件。
   这是 Tunnel connector token，不是 **My Profile → API Tokens** 中创建的 API token。

## 5. 在本机保存 Tunnel token

在项目目录执行：

```bash
cp .env.example .env
chmod 600 .env
```

编辑 `.env`：

```dotenv
CLOUDFLARE_TUNNEL_TOKEN=粘贴第4步生成的完整token
```

`.env` 已被 `.gitignore` 和 `.dockerignore` 排除。不要把真实 token 写入
`.env.example`、Compose 文件或文档。

## 6. 启动 pi-web 和 Tunnel

必须同时加载基础 Compose 文件和 Cloudflare override：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.cloudflare.yml \
  up -d --build
```

查看状态：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.cloudflare.yml \
  ps
```

查看 Tunnel 日志：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.cloudflare.yml \
  logs -f cloudflared
```

正常情况下日志会出现 `Registered tunnel connection`。按 `Ctrl-C` 只会退出
日志查看，不会停止容器。

基础 Compose 把主机端口限制为 `127.0.0.1:30141`：

- 本机仍可访问 <http://localhost:30141>。
- 局域网和公网不能直接访问 `30141`。
- 远程请求只能通过 Cloudflare Tunnel 进入。

返回 Tunnel 创建页面。连接器应在一分钟左右变成 **Healthy / Connected**；
确认在线后再继续配置公开 hostname。

## 7. 添加 Public Hostname

在 `pi-web-home` Tunnel 的 **Public Hostnames / Routes** 页面添加：

- Subdomain：`pi`
- Domain：`example.com`
- Path：留空
- Service type：`HTTP`
- URL：`pi-web:30141`

这里必须使用 `http://pi-web:30141`，不能使用 `localhost:30141`。
`cloudflared` 运行在另一个容器中，`pi-web` 是 Docker 网络中的服务名。

保存后 Cloudflare 会自动创建代理 DNS 记录。如果提示 hostname 已存在，进入
**DNS → Records**，检查并移除冲突的 `pi` 记录后重试；不要误删根域名、邮箱或
其他子域名的记录。

## 8. 验证登录保护

按以下顺序检查：

1. 本机打开 <http://localhost:30141>，确认 pi-web 正常。
2. 使用无痕窗口打开 <https://pi.example.com>。
3. 未登录时必须先出现 Cloudflare Access 登录页。
4. 使用白名单邮箱接收验证码并登录。
5. 使用一个不在白名单中的邮箱测试，应当被拒绝。
6. 在未登录的无痕窗口直接打开
   <https://pi.example.com/api/sessions>，也必须跳转登录或返回拒绝，
   不能看到 JSON 数据。
7. 登录后发送一条测试消息，确认流式回复和工具事件能够正常显示。

也可以在终端检查未登录响应：

```bash
curl -I https://pi.example.com
curl -I https://pi.example.com/api/sessions
```

通常会看到重定向到 Cloudflare Access，而不是直接返回应用内容。

## 9. 安装到 iPhone 或 iPad 主屏幕

部署包含 PWA Manifest 的新版本后：

1. 必须先用 **Safari** 打开 <https://pi.example.com>。
2. 输入白名单邮箱，完成验证码或 Identity Provider 登录。
3. 点击 Safari 的 **分享** 按钮。
4. 选择 **添加到主屏幕**；如果系统显示 **Open as Web App / 作为网页 App
   打开**，保持开启。
5. 名称保留为 `Pi Agent`，点击 **添加**。
6. 从主屏幕图标启动。应用会使用独立窗口，不显示 Safari 地址栏。

如果之前已经添加过旧图标，请先从主屏幕删除，再重新添加，以刷新 Manifest、
图标和独立窗口设置。独立 App 第一次启动时可能要求再次完成 Cloudflare Access
登录；Access session 到期后也需要重新登录，这是正常行为。

iOS 不允许网页按钮直接弹出系统安装界面，因此仍需手动使用“分享 → 添加到主
屏幕”。本项目没有缓存会话、API 或 Agent 事件，也不提供离线运行；Mac、Docker
和 Tunnel 必须在线。

如果 iOS 反复跳回登录页，先关闭内容拦截器，允许 Cookie，并确认系统时间为
自动设置，然后重新使用 Safari 登录。

## 日常维护

### 更新并重新启动

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.cloudflare.yml \
  pull cloudflared

docker compose \
  -f docker-compose.yml \
  -f docker-compose.cloudflare.yml \
  up -d --build
```

### 停止服务

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.cloudflare.yml \
  down
```

### 修改允许登录的邮箱

进入 **Zero Trust → Access → Applications → pi-web**，编辑 `Only me` 策略。
删除一个邮箱后，该账号不能创建新的 Access session；如控制台提供
**Revoke tokens/sessions**，同时撤销已有 session，或者缩短 session duration。

### Tunnel token 泄露或需要轮换

在 Cloudflare Tunnel 页面生成/轮换 connector token，替换本机 `.env` 中的值，
然后重新创建 cloudflared 容器：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.cloudflare.yml \
  up -d --force-recreate cloudflared
```

## 故障排查

### Cloudflare Error 1033

Tunnel 没有在线。检查：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.cloudflare.yml \
  logs --tail=100 cloudflared
```

常见原因是 token 错误、Docker 未启动、Mac 休眠或网络断开。

### 登录后出现 502 Bad Gateway

Cloudflare 已连接，但无法访问 pi-web。确认：

- 两个 Compose 文件是通过同一条命令一起启动的。
- `pi-web` 容器状态为 running。
- Public Hostname service 是 `http://pi-web:30141`，不是 `localhost`，也不是
  `https`。

### 域名直接打开应用，没有登录页

立即停止远程使用并检查：

- Access application domain 是否准确为 `pi.example.com`。
- 是否误加了 `Everyone` 或 `Bypass` 策略。
- 路由器是否开放了 `30141`。
- Compose 是否仍然使用 `127.0.0.1:30141:30141`。

### 安全检查清单

- Cloudflare 账号和登录邮箱均启用 MFA。
- Access 只允许准确邮箱地址。
- 路由器没有转发 `30141`。
- `.env` 从未提交或分享。
- Docker 只挂载 agent 真正需要编辑的项目目录。
- Mac 设置为运行期间不自动休眠，并让 Docker Desktop 登录后自动启动。
