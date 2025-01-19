'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"favicon-16x16.png": "fc0547c8f56b318fadb90b8a80d802f1",
"flutter_bootstrap.js": "ff4338cd6acb756fd44b7ec65eb0ddf4",
"version.json": "21a5fbe2a2eefc35afb450fb0eefd02c",
"favicon.ico": "3cacd96b6d602ce42ee0973d40622006",
"index.html": "f7d86b8b04a6a414418a15c58c089c7b",
"/": "f7d86b8b04a6a414418a15c58c089c7b",
"android-chrome-192x192.png": "5b565d54e84b474e7f26472e86d34fac",
"apple-touch-icon.png": "d2a9efde36fb5541fd60670fe6e0e8e0",
"main.dart.js": "8fdaf26ee484676fa0cf8dd8298f6280",
"flutter.js": "4b2350e14c6650ba82871f60906437ea",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"android-chrome-512x512.png": "81c63be219c5723a568b10bc5c8d27d3",
"site.webmanifest": "053100cb84a50d2ae7f5492f7dd7f25e",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"manifest.json": "70c669f99d17ca2d91870f4a788a4841",
"assets/dotenv": "077c0fa84b942af047f6e2ddd6d1d942",
"assets/AssetManifest.json": "ce6f3671be852b5d347caf0dea2da348",
"assets/html/recaptcha.html": "0152be5a6a083e295d30c08d282fa981",
"assets/NOTICES": "cfe0b92b42fadf54e9fcf6d29f5938aa",
"assets/FontManifest.json": "cab581fd1430c6105f7f7248e5c62e16",
"assets/AssetManifest.bin.json": "fe8ca2f6032c59363df342b4d04c63e1",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "94495392187d1e926a41d1bf06061cf5",
"assets/packages/firebase_ui_auth/fonts/SocialIcons.ttf": "c6d1e3f66e3ca5b37c7578e6f80f37d8",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "10642ed00bfe45cd6922542ae6d4ef3b",
"assets/fonts/MaterialIcons-Regular.otf": "11e32330da598461dc9acf9daa115f9a",
"assets/assets/teams/nrl/Canterbury_colours.svg": "53d04547852f1a5b45f508edfda87f8d",
"assets/assets/teams/nrl/Melbourne_colours.svg": "59c66275a722b6248b63f361c0126212",
"assets/assets/teams/nrl/St._George_colours.svg": "4d303e7b59daf0a8cfe5c07ee97ed741",
"assets/assets/teams/nrl/Parramatta_colours.svg": "7f8b10e2e86ea221f7096fcdf6b1aae5",
"assets/assets/teams/nrl/Newcastle_colours.svg": "f48cf12689bf7ed39d3fe47ac74c28e6",
"assets/assets/teams/nrl/Brisbane_colours.svg": "2cc6be7f4908f550f33830bdeeba6859",
"assets/assets/teams/nrl/Dolphins_colours.svg": "a9c059440b5cefb20523f17574d4415f",
"assets/assets/teams/nrl/Auckland_colours.svg": "b9f8d9001816204c2abf43338cdbb238",
"assets/assets/teams/nrl/Gold_Coast_Titans_colours.svg": "5bab294168acce725d2a976c896b1e87",
"assets/assets/teams/nrl/Penrith_Panthers_square_flag_icon_with_2020_colours.svg": "510e6d3dbd8a756d3e753a255237dc96",
"assets/assets/teams/nrl/Manly_Sea_Eagles_colours.svg": "ca232419747f12c79b51563b1ff25832",
"assets/assets/teams/nrl/Cronulla_colours.svg": "49f8c0cd81e5b5fd843f7818765ee1f0",
"assets/assets/teams/nrl/South_Sydney_colours.svg": "7784c5df70404f2d55d428737c23da2a",
"assets/assets/teams/nrl/Eastern_Suburbs_colours.svg": "965513c21c9c51095426df8a40603e0f",
"assets/assets/teams/nrl/Wests_Tigers_colours.svg": "7abf2372adb044d945f7a9e38ce8b384",
"assets/assets/teams/nrl/Canberra_colours.svg": "e5eca6c56a191538081cce604d02f805",
"assets/assets/teams/nrl/North_Queensland_colours.svg": "5bd6ea83972b4cec69582b044151d2ce",
"assets/assets/teams/afl/hawks.svg": "6dd45508ca9edf671c98cdfc8107c419",
"assets/assets/teams/afl/blues.svg": "80ea1cc305f9d735442622cd20f8be10",
"assets/assets/teams/afl/kagaroos.svg": "1da4742772d3fb735643568d953e3cf5",
"assets/assets/teams/afl/suns.svg": "a919265cca4e170f28cb231c5725a293",
"assets/assets/teams/afl/cats.svg": "aa8304bdf83c2b729bc63c9cbbcd8e7b",
"assets/assets/teams/afl/power.svg": "1da3f0367f9a9bfeb0bbb3a03334ed18",
"assets/assets/teams/afl/lions.svg": "e206f869a854e86f0a05af97bce29f0a",
"assets/assets/teams/afl/crows.svg": "bce78966d2e28511941bbf122abd8dee",
"assets/assets/teams/afl/tigers.svg": "eb03dc26ce200b392d86910a46b5c277",
"assets/assets/teams/afl/demons.svg": "a4105423f95e9057359259a9a785f977",
"assets/assets/teams/afl/giants.svg": "40d099be59614631df434285b7f771b0",
"assets/assets/teams/afl/power-old.svg": "31facd2422179e5225ad5db83d9ccc82",
"assets/assets/teams/afl/bulldogs.svg": "0b2b509fa2ddc160841f98599a519351",
"assets/assets/teams/afl/bombers.svg": "c2a78e6cb55e2a7bc4b34b1e4ddd53ae",
"assets/assets/teams/afl/swans.svg": "9ca9c3e9a0e009d0af2d861dfe030613",
"assets/assets/teams/afl/eagles.svg": "905a86dfd14dd0b848f857bc423cddae",
"assets/assets/teams/afl/magpies.svg": "7631482f2ba721d010aaa14b1abdaf4e",
"assets/assets/teams/afl/saints.svg": "4cfc51108281531f98ec3b47b0020822",
"assets/assets/teams/afl/dockers.svg": "7a786474382d5625458f0e5d4008a271",
"assets/assets/teams/afl.svg": "fa3763509d78006af047fa41c2118e9e",
"assets/assets/teams/grass%2520with%2520scoreboard.png": "86bf722a742e86eb131a53c40d97d40a",
"assets/assets/teams/grass%2520for%2520dau%2520app.png": "bb58974db6b3f8525e26d0ff1f19047c",
"assets/assets/teams/epl.svg": "8eb528250fe884940ce4419cba7f839b",
"assets/assets/teams/daulogo.jpg": "1a2e786c985e06f80cf246d225b6b0be",
"assets/assets/teams/daulogo-grass.jpg": "6eb217cf68f191e3dd140e3b5e665f90",
"assets/assets/teams/nrl.svg": "d9bd1e04069b08a27c18ac8732789b8b",
"assets/assets/icon/AppIcon.png": "cad55d77023a8e3a3b430b978fc46aa9",
"favicon-32x32.png": "4e8e4916553cf7f1df4553d2cdc45ae6",
"canvaskit/skwasm.js": "ac0f73826b925320a1e9b0d3fd7da61c",
"canvaskit/skwasm.js.symbols": "96263e00e3c9bd9cd878ead867c04f3c",
"canvaskit/canvaskit.js.symbols": "efc2cd87d1ff6c586b7d4c7083063a40",
"canvaskit/skwasm.wasm": "828c26a0b1cc8eb1adacbdd0c5e8bcfa",
"canvaskit/chromium/canvaskit.js.symbols": "e115ddcfad5f5b98a90e389433606502",
"canvaskit/chromium/canvaskit.js": "b7ba6d908089f706772b2007c37e6da4",
"canvaskit/chromium/canvaskit.wasm": "ea5ab288728f7200f398f60089048b48",
"canvaskit/canvaskit.js": "26eef3024dbc64886b7f48e1b6fb05cf",
"canvaskit/canvaskit.wasm": "e7602c687313cfac5f495c5eac2fb324",
"canvaskit/skwasm.worker.js": "89990e8c92bcb123999aa81f7e203b1c"};
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
