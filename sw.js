/* Kontivo – Offline-Cache. Bei jeder neuen Version VERSION erhöhen. */
var VERSION="kontivo-v22";
var CORE=["./","index.html","manifest.webmanifest","apple-touch-icon.png","icon-192.png","icon-512.png",
  "onb/list-light.webp","onb/list-dark.webp","onb/stat-light.webp","onb/stat-dark.webp","onb/budget-light.webp","onb/budget-dark.webp","onb/term-light.webp","onb/term-dark.webp"];
self.addEventListener("install",function(e){
  e.waitUntil(caches.open(VERSION).then(function(c){return c.addAll(CORE);}).then(function(){return self.skipWaiting();}));
});
self.addEventListener("activate",function(e){
  e.waitUntil(caches.keys().then(function(ks){return Promise.all(ks.filter(function(k){return k!==VERSION;}).map(function(k){return caches.delete(k);}));})
    .then(function(){return self.clients.claim();}));
});
self.addEventListener("fetch",function(e){
  var req=e.request;if(req.method!=="GET")return;
  var url=new URL(req.url);
  /* App selbst: zuerst Netz (Updates sofort), offline aus dem Cache */
  if(url.origin===self.location.origin){
    /* no-cache: immer beim Server nachfragen (GitHub Pages erlaubt sonst 10 Min. alten Stand) */
    e.respondWith(fetch(url.href,{cache:"no-cache",credentials:"same-origin"}).then(function(r){
      if(r&&r.ok){var cp=r.clone();caches.open(VERSION).then(function(c){c.put(req,cp);});}
      return r;
    }).catch(function(){return caches.match(req,{ignoreSearch:true}).then(function(m){return m||caches.match("index.html");});}));
    return;
  }
  /* Schrift und PDF-Anzeige: aus dem Cache, im Hintergrund auffrischen */
  if(/fonts\.googleapis\.com|fonts\.gstatic\.com|cdnjs\.cloudflare\.com/.test(url.hostname)){
    e.respondWith(caches.open(VERSION+"-ext").then(function(c){return c.match(req).then(function(m){
      var net=fetch(req).then(function(r){if(r&&(r.ok||r.type==="opaque"))c.put(req,r.clone());return r;}).catch(function(){return m;});
      return m||net;});}));
  }
});
