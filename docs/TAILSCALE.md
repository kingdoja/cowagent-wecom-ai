# 手机外网访问

CowAgent 只绑定这台 Mac 的 Tailscale 私网 IP，不再监听普通局域网地址，也没有开启公网端口映射。

## 手机设置

1. 在 iPhone App Store 或 Android 应用商店安装官方 Tailscale。
2. 使用与这台 Mac 相同的 Tailscale 账号登录。
3. 在手机中允许 Tailscale 添加 VPN 配置并保持连接。
4. 打开 `http://100.79.8.33:9899`。
5. 使用项目 `.env` 中的 `COWAGENT_WEB_PASSWORD` 登录 CowAgent。

地址栏显示 HTTP 是正常的；手机到 Mac 的流量仍在 Tailscale WireGuard 私网隧道内加密。不要把这个服务改成公网端口映射。

## Mac 状态检查

```bash
make tailscale-status
```

预期结果包括 Tailscale IP、CowAgent URL 和 HTTP 303/200。

## 运行条件

- Mac 必须开机、联网且不能深度休眠。
- Docker Desktop 和 CowAgent 容器必须运行。
- Tailscale 必须连接。
- 正式长期运行建议允许 Tailscale 登录时自动启动。

Tailscale IP 通常保持稳定。如果 IP 变化，应把 `.env` 中的 `COWAGENT_BIND_HOST` 改为新 IP，再执行：

```bash
make up
```

