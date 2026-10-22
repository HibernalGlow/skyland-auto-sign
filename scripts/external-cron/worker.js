/**
 * 森空岛自动签到 —— 外部定时兜底（Cloudflare Worker Cron）
 *
 * 作用：不依赖 GitHub 的 schedule，由 Cloudflare 每天定时调用 workflow_dispatch。
 * 幂等：先查「今天(UTC)是否已有运行」，有就跳过，避免和 GitHub 自带 schedule 重复签到。
 *
 * 需要的绑定：
 *   - Secret GITHUB_PAT : 具备 actions:write + actions:read 的细粒度 PAT（或经典 PAT 的 repo/workflow）
 *   - Vars   REPO / WORKFLOW / BRANCH
 */

const GITHUB_API = 'https://api.github.com';
const WINDOW_HOURS = 20; // 与 scripts/trigger-sign.sh 保持一致

function windowStart() {
  return new Date(Date.now() - WINDOW_HOURS * 3600 * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

async function ghFetch(env, path, init = {}) {
  const res = await fetch(`${GITHUB_API}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${env.GITHUB_PAT}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'skyland-external-cron',
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
  return res;
}

async function runsRecent(env) {
  const since = windowStart();
  const res = await ghFetch(
    env,
    `/repos/${env.REPO}/actions/workflows/${env.WORKFLOW}/runs?per_page=30`,
  );
  if (!res.ok) {
    throw new Error(`list runs failed: ${res.status} ${await res.text()}`);
  }
  const data = await res.json();
  return (data.workflow_runs || []).filter(
    (r) =>
      r.created_at > since &&
      r.conclusion !== 'cancelled' &&
      r.conclusion !== 'skipped',
  ).length;
}

async function dispatch(env, reason) {
  const res = await ghFetch(env, `/repos/${env.REPO}/actions/workflows/${env.WORKFLOW}/dispatches`, {
    method: 'POST',
    body: JSON.stringify({ ref: env.BRANCH || 'main', inputs: { reason } }),
  });
  if (res.status !== 204) {
    throw new Error(`dispatch failed: ${res.status} ${await res.text()}`);
  }
}

export default {
  async scheduled(event, env, ctx) {
    const trigger = event.cron || 'cron';
    try {
      const count = await runsRecent(env);
      if (count > 0) {
        console.log(`[skip] 最近 ${WINDOW_HOURS}h 已有 ${count} 次运行 (${trigger})`);
        return;
      }
      await dispatch(env, `cf-${trigger}`);
      console.log(`[ok] 已触发 ${env.REPO} / ${env.WORKFLOW} (${trigger})`);
    } catch (err) {
      console.error(`[fail] ${err.message}`);
      throw err;
    }
  },

  // 浏览器访问 Worker 域名时可手动看一眼状态
  async fetch(request, env) {
    try {
      const count = await runsRecent(env);
      return new Response(
        JSON.stringify(
          {
            repo: env.REPO,
            workflow: env.WORKFLOW,
            window_hours: WINDOW_HOURS,
            runs_in_window: count,
            window_start: windowStart(),
          },
          null,
          2,
        ),
        { headers: { 'content-type': 'application/json; charset=utf-8' } },
      );
    } catch (err) {
      return new Response(`error: ${err.message}`, { status: 500 });
    }
  },
};
