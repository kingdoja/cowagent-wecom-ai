# CowAgent WeCom AI

一个面向个人与小团队的多入口 AI 助手部署方案：以 CowAgent 承载 Web 与企业微信对话，以 OpenAI 兼容中转站提供模型能力，并通过 OpenClaw 隔离验证个人微信场景。

> **一句话概括**：把“能聊天的模型”变成一套可部署、可测试、可回滚的企业微信 AI 助手。

这个项目的重点不是重新开发一个聊天 UI，而是把现有能力组织成一套可复现、可观测、可回滚的运行系统：

- **多入口接入**：手机 Web 控制台 + 企业微信智能机器人（WebSocket 长连接）。
- **模型解耦**：通过 OpenAI-compatible API 接入不同模型和中转线路，应用层无需绑定具体供应商。
- **流式体验**：在不修改 CowAgent 上游镜像的前提下，以运行时补丁接入 SSE 流式回复，降低企微端首屏等待。
- **安全默认值**：默认关闭 Agent 与自进化能力，容器启用 `no-new-privileges`、最小 capabilities、进程数限制和日志轮转。
- **可验证运维**：提供 preflight、单元测试、中转站测试、流式测试、企微状态检查和 OpenClaw 多项验收门禁。
- **可回滚演进**：CowAgent 与 OpenClaw 使用独立账号、凭证和工作区，可并行验收，满足条件后再切换主入口。

> 当前项目处于“基础链路可运行、企业微信小范围验收”阶段。企微扫码授权和模型中转稳定性需要在实际环境中完成最终验收，README 不把未验证能力包装成生产承诺。

## 适合谁

- 想把个人 AI 助手接入企业微信、手机 Web 的个人开发者。
- 需要在内网或私有网络运行，并对凭证、日志和模型费用有控制力的小团队。
- 关注 AI 应用工程化、容器安全和灰度发布方法的面试官或技术评审。

## 核心能力一览

| 能力 | 当前状态 | 入口 / 命令 |
| --- | --- | --- |
| 手机 Web 对话 | 可运行 | `http://127.0.0.1:9899` |
| 企业微信单聊 / 群聊 | 支持扫码接入，小范围验收 | **Channels → WeCom Bot** |
| OpenAI-compatible 模型 | 已接入 | `make test-relay` |
| SSE 流式回复 | 已实现，可一键回滚 | `make test-streaming` |
| 私网访问与容器加固 | 已配置 | Tailscale、Compose security opts |
| OpenClaw 第二账号验收 | 独立链路 | `make openclaw-accept` |

## 架构概览

```text
手机浏览器 ------------------\
                               > CowAgent  ---- OpenAI-compatible Relay ---- LLM
企业微信员工 / 内部群 ----------/
       (WeCom Bot WebSocket)

第二微信账号 --> OpenClaw Gateway --> 独立模型凭证 / Docker Sandbox
                       |
                       +--> Tailscale Serve（仅暴露私网管理入口）
```

### 运行边界

| 模块 | 职责 | 默认边界 |
| --- | --- | --- |
| CowAgent | Web 会话、企微通道、上下文与基础记忆 | Agent 工具和自进化关闭 |
| Relay | 统一的模型 API 入口 | 使用独立子密钥，可设置额度并撤销 |
| Runtime patch | 注入流式回复与敏感日志脱敏 | 以只读 volume 挂载，不 fork 上游 |
| OpenClaw | 第二微信账号的独立验收链路 | Gateway 仅监听本机，任务在 Docker 沙箱中执行 |
| Tailscale | 手机访问管理端 | 不承载企微回调，不使用 Funnel |

## 工程亮点

### 1. 薄定制层，降低升级成本

项目不修改 CowAgent 上游源码，而是通过 `runtime/` 目录提供启动包装和流式适配器。上游镜像按 `sha256` digest 固定，定制逻辑可独立测试、回滚和替换。

### 2. 从首 token 开始更新企微回复

`runtime/cowagent_streaming_patch.py` 将普通聊天请求切换为 SSE，并把增量内容转为 CowAgent 的 `message_update` 事件。适配器会校验空流、保留最后一次完整内容，并在失败时有限重试；通过 `COW_STREAMING_PATCH_ENABLED=False` 可恢复上游非流式行为。

### 3. 安全策略前置，而不是依赖提示词

- CowAgent 容器默认只绑定 `127.0.0.1`，外网访问通过 Tailscale 私网地址。
- `cap_drop: ALL`，仅恢复启动非 root 用户所需的 `CHOWN`、`SETGID`、`SETUID`。
- 使用 `no-new-privileges`、`pids_limit`、独立持久化目录和 Docker 日志轮转。
- `.env` 按 dotenv 数据格式解析，不作为 shell 脚本执行；运行日志统一脱敏。
- Codex Bridge 只作为后续设计，仓库白名单、worktree、补丁输出和人工审批均要求由确定性代码控制。

### 4. 用门禁脚本验证真实链路

验证不仅检查 HTTP 状态码，还检查非空正文、流式首 token、结构化工具调用、沙箱隔离、搜索正文和重启恢复。OpenClaw 的 `openclaw-accept` 会在允许扫码前执行完整验收，失败即阻止切换。

## 项目结构

```text
.
├── docker-compose.yml       # CowAgent 容器、安全边界与持久化配置
├── runtime/                 # 不修改上游镜像的启动包装、流式适配和单测
├── scripts/                 # bootstrap、preflight、测试、状态检查与回滚脚本
├── openclaw/                # 第二微信账号的隔离配置模板（不含正式凭证）
└── docs/                    # 实施决策、企微、Tailscale、OpenClaw 运维文档
```

## 这个项目体现的工程能力

从面试或技术评审视角，项目可以重点关注以下决策：

1. **先拆边界，再加能力**：聊天链路与代码执行链路分开，OpenClaw 使用第二账号并行验收，避免一次切换影响现有服务。
2. **把安全写进部署配置**：通过容器权限、网络绑定、凭证隔离和日志脱敏建立多层防线，而不是只依赖模型提示词。
3. **用可观测指标定位问题**：流式测试区分 `first_token` 与 `total`，可以判断瓶颈在模型 / Relay 还是通道层。
4. **保留确定性回滚路径**：镜像 digest、运行时补丁开关、备份与 rollback 脚本，让每次升级都可验证、可撤回。
5. **诚实标注交付状态**：README 明确区分“已实现”“小范围验收”和“后续规划”，方便用户评估真实风险。

## 快速开始

### 环境要求

- macOS 或 Linux
- Docker Desktop / Docker Engine + Compose
- `bash`、`curl`、`jq`
- 可用的 OpenAI-compatible Relay（支持 Chat Completions）

### 启动 CowAgent + 企业微信链路

```bash
make bootstrap
```

复制并填写 `.env` 中的以下配置：

```dotenv
RELAY_API_BASE=https://relay.example.com/v1
RELAY_API_KEY=replace-with-a-dedicated-sub-key
RELAY_MODEL=replace-with-the-relay-model-name
COWAGENT_WEB_PASSWORD=replace-with-a-long-random-password
```

按顺序执行检查和启动：

```bash
make preflight       # 配置、依赖、镜像 digest 和绑定地址检查
make test-unit       # dotenv、配置初始化和 OpenClaw relay gate 单测
make test-relay      # 验证 Relay 返回非空文本
make up
make test-streaming  # 验证真实容器中的流式回复
make logs
```

默认管理入口为 `http://127.0.0.1:19999`，CowAgent Web 入口为 `http://127.0.0.1:9899`。启动后进入 **Channels → WeCom Bot**，使用企微扫码长连接方式完成绑定，再运行：

```bash
make wecom-status
```

常用运维命令：

```bash
make config       # 查看最终 Compose 配置
make pull         # 拉取已固定 digest 的镜像
make down         # 停止服务
make tailscale-status
```

### 启动 OpenClaw 隔离验收链路

OpenClaw 使用第二个微信账号，与 CowAgent 的数据、凭证和会话隔离。完整流程如下：

```bash
make openclaw-install
make openclaw-host-status
make openclaw-configure
make openclaw-gateway-install
make openclaw-accept
make openclaw-weixin-login
```

`openclaw-accept` 会执行模型文本、流式、工具调用、搜索、沙箱和生图门禁；全部通过后才允许扫码。切换前使用 `make openclaw-backup`，需要回滚时使用 `make openclaw-rollback`。

## 测试与验收

```bash
make test-unit       # 本地逻辑测试
make test-relay      # Relay Chat Completions / Responses 测试
make test-streaming  # CowAgent 容器内 SSE 冒烟测试
make openclaw-accept # OpenClaw 全链路验收
```

流式测试同时输出 `first_token` 与 `total`：前者高说明模型或中转线路首 token 慢，后者高则需要评估模型、线路或超时配置，避免把通道层问题误判为企微问题。

## 安全与凭证

- `.env`、`openclaw/.env`、`data/cow` 和运行时备份均不提交 Git。
- CowAgent、OpenClaw、企微 Bot 和生图服务使用不同凭证，分别设置额度、权限和撤销策略。
- 不在聊天、截图、工单或普通日志中粘贴 API Key、企微 Secret 或 Gateway token。
- 正式运行前应轮换曾出现在历史日志中的密钥，并为 `data/cow` 建立私密备份。
- 企微可见范围从维护者和少量测试成员开始，群聊只响应明确 `@`。

## 后续演进：Codex Bridge

基础聊天链路稳定后，再通过独立服务增加代码任务能力：

```text
POST /v1/codex/jobs
GET  /v1/codex/jobs/{job_id}
POST /v1/codex/jobs/{job_id}/approve
POST /v1/codex/jobs/{job_id}/cancel
```

设计原则：显式命令路由、仓库白名单、每任务独立 worktree / 容器、初期只生成补丁、创建分支或 PR 前人工批准，永不直接操作 `main` 或生产服务器。

## 文档索引

- [实施设计与阶段决策](docs/IMPLEMENTATION.md)
- [企业微信接入与验收清单](docs/WECOM.md)
- [Tailscale 私网访问](docs/TAILSCALE.md)
- [OpenClaw 部署、门禁与回滚](docs/OPENCLAW.md)

## License

本仓库主要包含部署脚本、运行时适配和验收工具；上游 CowAgent、OpenClaw 及其插件分别遵循各自许可证。
