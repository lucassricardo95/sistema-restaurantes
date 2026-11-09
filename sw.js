// Painel de Revenda: guarda só a casca para abrir como aplicativo. Dados vêm sempre da rede.
const V = 'revenda-v107';
const CASCA = ['./', 'index.html', 'revenda.css', 'config.js', 'etapas.js', 'revenda.js', 'codigos.js', 'codigos-tela.js', 'icones/icone-192-v2.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(V).then(c => c.addAll(CASCA)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin) return;
  e.respondWith(fetch(e.request).then(r => { const c = r.clone(); caches.open(V).then(x => x.put(e.request, c)); return r; }).catch(() => caches.match(e.request, { ignoreSearch: true }).then(r => r || caches.match('index.html'))));
});
self.addEventListener('push', e => { let d = {}; try{ d = e.data ? e.data.json() : {}; }catch(_){ d = { titulo:'Painel de Revenda', texto:e.data ? e.data.text() : '' }; }
  e.waitUntil(self.registration.showNotification(d.titulo || 'Painel de Revenda', { body:d.texto || '', tag:d.tag || 'painel', icon:'icones/icone-192-v2.png', badge:'icones/badge-96.png', data:{ url:d.url || './' } })); });
self.addEventListener('notificationclick', e => { e.notification.close(); e.waitUntil(self.clients.matchAll({ type:'window', includeUncontrolled:true }).then(L => { for(const c of L){ if('focus' in c) return c.focus(); } return self.clients.openWindow((e.notification.data && e.notification.data.url) || './'); })); });
