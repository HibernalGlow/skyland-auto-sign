#!/usr/bin/env bash
# 安装 / 卸载本机 launchd 兜底定时（每天 08:40、11:40 检查并触发签到）。
#
# 必须在「你自己的终端」里运行（launchctl 需要 GUI 登录会话，
# 从脚本代理/无 TTY 的环境执行会报 "Bootstrap failed: 5: Input/output error"）。
#
#   scripts/external-cron/install-launchd.sh              # 安装
#   scripts/external-cron/install-launchd.sh --uninstall  # 卸载
#   scripts/external-cron/install-launchd.sh --test       # 安装后立刻试跑（DRY_RUN，不真的触发）
set -euo pipefail

LABEL="cn.glow.skyland-autosign"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO_DIR/scripts/external-cron/launchd/$LABEL.plist"
DST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

uninstall() {
  launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
  rm -f "$DST"
  echo "已卸载 $LABEL（$DST）"
}

case "${1:-}" in
  --uninstall)
    uninstall
    exit 0
    ;;
esac

mkdir -p "$HOME/Library/LaunchAgents"
# 模板里的绝对路径替换成当前仓库路径，仓库搬家后重跑本脚本即可
sed "s#/Users/glow/Base/Code/Prometheus/skyland-auto-sign#$REPO_DIR#g" "$SRC" > "$DST"
chmod 644 "$DST"
plutil -lint "$DST"

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$DST"
echo "已安装并加载 $LABEL"
launchctl print "gui/$UID_NUM/$LABEL" | grep -E "state|next fire" || true

if [ "${1:-}" = "--test" ]; then
  echo "--- 试跑（DRY_RUN=1，只检查不触发）---"
  DRY_RUN=1 "$REPO_DIR/scripts/trigger-sign.sh"
fi

echo
echo "日志：tail -f ~/Library/Logs/skyland-autosign.log"
echo "卸载：$0 --uninstall"
