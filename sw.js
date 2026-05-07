// dropadot service worker — Phase 2 PWA support.
//
// Goals:
//   1. Make the home-screen launch feel app-like: the shell loads from
//      cache instantly on second-and-later visits while the network
//      revalidates in the background (stale-while-revalidate).
//   2. Provide a basic offline experience — if the user opens the app
//      with no connection, the shell still paints; live data (dots,
//      flares, casts) just won't update until they reconnect.
//   3. Lay the groundwork for Phase 3 (push notifications), which
//      requires a registered service worker.
//
// Caching scope: same-origin GET requests only. Everything cross-origin
// (Supabase REST, MyMemory translation, the Cloudflare Worker
// /loadAll endpoint, OpenStreetMap tile servers, Google Fonts CDN,
// unpkg.com for Leaflet) is left to the network so that live state
// stays live. Same-origin covers index.html, manifest.json, and the
// /assets/* files — the static app shell.
//
// Updates: the cache is namespaced by CACHE_VERSION. Bumping the
// version invalidates everything on the next activate, so users get
// the new shell on the launch after a deploy. (This is the standard
// PWA "one launch behind" trade-off — instant boot in exchange for
// shell updates lagging by one open. Acceptable here because the
// user-visible content — dots, flares, casts — is fetched fresh on
// every load and not part of the cached shell.)

const CACHE_VERSION = "dropadot-shell-v1";

self.addEventListener("install", (event) => {
  // Take over from any existing SW immediately so the user doesn't have
  // to fully close and reopen the app for the new version to apply.
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    Promise.all([
      // Drop any caches whose name doesn't match the current version so
      // old precaches don't accumulate.
      caches.keys().then((keys) =>
        Promise.all(
          keys
            .filter((k) => k !== CACHE_VERSION)
            .map((k) => caches.delete(k))
        )
      ),
      // Become the controller for any open clients (tabs / installed
      // app windows) so the fetch handler below intercepts their
      // requests right away, not on next page load.
      self.clients.claim()
    ])
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // Only intercept same-origin GETs. Anything cross-origin (Supabase,
  // MyMemory, Cloudflare Worker, OSM tiles, fonts CDN, unpkg, etc.)
  // goes straight to the network — caching those would mask freshness
  // and serve stale dots / wrong tiles.
  if (req.method !== "GET") return;
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    caches.open(CACHE_VERSION).then(async (cache) => {
      const cached = await cache.match(req);
      const networkFetch = fetch(req)
        .then((response) => {
          // Only cache real, non-error, non-opaque responses. `basic`
          // type means same-origin success; opaque (e.g. no-cors) and
          // error responses can't be safely re-served from cache.
          if (response && response.status === 200 && response.type === "basic") {
            cache.put(req, response.clone());
          }
          return response;
        })
        .catch(() => null);

      // Stale-while-revalidate: serve cache instantly if available,
      // otherwise wait on the network. If the network also fails and
      // there's no cache (e.g. very first visit, offline), surface a
      // 503 so the page can show a degraded-mode UI rather than hang.
      return (
        cached ||
        (await networkFetch) ||
        new Response("offline", { status: 503, statusText: "offline" })
      );
    })
  );
});
