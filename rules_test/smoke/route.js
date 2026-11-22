async page => {
  // The Flutter web plugin loads the Firebase JS SDK from Google's CDN, which the OS boundary refuses.
  // Fulfil those requests from the locally installed copy of the SAME version (served on loopback by
  // up.sh). The app chooses its own SDK version; nothing here overrides it. A request for any other
  // version than the one served is aborted and reported, so the app can never silently run against an
  // SDK it was not released with (and the bundles, which import firebase-app.js by its versioned URL,
  // always share one copy of the app module).
  const local = await (await page.request.get('http://127.0.0.1:18091/package.json')).json();
  const served = new Set();
  const refused = new Set();
  await page.context().route(/^https:\/\/www\.gstatic\.com\/firebasejs\/[\d.]+\/[\w.-]+\.js$/, async (route) => {
    const parts = route.request().url().split('/');
    const name = parts.pop();
    const requested = parts.pop();
    if (requested !== local.version) {
      refused.add(requested);
      await route.abort();
      return;
    }
    served.add(requested);
    const upstream = await route.fetch({ url: 'http://127.0.0.1:18091/' + name });
    await route.fulfill({ response: upstream, headers: { ...upstream.headers(), 'access-control-allow-origin': '*', 'content-type': 'text/javascript' } });
  });
  await page.goto('http://127.0.0.1:18090/');
  await page.waitForTimeout(8000);
  if (refused.size > 0) return 'SDK-MISMATCH app requested ' + [...refused].join(',') + ' but ' + local.version + ' is served';
  if (served.size === 0) return 'SDK-NOT-LOADED the app requested no Firebase JS SDK files';
  return 'routed firebase-js-sdk=' + [...served].join(',');
}
