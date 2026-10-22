#!/usr/bin/env bash
# 外部兜底触发：在 GitHub 的 schedule 之外，检查「最近 20 小时是否跑过 Auto Sign」，
# 没有就手动 dispatch 一次。幂等 —— 可以被 launchd / 云定时器反复调用。
#
# 为什么用「最近 20 小时」而不是「今天(UCT)」：
#   触发时间在 UTC 00:17，本地凌晨/早晨的边界很容易跨日，20 小时窗口在
#   08:40 / 11:40 两次重试时都能正确看到当天早上那次运行。
#
# 用法：
#   scripts/trigger-sign.sh                  # 正常触发
#   DRY_RUN=1 scripts/trigger-sign.sh        # 只检查不触发
#   REPO=owner/repo scripts/trigger-sign.sh  # 换仓库
#
# 退出码：0 = 已有运行或已成功提交触发；非 0 = 失败（launchd 日志里可见）
set -euo pipefail

REPO="${REPO:-HibernalGlow/skyland-auto-sign}"
WORKFLOW="${WORKFLOW:-auto-sign.yml}"
BRANCH="${BRANCH:-main}"
WINDOW_HOURS="${WINDOW_HOURS:-20}"

# launchd 启动时 PATH 很精简，补上 Homebrew 等常见路径
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

log() { echo "[$(date '+%F %T %Z')] $*"; }

if ! command -v gh >/dev/null 2>&1; then
  log "找不到 gh，跳过（检查 PATH）" >&2
  exit 1
fi

# 计算窗口起点（BSD date 与 GNU date 都兼容）
if date -u -v-"${WINDOW_HOURS}"H '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
  CUTOFF="$(date -u -v-"${WINDOW_HOURS}"H '+%Y-%m-%dT%H:%M:%SZ')"
else
  CUTOFF="$(date -u -d "-${WINDOW_HOURS} hours" '+%Y-%m-%dT%H:%M:%SZ')"
fi

# 窗口内的有效运行数（被取消 / 跳过的不算）；ISO8601 字符串可直接比较
COUNT="$(gh run list -R "$REPO" -w "$WORKFLOW" -L 30 \
  --json createdAt,conclusion \
  --jq "[.[] | select(.createdAt > \"$CUTOFF\") | select(.conclusion != \"cancelled\" and .conclusion != \"skipped\")] | length" \
  2>/dev/null || echo 0)"

if [ "${COUNT:-0}" -gt 0 ]; then
  log "最近 ${WINDOW_HOURS}h 内 $REPO 已有 ${COUNT} 次运行（窗口起点 ${CUTOFF}），无需兜底"
  exit 0
fi

log "最近 ${WINDOW_HOURS}h 内没有运行（窗口起点 ${CUTOFF}），提交 workflow_dispatch"

if [ "${DRY_RUN:-0}" = "1" ]; then
  log "[dry-run] 只检查不触发：gh workflow run $WORKFLOW -R $REPO --ref $BRANCH"
  exit 0
fi

gh workflow run "$WORKFLOW" -R "$REPO" --ref "$BRANCH" -f reason=external-cron
log "触发请求已提交：https://github.com/$REPO/actions/workflows/$WORKFLOW"
