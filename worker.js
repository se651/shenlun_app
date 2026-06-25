/**
 * Cloudflare Worker — CORS 代理
 * 部署后 Web 版实时抓取党媒新闻
 * 
 * 部署：
 * 1. workers.dev 创建 Worker
 * 2. 粘贴此代码
 * 3. 得到 https://你的worker名.你的账号.workers.dev
 *
 * 免费：10 万次/天，单次 10 秒超时
 */
export default {
  async fetch(request) {
    const url = new URL(request.url);
    const target = url.searchParams.get('url');
    if (!target) return new Response('Missing ?url=', { status: 400 });

    // 安全检查：只允许白名单域名
    const allowed = [
      'people.com.cn', 'opinion.people.com.cn',
      'xinhuanet.com', 'www.xinhuanet.com', 'news.cn', 'www.news.cn',
      'qstheory.cn', 'www.qstheory.cn',
      'cctv.com', 'news.cctv.com',
    ];
    const host = new URL(target).hostname;
    if (!allowed.some(a => host === a || host.endsWith('.' + a))) {
      return new Response('Forbidden domain', { status: 403 });
    }

    try {
      const resp = await fetch(target, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
        redirect: 'follow',
        signal: AbortSignal.timeout(8000),
      });

      const body = await resp.arrayBuffer();
      return new Response(body, {
        status: resp.status,
        headers: {
          'Content-Type': resp.headers.get('Content-Type') || 'text/html; charset=utf-8',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
          'Cache-Control': 'public, max-age=300',
        },
      });
    } catch (e) {
      return new Response('Proxy error: ' + e.message, { status: 502 });
    }
  },
};
