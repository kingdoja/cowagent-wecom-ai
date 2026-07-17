# OpenClaw 个人微信助手

## 固定组件

| 组件 | 固定版本或值 |
| --- | --- |
| Node.js | `22.22.3` |
| OpenClaw | `2026.7.1` |
| Parallel plugin | `2026.7.1` |
| Tencent Weixin plugin | `2.4.6` |
| Memory plugin | OpenClaw 内置 `memory-core@2026.7.1` |
| Gateway | `127.0.0.1:18789` |
| Sandbox image | `cowagent-openclaw-sandbox:2026.7.1` |
| Workspace | `~/OpenClawWorkspace` |

不要使用 `latest`、beta、TRAE 或 `@openclaw/codex`。升级必须修改仓库中的固定版本并重新走完整验收。

沙箱基础层是 Docker Official Image `node:22.22.0-bookworm-slim` 的镜像站副本，并按内容 digest 固定；这是为了绕开当前网络不可达的 Docker Hub token 服务，不会跟随标签漂移。

## 1. 无密钥安装

```bash
make openclaw-install
```

这个步骤安装固定版本核心和两个插件、创建权限为 `0700` 的目录，并构建 Docker 沙箱镜像。它不会登录微信、停止 CowAgent 或保存中转凭证。

## 2. 主机前置项

查看状态：

```bash
make openclaw-host-status
```

在“系统设置 > 隐私与安全性 > FileVault”中开启 FileVault，亲自保存恢复密钥。不要把恢复密钥放入本仓库、聊天或普通云笔记。

设置接通电源时系统不睡眠，显示器 10 分钟休眠：

```bash
make openclaw-host-power
```

这个命令会触发 macOS 管理员密码提示。

## 3. 独立凭证与配置

先创建 OpenClaw 专用中转子密钥。它必须与 CowAgent 的 `RELAY_API_KEY` 不同，并应有独立额度和撤销能力。

```bash
cp openclaw/openclaw.env.example openclaw/.env
chmod 600 openclaw/.env
```

填写 `RELAY_API_BASE` 和新的 `RELAY_API_KEY`。Gateway token 可保留占位符，配置脚本会生成 96 位十六进制随机值。

```bash
make openclaw-configure
make openclaw-preflight
```

配置脚本会拒绝 FileVault 关闭、占位密钥、非 `0600` 环境文件和复用 CowAgent 密钥。正式文件只写入 `~/.openclaw`，仓库不保存凭证。

## 4. Gateway 与验收

```bash
make openclaw-gateway-install
make openclaw-status
make openclaw-accept
```

`openclaw-accept` 依次执行配置/安全审计、已开放模型的非流式文本/流式首正文/结构化工具调用、20 次日常模型、两步工具、三类搜索和沙箱隔离测试。全部通过后才生成被 Git 忽略的 `READY_FOR_WEIXIN` 标记。

模型规则：

- `/model daily`: `relay/gpt-5.4-mini`，low，稳定日常模型。
- `/model smart`: `relay/gpt-5.5`，medium，需要更强推理时手动选择。
- `/model sol`: `relay/gpt-5.6-sol`，high，高阶手动模型。
- `/model terra`: `relay/gpt-5.6-terra`，high，高阶手动模型。
- `gpt-5.6-luna` 的非流式正文冒烟测试为空，暂不开放。
- 高阶模型不参与自动 fallback，避免延迟或空正文影响日常会话。

模型 ID、别名、推理等级、流式阈值和门禁退出码统一维护在 `openclaw/models.json`。验收会对所有已开放模型执行文本、流式和工具调用检查，并对 Mini 执行 20 次日常稳定性测试。Mini 不达标时脚本停止并禁止扫码；任一手动模型不达标时，降级配置只保留通过复验的 `daily`，不会留下未验证的手动别名。

搜索门禁除了检查回答中的 URL，还会读取 OpenClaw 会话轨迹，确认至少一次 `web_fetch` 成功返回正文。

## 5. 第二微信账号

```bash
make openclaw-weixin-login
```

只用第二个微信账号扫码。微信插件默认执行 pairing，未配对发送者会被拒绝；会话按 `account + channel + peer` 隔离。不要导入 CowAgent 的聊天历史或完整记忆。

验收文本、图片、文件、长回答、三个模型命令、未配对拒绝、Gateway 重启和 Mac 重新登录恢复后，人工生成一份脱敏个人偏好摘要放到 `~/OpenClawWorkspace`。

## 6. 切换与回滚

切换主账号前：

```bash
make openclaw-backup
```

备份位于 `~/OpenClawBackups`，权限为 `0700/0600`，脚本清理超过 30 天的归档。然后才停止 CowAgent，并用主微信账号登录 OpenClaw。测试账号在主账号稳定后移除。

需要回滚时：

```bash
make openclaw-rollback
```

这个命令停止 OpenClaw Gateway 并恢复 CowAgent 容器，不删除 OpenClaw、镜像、凭证或备份。

## 管理入口

- 本机：`http://127.0.0.1:18789/`
- 手机：Gateway 启动后由 `tailscale serve status` 显示的私网 HTTPS 地址

Gateway 始终要求随机 token。禁止 Tailscale Funnel、`0.0.0.0`、普通 LAN 监听和 Docker socket 挂载。

## 设计依据

- [OpenClaw 安装](https://docs.openclaw.ai/install)
- [微信插件](https://docs.openclaw.ai/channels/wechat)
- [沙箱](https://docs.openclaw.ai/gateway/sandboxing)
- [Parallel 搜索](https://docs.openclaw.ai/tools/parallel-search)
- [执行审批](https://docs.openclaw.ai/tools/exec-approvals)
- [Tailscale](https://docs.openclaw.ai/gateway/tailscale)
