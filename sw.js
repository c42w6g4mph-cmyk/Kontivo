/* Kontivo – Offline-Cache. Bei jeder neuen Version VERSION erhöhen. */
var VERSION="kontivo-v155";
var CORE=["./","index.html","manifest.webmanifest","apple-touch-icon.png","icon-192.png","icon-512.png",
  "onb/list-light.webp","onb/list-dark.webp","onb/stat-light.webp","onb/stat-dark.webp","onb/budget-light.webp","onb/budget-dark.webp","onb/term-light.webp","onb/term-dark.webp",
  "fonts/Hurricane-Regular.ttf","fonts/LaBelleAurore.ttf","fonts/Licorice-Regular.ttf","fonts/Zeyada.ttf","fonts/Qwigley-Regular.ttf","fonts/Bilbo-Regular.ttf"];
self.addEventListener("install",function(e){
  e.waitUntil(caches.open(VERSION).then(function(c){return c.addAll(CORE.map(function(u){return new Request(u,{cache:"no-cache"});}));}).then(function(){return self.skipWaiting();}));
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
    var put=null;
    var net=fetch(url.href,{cache:"no-cache",credentials:"same-origin"}).then(function(r){
      if(r&&r.ok){var cp=r.clone();put=caches.open(VERSION).then(function(c){return c.put(req,cp);});}
      return r;
    });
    var cached=function(){return caches.match(req,{ignoreSearch:true}).then(function(m){return m||caches.match("index.html");});};
    if(req.mode==="navigate"||/\/(index\.html)?$/.test(url.pathname)){
      /* App-Start: höchstens 3 s aufs Netz warten, dann Cache; bei HTTP-Fehler Cache, falls vorhanden.
         Die Netzantwort aktualisiert den Cache im Hintergrund weiter (waitUntil). */
      var limit=new Promise(function(res){setTimeout(function(){res(null);},3000);});
      e.respondWith(Promise.race([net.catch(function(){return null;}),limit]).then(function(r){
        if(r&&r.ok)return r;
        return cached().then(function(m){return m||r||net;});
      }));
      e.waitUntil(net.then(function(){return put;}).catch(function(){}));
    }
    else e.respondWith(net.catch(cached));
    return;
  }
  /* Schrift und PDF-Anzeige: aus dem Cache, im Hintergrund auffrischen */
  if(/fonts\.googleapis\.com|fonts\.gstatic\.com|cdnjs\.cloudflare\.com/.test(url.hostname)){
    e.respondWith(caches.open(VERSION+"-ext").then(function(c){return c.match(req).then(function(m){
      var net=fetch(req).then(function(r){if(r&&(r.ok||r.type==="opaque"))c.put(req,r.clone());return r;}).catch(function(){return m;});
      return m||net;});}));
  }
});
