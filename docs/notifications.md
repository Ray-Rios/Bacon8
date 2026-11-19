Moved word for word from BACON8.md (§16) on 2026-11-19; BACON8.md keeps a short summary and links here.

## 16. Phone and desktop notifications

Built 2026-11-03 (owner: "our /chat features may need an android/iphone app to help with notifications and
updates"). `Bacon8.Push`, `Bacon8.Push.WebPush`, `Bacon8Web.PushOptIn`, `assets/js/push_opt_in.ts`.

- **What gets pushed:** every notification (`Notifications.create_notification/1`): chat mentions and
  invitations, replies, reports for the admins, announcements. Each person turns it on per device, on
  `/profile?tab=notifications` or from the chat sidebar, and can switch off "Show message text" so a lock
  screen says only that something is new.
- **Where it works:** Chrome, Edge, Firefox and Samsung Internet on Android and computers; iPhone and iPad
  from iOS 16.4 once the site is added to the Home Screen and opened from there (the page says how).
- **How:** the browser subscribes with the site's VAPID public key; the server encrypts each message for
  that device (RFC 8291, tested against the RFC's own example) and signs the request (RFC 8292). The push
  service (Google's, Apple's, Mozilla's, Microsoft's) carries it but can't read it. The server only ever
  calls those services' hosts (a subscription is a URL a browser gives us). Gone devices (404/410) are
  forgotten; five failures in a row drop one; 20 devices a person at most.
- **The worker** is `/push/sw.js` (`PushController`), scope `/push/`: it shows each message (Safari takes
  the permission back from a site whose push shows nothing) and opens the page a notification names, only
  ever a page on this site. Never at `/`, where Bacon World's game worker is.
- **Setting it up:** `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` (`mailto:`) in the
  deployment's secrets. `/admin/notifications` makes a pair (shown once, kept nowhere) or run
  `mix bacon8.gen.vapid` in a container (writes the gitignored `.env.push`). Without them nothing is
  offered or sent. Keep the pair: a new one stops every device until its person turns it on again.
- **`/admin/notifications`:** whether it's on, how many devices and people, a test to your own devices,
  and **announcements** (a title, a line, a page to open; to everyone or only the admins), audited.
- **A native app** (an App Store / Play Store listing) is not needed for notifications. If the owner wants
  one: a Capacitor shell around the site, with its own push through Firebase Cloud Messaging and APNs (a
  server-side sender beside Web Push), an Apple Developer account and a Google Play developer account.

---

