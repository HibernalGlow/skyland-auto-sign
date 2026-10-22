#!/usr/bin/env bash
# 外部兜底触发：在 GitHub 的 schedule 之外，检查「今天是否已经跑过 Auto Sign」，
# 没有就手动 dispatch 一次。幂等 —— 可以被 launchd / 云定时器反复调用。
#
# 用法：
#   scripts/trigger-sign.sh                 # 本地 / launchd
#   REPO=owner/repo scripts/trigger-sign.sh # 指定仓库（默认本仓库）
#
# 退出码：0 = 已有运行或已成功提交触发；非 0 = 失败（launchd 日志里可见）
set -euo pipefail

REPO="${REPO:-HibernalGlow/skyland-auto-sign}"
WORKFLOW="${WORKFLOW:-auto-sign.yml}"
BRANCH="${BRANCH:-main}"

# launchd 启动时 PATH 很精简，补上 Homebrew 等常见路径
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

log() { echo "[$(date '+%F %T %Z')] $*"; }

if ! command -v gh >/dev/null 2>&1; then
  log "找不到 gh，跳过（检查 PATH）" >&2
  exit 1
fi

# 以 UTC 判定「今天」，与 cron 的 UTC 时间轴一致
TODAY_UTC="$(date -u +%F)"

# 当天已有的有效运行数（被取消 / 跳过的不算）
COUNT="$(gh run list -R "$REPO" -w "$WORKFLOW" -L 20 \
  --json createdAt,conclusion,status \
  --jq "[.[] | select(.createdAt[0:10] == \"$TODAY_UTC\") | select(.conclusion != \"cancelled\" and .conclusion != \"skipped\")] | length" \
  2>/dev/null || echo 0)"

if [ "${COUNT:-0}" -gt 0 ]; then
  log "今天($TODAY_UTC) $REPO 已有 $COUNT 次运行，无需兜底"
  exit 0
fi

log "今天($TODAY_UTC) 还没有运行，提交 workflow_dispatch"
gh workflow run "$WORKFLOW" -R "$REPO" --ref "$BRANCH" -f reason=external-cron
log "触发请求已提交，稍后可查看：https://github.com/$REPO/actions/workflows/$WORKFLOW"
