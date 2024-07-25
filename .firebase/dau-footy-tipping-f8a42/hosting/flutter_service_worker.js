'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"favicon-16x16.png": "fc0547c8f56b318fadb90b8a80d802f1",
"flutter_bootstrap.js": "eab76dc64273587943861475588178ef",
"version.json": "7ef0a56aa877c3fb330ccbbc5cc6540e",
"favicon.ico": "3cacd96b6d602ce42ee0973d40622006",
"index.html": "f7d86b8b04a6a414418a15c58c089c7b",
"/": "f7d86b8b04a6a414418a15c58c089c7b",
"android-chrome-192x192.png": "5b565d54e84b474e7f26472e86d34fac",
"apple-touch-icon.png": "d2a9efde36fb5541fd60670fe6e0e8e0",
"main.dart.js": "caf661c4ecc2cc1ad9bfc61de38e78ee",
"flutter.js": "383e55f7f3cce5be08fcf1f3881f585c",
"android-chrome-512x512.png": "81c63be219c5723a568b10bc5c8d27d3",
"site.webmanifest": "053100cb84a50d2ae7f5492f7dd7f25e",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"manifest.json": "70c669f99d17ca2d91870f4a788a4841",
"assets/dotenv": "b76e4101e708309f93d30e31a8a39a46",
"assets/AssetManifest.json": "3284e6b3a82eb1bb0fcb8f51eba4dd1d",
"assets/html/recaptcha.html": "0152be5a6a083e295d30c08d282fa981",
"assets/NOTICES": "154f9db91f330a60fadea1e379727edf",
"assets/FontManifest.json": "cab581fd1430c6105f7f7248e5c62e16",
"assets/AssetManifest.bin.json": "f6b5393023238775ec9078be43e0a5b6",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "e14d4247c0221552f79bf5629127cff4",
"assets/packages/firebase_ui_auth/fonts/SocialIcons.ttf": "c6d1e3f66e3ca5b37c7578e6f80f37d8",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "df36584fc04e4cb59ddec577f25510b7",
"assets/fonts/MaterialIcons-Regular.otf": "edcd8f666778ae02cfb48bbcbc25c8e7",
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
"assets/assets/teams/daulogo.jpg": "1a2e786c985e06f80cf246d225b6b0be",
"assets/assets/teams/daulogo-grass.jpg": "6eb217cf68f191e3dd140e3b5e665f90",
"assets/assets/teams/nrl.svg": "d9bd1e04069b08a27c18ac8732789b8b",
"assets/assets/icon/AppIcon.png": "cad55d77023a8e3a3b430b978fc46aa9",
"favicon-32x32.png": "4e8e4916553cf7f1df4553d2cdc45ae6",
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
