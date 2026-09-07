# OpenClaw 个人微信助手

## 固定组件

| 组件 | 固定版本或值 |
| --- | --- |
| Node.js | `22.22.3` |
| OpenClaw | `2026.7.1` |
| Parallel plugin | `2026.7.1` |
| Tencent Weixin plugin | `2.4.6` |
| Lucen Image plugin | `1.1.0`（仓库内） |
| Memory plugin | OpenClaw 内置 `memory-core@2026.7.1` |
| Gateway | `127.0.0.1:18789` |
| Sandbox image | `cowagent-openclaw-sandbox:2026.7.1` |
| Workspace | `~/OpenClawWorkspace` |

不要使用 `latest`、beta、TRAE 或 `@openclaw/codex`。升级必须修改仓库中的固定版本并重新走完整验收。

沙箱基础层是 Docker Official Image `node:22.22.0-bookworm-slim` 的镜像站副本，并按内容 digest 固定；这是为了绕开当前网络不可达的 Docker Hub token 服务，不会跟随标签漂移。

沙箱内置 `rsvg-convert`、Pillow 和 Noto CJK 字体。微信出站图片必须是 PNG/JPEG；模型生成 SVG 概念稿时，先转为 PNG 再通过 `MEDIA:` 发送，不能直接发送 SVG。

原生生图使用独立的 OpenAI 兼容端点、`IMAGE_API_KEY` 和仓库内 `lucen-image` 适配插件，默认模型为 `lucen-image/gpt-image-2`。适配器强制请求 `b64_json`，单次最多生成一张图，并将误传的 `openai/gpt-image-1.5` 兼容映射到 Lucen 的 `gpt-image-2`。聊天与生图密钥必须分离；`image_generate` 已开放，音乐、视频和 TTS 仍保持禁用。

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

先创建 OpenClaw 专用聊天中转子密钥和生图密钥。两者必须互不相同，也不能复用 CowAgent 的 `RELAY_API_KEY`，并应有独立额度和撤销能力。

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

`openclaw-accept` 依次执行配置/安全审计、已开放模型的非流式文本/流式首正文/结构化工具调用、20 次日常模型、两步工具、三类搜索、沙箱隔离和一次真实生图测试。全部通过后才生成被 Git 忽略的 `READY_FOR_WEIXIN` 标记。

模型规则：

- `/model daily`: `relay/gpt-5.6-terra`，high，当前默认主模型、utility 与稳定性验收模型。
- 当前聊天线路为 Terra/FunCloud；Lucen 聊天线路在 2026-07-31 持续返回 HTTP 502，恢复并重新验收前不加入可选模型。
- `gpt-5.6-luna` 的非流式正文冒烟测试为空，暂不开放。
- 不配置自动 fallback；模型失败时明确报错，不静默切换线路。

高推理模型偶发需要数分钟才返回首个可见 token，因此 relay provider 超时固定为 600 秒，Agent 总超时固定为 900 秒；两者不要倒置，否则会再次出现 `LLM request timed out`。

模型 ID、别名、推理等级、流式阈值和门禁退出码统一维护在 `openclaw/models.json`。验收会对所有已开放模型执行文本、流式和工具调用检查，并对默认 `daily` 模型执行 20 次日常稳定性测试。`daily` 不达标时脚本停止并禁止扫码。

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

## 7. 自动巡检与自愈

本机 launchd 持续监听 Gateway 日志，但不做定时健康请求。只有日志出现模型 `5xx`/`FailoverError`、微信轮询失败、通道失联，或 Docker 沙箱报告 daemon 不可用时，才触发一次完整检查和自愈：

```bash
make openclaw-self-heal-install
make openclaw-self-heal
```

触发后的检查覆盖认证 Gateway RPC、微信长轮询心跳和一次真实聊天回复。检测到 Docker daemon 不可用时，脚本会启动 Docker Desktop，最多等待 90 秒并重新执行完整检查；恢复失败会发出 macOS 通知，且不会误切换模型线路。Gateway 或微信心跳异常时先重启 Gateway；聊天线路故障时探测备用 provider。备用线路必须连续通过两次文本、流式输出和结构化工具调用，切换后还要通过 OpenClaw 实际 Agent 回复与微信心跳检查，否则自动恢复切换前的环境和配置。同类错误事件在 5 分钟冷却窗口内只触发一次，避免上游重试风暴造成重复处理。

候选线路仅配置在权限为 `0600` 的 `~/.openclaw/self-heal.env`，可参考 `openclaw/self-heal.env.example`。状态、自愈日志和事件触发日志分别位于 `~/.openclaw/self-heal-state.json`、`~/.openclaw/self-heal.log` 与 `~/.openclaw/self-heal-trigger.log`。切换前快照保留在 `~/.openclaw/self-heal-backups`。

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
