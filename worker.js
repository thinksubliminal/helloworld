// ─────────────────────────────────────────────────────────────────────────
// dropadot-cache — Cloudflare Worker
// ─────────────────────────────────────────────────────────────────────────
// Bundles today's read-only data for the boot path of dropadot.world so a
// viral page-load surge (1000+ visitors in a window) collapses into ~2
// Supabase queries per minute total instead of 6+ per visitor.
//
// Endpoint: GET https://dropadot-cache.thinksubliminal.workers.dev/loadAll
// Response: {
//   messages, flares, flare_responses,
//   message_responses, stars, star_responses
// }
//
// Each value is the raw array of rows for that table for today's UTC
// window (>= midnight UTC), ordered by created_at ascending. The client
// (`index.html` boot fetch) destructures this bundle and falls back to
// direct Supabase reads for any key that comes back null/undefined, so
// adding/removing keys here is non-breaking.
//
// The Worker fires its 6 SELECTs in parallel on every CACHE MISS,
// caches the result at the edge for 30s via Cache-Control + an
// explicit caches.default.put. `X-Cache: HIT` / `MISS` headers in the
// response let you confirm cache behavior in the browser network tab.
//
// IMPORTANT: this file is the canonical source of the live worker
// running in the Cloudflare dashboard. To deploy:
//   1. Open dash.cloudflare.com → Workers & Pages → dropadot-cache
//   2. Click "Edit code"
//   3. Replace the editor contents with this entire file
//   4. Click "Save and Deploy"
// The dashboard's editor doesn't sync with this repo — it's a manual
// copy-paste relationship. Keep them in sync when you change either.
// ─────────────────────────────────────────────────────────────────────────

const SUPABASE_URL = "https://sxofvadbeznwgctdzbmk.supabase.co";
// Anon publishable key. Safe to expose — RLS protects writes; reads on
// these tables are intentionally public.
const SUPABASE_KEY = "sb_publishable_j9BUYILtg52cqg0-CnioZQ_iFi5Z0Yx";

const CACHE_TTL_S = 30;

function todayMidnightUTC() {
  const d = new Date();
  d.setUTCHours(0, 0, 0, 0);
  return d.toISOString();
}

async function sbSelect(table, select) {
  const since = todayMidnightUTC();
  const url =
    `${SUPABASE_URL}/rest/v1/${table}` +
    `?select=${encodeURIComponent(select)}` +
    `&created_at=gte.${encodeURIComponent(since)}` +
    `&order=created_at.asc`;
  try {
    const r = await fetch(url, {
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
      },
    });
    if (!r.ok) return null;
    return await r.json();
  } catch (e) {
    return null;
  }
}

async function buildBundle() {
  const [
    messages,
    flares,
    flare_responses,
    message_responses,
    stars,
    star_responses,
  ] = await Promise.all([
    sbSelect("messages", "id,text,lat,lng,loc,mood,created_at,continent,planter_id"),
    sbSelect("flares", "id,text,lat,lng,loc,continent,planter_id,planter_loc,created_at"),
    sbSelect("flare_responses", "id,flare_id,responder_id,text,created_at"),
    sbSelect("message_responses", "id,message_id,responder_id,text,created_at"),
    sbSelect("stars", "id,text,lat,lng,planter_id,created_at"),
    sbSelect("star_responses", "id,star_id,responder_id,text,created_at"),
  ]);
  return {
    messages,
    flares,
    flare_responses,
    message_responses,
    stars,
    star_responses,
  };
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname !== "/loadAll") {
      return new Response("not found", { status: 404 });
    }

    const cache = caches.default;
    const cacheKey = new Request(url.toString(), request);
    const cached = await cache.match(cacheKey);
    if (cached) {
      const r = new Response(cached.body, cached);
      r.headers.set("X-Cache", "HIT");
      return r;
    }

    const bundle = await buildBundle();
    const response = new Response(JSON.stringify(bundle), {
      status: 200,
      headers: {
        "content-type": "application/json",
        "cache-control": `public, max-age=${CACHE_TTL_S}`,
        "access-control-allow-origin": "*",
        "X-Cache": "MISS",
      },
    });
    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};
