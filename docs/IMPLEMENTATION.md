# 实施设计

## 1. 决策

采用“成熟产品主干 + 薄定制层”，不从零开发聊天产品，也不直接修改 CowAgent 源码。

第一阶段由 CowAgent 负责手机 Web、企业微信渠道、模型调用、普通会话和基础记忆。第二阶段才增加独立 Codex Bridge，负责代码仓库访问、任务排队、沙箱、审批和结果回传。

这样做的原因：

1. CowAgent 已支持 `open_ai_api_base`、OpenAI 兼容模型和 WeCom Bot 长连接。
2. 手机和企微基础链路不需要重复开发。
3. Codex 的风险边界与聊天机器人不同，应独立部署和授权。
4. 不 fork 上游，后续升级和回滚更简单。

## 2. 第一阶段架构

```text
手机浏览器 ---------\
                     > CowAgent ---- OpenAI 兼容中转站
企业微信 WeCom Bot -/
```

第一阶段范围：

- 中转站文本聊天
- CowAgent Web 控制台
- 企微私聊和群聊
- 会话持久化与基础备份
- Agent 工具关闭

不包含：

- 自动运行 shell
- 读取或修改代码仓库
- 自动提交代码或推送 Git
- 统一企业 SSO、部门权限和审计平台

## 3. 安全默认值

上游示例 Compose 使用了 `seccomp:unconfined`。本项目不使用该设置，并增加：

- `no-new-privileges`
- 丢弃默认 Linux capabilities，仅恢复入口脚本切换非 root 用户所需的 `CHOWN`、`SETGID`、`SETUID`
- 进程数限制
- 独立持久化目录
- 将 CowAgent 的 `COW_DATA_DIR` 指向 `data/cow`，使通道配置和扫码凭据在容器重建后保留
- 默认只绑定 `127.0.0.1`
- Agent 与自进化功能默认关闭
- 上下文轮数、token 和 Agent 步骤上限
- 启动日志敏感值脱敏和 Docker 日志轮转

这些设置需要在实际镜像上验证。如果 CowAgent 的某项功能因最小权限失败，应逐项增加最小权限，不整体关闭隔离。

## 4. 验收顺序

### 阶段 A：中转站

1. `/chat/completions` 或 `/responses` 测试成功。
2. 返回模型名称与后台配置一致。
3. 流式回复正常。
4. 子密钥配额、过期和撤销机制有效。

CowAgent 的 OpenAI 兼容文本链路应优先验证 `/chat/completions`。单独通过 `/responses` 测试不代表 CowAgent 无需适配即可工作。

### 阶段 B：CowAgent Web

1. 本机可登录 Web 控制台。
2. 能连续对话且重启后数据仍在。
3. 手机通过局域网或 HTTPS 地址访问。
4. 未授权用户无法访问。

### 阶段 C：企业微信

1. WeCom Bot 长连接成功。
2. 私聊和群聊 `@Bot` 均可回复。
3. 图片、文件和长回答按中转站能力逐项测试。
4. 群内未明确触发时不执行高风险工具。

## 5. Codex Bridge 设计

只有基础链路通过后才实施。建议接口：

```text
POST /v1/codex/jobs
GET  /v1/codex/jobs/{job_id}
POST /v1/codex/jobs/{job_id}/approve
POST /v1/codex/jobs/{job_id}/cancel
```

核心规则：

- 仅 `/codex`、`/review`、`/fix` 等显式命令进入 Codex。
- 仓库必须来自白名单，用户不能提交任意本地路径。
- 每个任务使用独立 worktree 或容器。
- 初期只读；写入阶段只能生成补丁。
- 创建分支或草稿 PR 前必须人工批准。
- 永不直接操作 `main` 或生产服务器。
- 中转站密钥、Git 凭据和企微 Secret 分开管理。

Codex Bridge 可通过 CowAgent MCP 工具接入，但提交任务的鉴权、命令路由和审批必须由确定性代码处理，不能只依赖模型提示词。

## 6. 升级策略

当前镜像默认使用 `latest`，便于首次验证，但正式运行前应在测试通过后锁定镜像 digest。升级流程应为：备份 `data/cow`、拉取新镜像、在测试实例验证、再替换生产实例。

上游当前镜像为 `linux/amd64`，本项目在 Apple Silicon Mac 上通过 Docker 的 amd64 模拟运行。首次验收需要额外观察启动耗时、内存占用和工具兼容性。

## 7. 当前阻塞项

- 企微 Bot 尚未扫码绑定。
- 模型中转站在严格复测中出现过 HTTP 成功但正文为空；扩大企微可见范围前需确认模型或中转路由稳定性。
- Tailscale 已登录并在线，但“登录时自动启动”仍待用户确认。

Docker Desktop 4.82.0 已安装并启动，CowAgent 官方镜像已拉取。中转站 Chat Completions 可返回正常内容，但严格测试也捕获到偶发空正文，暂不视为稳定验收通过。正式 CowAgent 容器已运行，Web 控制台返回 HTTP 303 并跳转到 `/chat`，企微相关渠道正常加载。Apple Silicon 上首次启动约需一分钟。

Tailscale 1.98.8 已安装并登录，CowAgent 只绑定 Tailscale 私网 IP。私网地址返回 HTTP 303，原局域网地址不可访问。
