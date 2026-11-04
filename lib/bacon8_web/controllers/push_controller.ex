defmodule Bacon8Web.PushController do
  @moduledoc """
  GET /push/sw.js - the service worker that shows push notifications (`Bacon8.Push`).

  It lives in /push/ so its scope is /push/: it controls no pages, caches nothing and never meets
  Bacon World's game worker (/sw-game.js, scope /). It does two things: show each message that
  arrives (a push that shows nothing makes Safari take the permission back), and open or focus
  the page a notification names when it's tapped, only ever a page on this site.
  """
  use Bacon8Web, :controller

  @worker ~S"""
  // Bacon8 notifications (Bacon8.Push, served by Bacon8Web.PushController). Scope /push/.
  self.addEventListener('install', () => self.skipWaiting());
  self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

  function safePath(u) {
    return typeof u === 'string' && u.charAt(0) === '/' && u.charAt(1) !== '/' && u.indexOf('\\') < 0 ? u : '/';
  }

  self.addEventListener('push', (event) => {
    let data = {};
    try {
      data = event.data ? event.data.json() : {};
    } catch (e) {
      data = { body: event.data ? event.data.text() : '' };
    }
    const title = typeof data.title === 'string' && data.title ? data.title : 'Bacon8';
    const options = {
      body: typeof data.body === 'string' ? data.body : '',
      icon: '/images/icon-192.png',
      data: { url: safePath(data.url) },
    };
    if (typeof data.tag === 'string' && data.tag) {
      options.tag = data.tag;
      options.renotify = true;
    }
    event.waitUntil(self.registration.showNotification(title, options));
  });

  self.addEventListener('notificationclick', (event) => {
    event.notification.close();
    const path = safePath(event.notification.data && event.notification.data.url);
    const url = new URL(path, self.location.origin).href;
    event.waitUntil((async () => {
      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const w of windows) {
        if (w.url === url && 'focus' in w) return w.focus();
      }
      return self.clients.openWindow(url);
    })());
  });
  """

  def service_worker(conn, _params) do
    conn
    |> put_resp_content_type("text/javascript")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, @worker)
  end
end
