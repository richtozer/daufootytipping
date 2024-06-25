'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

<<<<<<< Updated upstream
const RESOURCES = {"flutter_bootstrap.js": "3639daba18878fb364c194a26e5cca00",
"version.json": "50e03e07101daea9e01f1249b8358692",
"index.html": "a91f74097f810a425fb67ffa77702ef7",
"/": "a91f74097f810a425fb67ffa77702ef7",
"main.dart.js": "c48ff6a28d2ef44c3a23dd4f11d58958",
=======
const RESOURCES = {"flutter_bootstrap.js": "42d88073b39240de44bf32a900cad465",
"version.json": "50e03e07101daea9e01f1249b8358692",
"index.html": "a91f74097f810a425fb67ffa77702ef7",
"/": "a91f74097f810a425fb67ffa77702ef7",
"main.dart.js": "cfb6948da20d9c342ca17379e184fe11",
>>>>>>> Stashed changes
"flutter.js": "383e55f7f3cce5be08fcf1f3881f585c",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"manifest.json": "70c669f99d17ca2d91870f4a788a4841",
"assets/dotenv": "b76e4101e708309f93d30e31a8a39a46",
"assets/AssetManifest.json": "00c567574ab6e94369515441484c4408",
"assets/html/recaptcha.html": "0152be5a6a083e295d30c08d282fa981",
"assets/NOTICES": "154f9db91f330a60fadea1e379727edf",
"assets/FontManifest.json": "cab581fd1430c6105f7f7248e5c62e16",
"assets/AssetManifest.bin.json": "ce74f5227ab62a38c6cc23f4c17ff486",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "e14d4247c0221552f79bf5629127cff4",
"assets/packages/firebase_ui_auth/fonts/SocialIcons.ttf": "c6d1e3f66e3ca5b37c7578e6f80f37d8",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "222d721d5038de5e858b9243b068bfa0",
"assets/fonts/MaterialIcons-Regular.otf": "85164015c5d334a9b5fab41051c195dd",
"assets/assets/teams/nrl/Canterbury_colours.svg": "7b206a789b13a6f2151b37292631af03",
"assets/assets/teams/nrl/Melbourne_colours.svg": "21fcead34bcc42f878175d5c6e89a0ef",
"assets/assets/teams/nrl/St._George_colours.svg": "069ee87753a236f83ba3e4503df34066",
"assets/assets/teams/nrl/Parramatta_colours.svg": "ceace1860f17cba6534388eb48a6d584",
"assets/assets/teams/nrl/Newcastle_colours.svg": "e7311b870f55746be42d85a14083c518",
"assets/assets/teams/nrl/Brisbane_colours.svg": "72daec72d49ee33fbf73270ef1a388b9",
"assets/assets/teams/nrl/Dolphins_colours.svg": "5f40958c056191fd5e29c617bd825812",
"assets/assets/teams/nrl/Auckland_colours.svg": "8809ff590458221a69343c736fd8b464",
"assets/assets/teams/nrl/Gold_Coast_Titans_colours.svg": "01e7b599bff45ebdd3e208b69b961252",
"assets/assets/teams/nrl/Penrith_Panthers_square_flag_icon_with_2020_colours.svg": "4ff9542073e832f22e7bd915fa0437ef",
"assets/assets/teams/nrl/Manly_Sea_Eagles_colours.svg": "8e816bd7358a0f5a3a343c0128f36103",
"assets/assets/teams/nrl/Cronulla_colours.svg": "445382821d095a8b0807df6a63c73899",
"assets/assets/teams/nrl/South_Sydney_colours.svg": "aa50a201b9b2b183eab0338cfce1b247",
"assets/assets/teams/nrl/Eastern_Suburbs_colours.svg": "77875a9c55fa3e84dbb07f3e072e9b0b",
"assets/assets/teams/nrl/Wests_Tigers_colours.svg": "301ac7a4b99cb1c409fc27324b467353",
"assets/assets/teams/nrl/Canberra_colours.svg": "1cb7003d6e4ee576fdba76b50d11b136",
"assets/assets/teams/nrl/North_Queensland_colours.svg": "0a84712a94fc3d072acff4808dfefaf0",
"assets/assets/teams/afl/hawks.svg": "1b52a8944ee6d02e98b762a980dee7e8",
"assets/assets/teams/afl/blues.svg": "07c6085581b0b2a98133ec182c5a3b8a",
"assets/assets/teams/afl/kagaroos.svg": "de47a81620f9b67b1af72577ecebe4dd",
"assets/assets/teams/afl/suns.svg": "a919265cca4e170f28cb231c5725a293",
"assets/assets/teams/afl/cats.svg": "9b927687b76d124d5ac1fbe55af423a7",
"assets/assets/teams/afl/power.svg": "31facd2422179e5225ad5db83d9ccc82",
"assets/assets/teams/afl/lions.svg": "a8c46f52dea92f8db79e9b1f479fabe3",
"assets/assets/teams/afl/crows.svg": "89ab99242b02108c74802abd4ec5ff77",
"assets/assets/teams/afl/tigers.svg": "a8d6e1ca53d55610b598ed85c9c81660",
"assets/assets/teams/afl/demons.svg": "a4105423f95e9057359259a9a785f977",
"assets/assets/teams/afl/giants.svg": "84fb7627dbe84f1bc93c6278d92cfea5",
"assets/assets/teams/afl/bulldogs.svg": "4cab3e27c3235157befd1e4716228c92",
"assets/assets/teams/afl/bombers.svg": "22838d97dcc8f18042ed0eb0cfba3486",
"assets/assets/teams/afl/swans.svg": "98aa62460ac91a4aca7648894ace257c",
"assets/assets/teams/afl/eagles.svg": "0ac5a8cfb39f68e245556f8abdeb7e88",
"assets/assets/teams/afl/magpies.svg": "1bd0a7f2b939bad49584f66c19e1599f",
"assets/assets/teams/afl/saints.svg": "87bb5e2355df04c78e26fc41a8ee3bf5",
"assets/assets/teams/afl/dockers.svg": "1af624e561f6c03b485cfb9c25c606d8",
"assets/assets/teams/afl.svg": "fa3763509d78006af047fa41c2118e9e",
"assets/assets/teams/daulogo.jpg": "1a2e786c985e06f80cf246d225b6b0be",
"assets/assets/teams/daulogo-grass.jpg": "6eb217cf68f191e3dd140e3b5e665f90",
"assets/assets/teams/nrl.svg": "d9bd1e04069b08a27c18ac8732789b8b",
"assets/assets/icon/AppIcon.png": "cad55d77023a8e3a3b430b978fc46aa9",
"canvaskit/skwasm.js": "5d4f9263ec93efeb022bb14a3881d240",
"canvaskit/skwasm.js.symbols": "c3c05bd50bdf59da8626bbe446ce65a3",
"canvaskit/canvaskit.js.symbols": "74a84c23f5ada42fe063514c587968c6",
"canvaskit/skwasm.wasm": "4051bfc27ba29bf420d17aa0c3a98bce",
"canvaskit/chromium/canvaskit.js.symbols": "ee7e331f7f5bbf5ec937737542112372",
"canvaskit/chromium/canvaskit.js": "901bb9e28fac643b7da75ecfd3339f3f",
"canvaskit/chromium/canvaskit.wasm": "399e2344480862e2dfa26f12fa5891d7",
"canvaskit/canvaskit.js": "738255d00768497e86aa4ca510cce1e1",
"canvaskit/canvaskit.wasm": "9251bb81ae8464c4df3b072f84aa969b",
"canvaskit/skwasm.worker.js": "bfb704a6c714a75da9ef320991e88b03"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
