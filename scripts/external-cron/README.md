# 外部定时兜底

GitHub 的 `schedule` 是「尽力而为」的：会延迟、会被丢弃，公开仓库还会因为长期没有活动被自动停用，
而且**停用时不发任何通知**（这个仓库 2026-10-15 ~ 10-22 就整段漏签过）。

所以签到有两条额外触发路径，都调用 `workflow_dispatch`，与 GitHub 自己的 08:17 定时互补：

| 路径 | 时间（北京时间） | 依赖 | 适用 |
|---|---|---|---|
| GitHub schedule | 08:17 左右（可能延迟数小时） | GitHub | 主路径 |
| 本机 launchd | 08:40 / 11:40 | 这台 Mac 开机联网 | 日常兜底 |
| Cloudflare Worker | 08:40 | Cloudflare 账号 | 7×24 兜底 |

三者都是幂等的：先查「最近 20 小时是否已有运行」，有就跳过，不会重复签到
（用 20 小时窗口而不是「今天」，避免 UTC 跨日导致 08:40 的重试误判）。
判断逻辑在 `scripts/trigger-sign.sh`（本地）和 `worker.js`（云）里，两边一致。

---

## 1. 本机 launchd（已可直接用）

```bash
cp scripts/external-cron/launchd/cn.glow.skyland-autosign.plist ~/Library/LaunchAgents/
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/cn.glow.skyland-autosign.plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/cn.glow.skyland-autosign.plist
launchctl kickstart -p gui/$(id -u)/cn.glow.skyland-autosign   # 立刻试跑
tail -f ~/Library/Logs/skyland-autosign.log
```

卸载：`launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/cn.glow.skyland-autosign.plist`

手动跑一次：`scripts/trigger-sign.sh`

> 注意：launchd 不读你的 shell 配置，`gh` 的登录态来自钥匙串。
> 如果日志里报 `gh auth` 相关错误，改成在 plist 的 `EnvironmentVariables` 里加 `GH_TOKEN`（注意该文件权限设为 600）。

## 2. Cloudflare Worker（需要你登录 Cloudflare）

```bash
cd scripts/external-cron
npx wrangler login                       # 一次性
npx wrangler deploy                      # 部署 worker + 定时触发器
npx wrangler secret put GITHUB_PAT       # 粘贴 GitHub PAT（需 actions:write + actions:read）
```

PAT 建议用 **Fine-grained token**，只授权本仓库 `Actions: Read and write`。

验证：

```bash
npx wrangler tail                        # 看下一次 cron 的日志
curl https://skyland-autosign-cron.<你的子域>.workers.dev   # 返回今天已有几次运行
```

修改触发时间：编辑 `wrangler.toml` 的 `crons`（UTC）后重新 `wrangler deploy`。

## 3. 检查是否真的跑了

```bash
gh run list -R HibernalGlow/skyland-auto-sign -w auto-sign.yml -L 5
```

`event` 列会告诉你来源：`schedule`（GitHub 自己）、`workflow_dispatch`（外部触发）。
