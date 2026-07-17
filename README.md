# CowAgent 与 OpenClaw 个人助手

这个仓库同时保留两条互不争用的路径：

- CowAgent 继续运行，作为现有 Web、微信和企微通道及 30 天回滚方案。
- OpenClaw 使用第二个微信账号并行验收，通过硬门槛后才切换主微信账号。

OpenClaw 的完整部署和验收流程见 [docs/OPENCLAW.md](docs/OPENCLAW.md)。

## OpenClaw 当前边界

- 固定 `openclaw@2026.7.1`、官方内置 `memory-core`、`@openclaw/parallel-plugin@2026.7.1` 和 `@tencent-weixin/openclaw-weixin@2.4.6`。
- 只使用 OpenClaw 内置 runtime，不安装 Codex harness，不读取 `~/.codex`。
- 只允许专属工作区文件、Parallel 搜索、网页抓取和 Docker 沙箱执行。
- Gateway 只监听 `127.0.0.1:18789`，手机入口由 Tailscale Serve 提供。
- 宿主执行、桌面控制、主动消息、定时任务、节点控制和 elevated 全部关闭。

在 FileVault 开启前，仓库只安装无密钥组件，不会写入正式 OpenClaw 凭证。

## OpenClaw 快速顺序

```bash
make openclaw-install
make openclaw-host-status
make openclaw-host-power
make openclaw-configure
make openclaw-gateway-install
make openclaw-accept
make openclaw-weixin-login
```

最后一个命令只允许使用第二个微信账号扫码。验收前不要停止 CowAgent。

## CowAgent 现有部署

这个项目不修改 CowAgent 上游源码，而是提供一套可复现、默认收紧权限的部署封装：

- CowAgent Web 控制台作为手机入口
- CowAgent WeCom Bot 长连接作为企业微信入口
- OpenAI 兼容中转站作为模型提供方
- 后续通过独立 Codex Bridge 增加受控代码任务

CowAgent 镜像按内容 digest 固定。升级镜像时必须同时更新 `docker-compose.yml`、`.env.example` 和本机 `.env`，再重新执行中转与流式测试。

完整决策和阶段设计见 [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md)。

企业微信方案比较、安全前置项和扫码验收见 [docs/WECOM.md](docs/WECOM.md)。

手机外网访问见 [docs/TAILSCALE.md](docs/TAILSCALE.md)。

## 当前阶段

第一阶段部署已运行，企业微信等待扫码授权。项目不会把真实密钥写进仓库，默认关闭 CowAgent Agent 工具和自进化能力，只启用普通聊天链路。模型中转已可返回文本，但严格测试捕获到过空正文，扩大使用范围前仍需做稳定性验收。

## 快速开始

```bash
make bootstrap
```

然后在本机 `.env` 中填写：

```text
RELAY_API_BASE
RELAY_API_KEY
RELAY_MODEL
COWAGENT_WEB_PASSWORD
```

`.env` 按数据文件解析，不会作为 shell 脚本执行。包含空格或 `#` 的值请使用成对的单引号或双引号。

依次执行：

```bash
make preflight
make test-unit
make test-relay
make test-streaming
make up
make logs
make tailscale-status
```

默认模板仅允许本机访问 `http://127.0.0.1:9899`。当前实例已经改为只绑定 Tailscale 私网地址，普通局域网和公网均不直接暴露 CowAgent。

无论 Tailscale 绑定地址如何，本机管理入口固定为 `http://127.0.0.1:19999`，仅供本机配置通道使用。

CowAgent 启动后，在 Web 控制台的 Channels 页面选择 WeCom Bot，优先使用二维码长连接方式，无需公网回调地址。

扫码后可检查连接状态：

```bash
make wecom-status
```

## 常用命令

```bash
make config       # 查看 Docker Compose 最终配置
make pull         # 拉取 CowAgent 镜像
make up           # 启动
make logs         # 查看日志
make down         # 停止
```

## 密钥规则

- 不提交 `.env`。
- 中转站使用单独的子密钥，设置额度并支持随时撤销。
- 不在聊天、截图或日志中发送 API Key、企微 Secret。
- `data/cow` 包含运行数据，不提交 Git，并应纳入私密备份。
