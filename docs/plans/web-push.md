# Web Push for the browser console

Status: approved 2026-10-22, open questions settled as recommended. It
builds on the installable PWA in #2206 (`claude/pwa-support-5b8cd3`).

Goal: an installed console on a phone shows a notification while the app is
closed in three cases:

- a run on one of the account's desktops finishes;
- a run on a desktop stops to ask for permission;
- a Cloud Agents turn finishes (§4).

This must work on Android Chrome and on iOS 16.4+ after Add to Home Screen.

## Facts that shape the design

- **The relay sees no notification events today.** `serve_browser` splices
  browser and host sockets without parsing them, and the host sends nothing
  on the `/v1/tunnel` control socket after `register`. When the phone app is
  closed, no browser stream exists at all. So the host has to tell the relay
  through a new control frame.
- **The window frontend decides notifications, not the host.**
  `frontend/system_notification.mbt` posts a banner for (a) the first
  `Finished` of a run whose status is not `cancelled`, and (b) a live
  `ApprovalRequested`. Recovered approvals never post. The host hub already
  has both facts: `Hub::record_finished` dedupes settlements, and
  `pending_approvals` / `message_approvals` hold live questions.
- **openseek-api has no P-256.** Its dependencies give SHA-256, HMAC and AES
  (ECB/CBC). Web Push needs ECDSA P-256 for VAPID (RFC 8292), and ECDH P-256
  plus AES-128-GCM for payload encryption (RFC 8291). `moonbitlang/async`
  already `dlopen`s `libssl.so.3` at runtime. The runtime image has it through
  `ca-certificates → openssl`.
- **Both console credentials are rows in `sessions`.** That covers the relay
  cookie and the v2 account bearer that the proxy and Android use.
  `SessionTtl` slides on use (7 days).

## 1. Where the worker is served

**Decision: `sw.js` at the bundle root, next to `index.html`, served at
`/sw.js`.** A script at `/sw.js` gets scope `/` by default, which covers
`/cloud/...` and `/device/...`. No `Service-Worker-Allowed` header is needed.
The alternative was `/assets/sw.js` plus that header, which would change
static serving in all three hosts. With the root location, two of the three
hosts need no code at all.

- Source: `desktop/pwa/sw.js`. `Build.stageFrontend` copies it to
  `<output>/sw.js`, not into `assets/`.
- **openseek-api** (`register_browser_release_routes`): add
  `GET /sw.js`. It streams `<current release>/sw.js` with
  `Content-Type: text/javascript` and `Cache-Control: no-cache`. A release
  without the file returns 404, so registration fails and the console shows
  push as unavailable. The route is registered before the homepage
  `/*rest` wildcard, as `/assets/*file` already is.
- **Local console** (`remote/local.mbt`): no change. `static_asset_route`
  already maps `/sw.js` to the root file, and `content_type` returns JS. Add a
  route test so this stays true.
- **Console proxy**: no change. The `@unstable_static` middleware serves the
  bundle root. Add a test in `console_proxy_test.mbt`. Its `/v2/*` forwarding
  also carries the push API to the relay, so the proxy can test real pushes
  (Android over `chrome://inspect` port forwarding runs on `localhost`, which
  is a secure context). `--demo` answers `/v2/push/key` with its usual 503,
  which the page treats like 404.

The worker only handles push. It has no `fetch` handler and no caching:

- `push`: decode the JSON payload, then call
  `showNotification(title, {body, tag, data: {url}, icon})` inside
  `waitUntil`. It always shows something, because iOS revokes the
  subscription after silent pushes.
- `notificationclick`: focus an open client and navigate it to `data.url`,
  or `clients.openWindow(url)`.
- `install` / `activate`: call `skipWaiting` and `clients.claim`.
- `pushsubscriptionchange` is ignored. The page heals subscriptions on every
  boot (see §2).

**Text formatting lives in the worker.** The host has no locale (it is a
frontend setting), and openseek-api has no i18n. The payload is structured
(§3). `sw.js` holds the same strings `system_notification.mbt` uses: the
three finish titles, the fallback body and the approval title/body in five
locales. It picks them by the `locale` stored with the subscription. That
duplication is the cost; the alternative is i18n in openseek-api.

## 2. Frontend

- **Registration:** only when `!model.is_desktop` (no bridge), once a
  browser account loads, and only when `navigator.serviceWorker`,
  `PushManager` and `Notification` all exist. It registers `/sw.js`, whose
  default scope is `/`. The Proton window never registers.
- **UI:** a browser-only notifications row in the sidebar's account area,
  above the sign-in row. The browser console has no Settings page.
  `frontend/web_push` owns the state machine, which is its blackbox-tested
  contract:
  - `Unsupported`: no Push API. On iOS Safari this means "not installed", and
    the row says to add the app to the Home Screen.
  - `Unavailable`: `GET /v2/push/key` answers anything but 200 (relay not
    configured, local console, proxy `--demo`, or unreachable). The row is
    hidden until the next page load.
  - `Off`: Turn on.
  - `Working`: prompt, subscribe, unsubscribe or test in flight.
  - `On`: Test, and Turn off.
  - `Blocked`: permission denied; points at browser settings.
- **Turn on** (user gesture): `Notification.requestPermission()` runs first,
  before anything waits. Then `pushManager.subscribe({userVisibleOnly: true,
  applicationServerKey})` on the ready registration, then
  `PUT /v2/push/subscription`. A dismissed prompt returns to `Off`.
- **Heal on boot:** when permission is `granted` and
  `pushManager.getSubscription()` returns one, the page sends the same
  `PUT` again. The upsert re-binds the row to the current session and locale,
  and it re-creates a row the relay pruned.
- **Turn off:** `DELETE /v2/push/subscription`, then `unsubscribe()`.
- **Sign out:** an explicit sign-out calls `unsubscribe()`. The relay row
  already went with the session (the cascade in §3). An expired sign-in
  keeps the browser subscription, so signing in again heals it and pushes
  resume.
- The relay calls use the console's account Bearer, like its other `/v2`
  calls.

## 3. openseek-api

### Config

`UserSystemConfig` gains `web_push : WebPushConfig?`:

- `WEB_PUSH_VAPID_PRIVATE_KEY`: base64url of the raw 32-byte P-256 scalar.
  This is the format `web-push generate-vapid-keys` prints. The public key is
  derived at startup, which also validates the key and fails fast.
- `WEB_PUSH_SUBJECT`: a `mailto:` or `https:` contact. Apple rejects pushes
  without one.

Neither variable set means push is disabled (`None`). Exactly one set is a
startup error. `npx web-push generate-vapid-keys` prints a key in this
form for `deploy/.env`.

### Data model

```sql
CREATE TABLE IF NOT EXISTS push_subscriptions (
    endpoint        TEXT PRIMARY KEY,
    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_hash    TEXT NOT NULL REFERENCES sessions(token_hash) ON DELETE CASCADE,
    p256dh          TEXT NOT NULL,   -- base64url, 65-byte uncompressed point
    auth            TEXT NOT NULL,   -- base64url, 16 bytes
    locale          TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_success_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user ON push_subscriptions(user_id);
```

- **One row per browser installation**, keyed by its push endpoint. A row
  belongs to an account, and every host device of that account fans out to
  it. Per-host muting can be a later column. It is not in v1.
- **The row is bound to the session that created it.** Sign-out deletes the
  session, and the cascade deletes the row. So a signed-out or shared browser
  stops receiving pushes even if its page never ran the `DELETE`.
  - The cost: an installation that goes unused for longer than `SessionTtl`
    (7 days) stops receiving pushes until it is opened again, and the boot
    heal then re-binds it. **Open question 1.**

### Routes

All routes use v2 account auth (`account_user`). Cookie requests get the
existing `cookie_origin_allowed` check.

| Route | Result |
| --- | --- |
| `GET /v2/push/key` | `{public_key}` (base64url, 65 bytes), or 404 when push is disabled. No auth needed. |
| `PUT /v2/push/subscription` | Body `{endpoint, keys:{p256dh, auth}, locale}`. Upsert by endpoint into this user and session. Returns 204. |
| `DELETE /v2/push/subscription` | Body `{endpoint}`. Deletes only the caller's own row. Returns 204. |
| `POST /v2/push/test` | Body `{endpoint}`. Sends a test push to the caller's own row and reports the push service's answer: 202 accepted, 410 gone (the row is pruned), 502 refused. This supports the real-device acceptance check. |

**The endpoint must be `https://` on an allowlisted push-service host.**
Otherwise the relay would POST to any URL a signed-in user names, which is
an SSRF into the deployment network. The allowlist:

- `fcm.googleapis.com`
- `updates.push.services.mozilla.com`
- `web.push.apple.com`
- `*.notify.windows.com`
- `*.push.apple.com`

`p256dh` must decode to 65 bytes starting with `0x04`, and `auth` to 16 bytes,
or the route answers 400. Without that check, encryption would fail later on
every fan-out.

### Host → relay: the `notify` control frame

A new tunnel frame from host to relay. It goes into `desktop/backend/tunnel`,
its verbatim copy `tunnel_frame.mbt`, and the control-frame table in
`docs/remote-protocol.md`:

```json
{"type":"notify","event":{"kind":"finished","session":"…","status":"finished","answer":"…"}}
{"type":"notify","event":{"kind":"approval","session":"…","tool":"mbtx","detail":"…"}}
```

- **Compatible in both directions, with no revision bump.** Today's relay
  already reads and drops whatever the host sends after `register`, so a new
  host on an old relay is a no-op. A new relay with an old host sends nothing.
- **Host side** (`remote/connect.mbt`): while registered, `connect_once`
  subscribes to the hub. It maps the same two triggers the window uses to
  `Notify`:
  - the first settlement of a top-level run with a status other than
    `cancelled`;
  - a live approval request, never a recovered one.
  - `answer` and `detail` are cut to the window's 180-character banner limit.
  - The WebSocket serializes its own writes, so these frames never
    interleave with pings.
  - The notifier is seeded from `agent.runs` in the same turn it
    subscribes. Approvals standing at connect time are never announced, so a
    reconnect does not push them again; runs already in flight still push.
  - A frame raised while the tunnel is down is dropped. Delivery is best
    effort, like the banner.
- **Relay side** (`serve_control`): the reader loop that now drops messages
  decodes them instead, with the existing bounded reader and an 8 KiB limit.
  It ignores anything other than `notify`, and hands a `notify` to the push
  sender through a bounded queue (`try_put`; a full queue logs and drops).
  The control reader therefore never waits on push services.

**The payload carries the answer excerpt and the approval detail, the same
text the desktop banner shows.** The relay already terminates TLS on both
splice legs, so this does not widen what the relay operator can see. Push
services see only ciphertext (RFC 8291). The relay never logs payloads.
**Open question 2.**

### Fan-out (`webpush/` package)

For each `notify` from device `d` of user `u`, the relay sends to every
subscription of `u`, with bounded concurrency and a 10 s timeout per send:

- **Payload:** the event plus `{v:1, device, device_name, url, locale}`, where
  `url = /device/<d>/chat/session/<session>`. The relay knows `d` from the
  control session, so the host does not compose URLs. The payload stays
  under 3 KiB.
- **Encryption:** RFC 8291 `aes128gcm` with one record, a fresh ephemeral
  ECDH key and a fresh salt.
- **VAPID:** an ES256 JWT with `aud` = the endpoint origin, `exp` = now + 12 h,
  and `sub` from config, cached per audience. Header
  `Authorization: vapid t=…, k=…`.
- **Headers:**
  - `TTL: 86400`.
  - `Urgency: high` for approval, `normal` for finished.
  - `Topic`: a hash of the session, so undelivered pushes for one
    conversation collapse.
- **Responses:**
  - 201: set `last_success_at`.
  - 404 / 410: delete the row.
  - 400 / 413: log.
  - 429 / 5xx: log. No retry in v1.

**Payload contract** (relay → worker; the plaintext before RFC 8291
encryption). `sw.js` in openseek and the sender in openseek-api must agree
on this shape:

```json
{"v":1,"kind":"finished","locale":"zh-Hans","url":"/device/d_1/chat/session/s1",
 "device_name":"MacBook","status":"finished","answer":"…"}
{"v":1,"kind":"approval","locale":"en","url":"/device/d_1/chat/session/s1",
 "device_name":"MacBook","tool":"mbtx","detail":"…"}
{"v":1,"kind":"cloud_finished","locale":"en","url":"/cloud/session/c1",
 "status":"completed","answer":"…"}
{"v":1,"kind":"test","locale":"en","url":"/cloud"}
```

- `locale` is the subscription's stored tag, one of the `@i18n.Locale::tag`
  values: `en`, `zh-Hans`, `zh-Hant`, `ja`, `es`. The worker falls back to
  `en` for anything else.
- `url` is a root-relative application path. The worker resolves it against
  its own origin.
- `answer` is optional. Without it the worker uses the fallback body.
- `status` is the host's run status for `finished`: `finished`,
  `max_steps_exhausted`, or anything else, which reads as failed. For
  `cloud_finished` it is Cloud's `completed` or `failed`.
- The worker uses the url as the notification `tag`, so a newer push about
  the same conversation replaces the older one.
- A payload the worker cannot parse still shows a generic "SeekMoon"
  notification. iOS revokes subscriptions whose pushes show nothing.

**Crypto:** a small C stub `dlopen`s libcrypto the way async's loader does
(`libcrypto.so.3`, falling back to the macOS LibreSSL dylib). It exposes:

- P-256 public key from a scalar
- ephemeral keypair
- ECDSA sign, returning raw `r‖s`
- ECDH
- ECDSA verify, for tests

It uses the `EC_KEY` / `ECDSA_do_sign` / `ECDH_compute_key` APIs, which
both OpenSSL 3 and LibreSSL export. HKDF and the record framing are MoonBit
on top of `@crypto.hmac`. AES-128-GCM is also MoonBit: counter mode and
GHASH over `@crypto.aes_ecb_encrypt`, because macOS LibreSSL 3.3 refuses
EVP AES-GCM. Tests:

- the RFC 8291 §5 vector reproduces byte for byte, which also pins the GCM;
- a VAPID JWT verifies against the derived key;
- delivery and 404/410 classification against a fake `post`, since the
  endpoint allowlist admits only real push services.

Writing P-256 in MoonBit was rejected: it is a correctness and side-channel
risk for no gain.

## 4. Cloud Agents

Cloud turns never pass through a desktop host or the tunnel, so the `notify`
frame cannot see them. Yet this is the case where push matters most: the
user starts a task from the phone, closes the app, and Cloud is the only
place that knows when it ends.

Facts from `moonbitlang/cloud-agents`, a Rust service maintained outside this
repo:

- **A turn outlives its client.** `start` runs the turn in a detached
  `tokio::spawn` (`src/task.rs`), so closing the app does not stop it.
- **One place records the end.** The spawned task calls
  `store.finish(session, task, outcome)` and then emits `task_finished`.
  `outcome.status` is `completed` or `failed`. Cloud has no approvals and no
  cancellation yet, so a turn's end is its only push trigger.
- **Same account as the relay.** Every Cloud request carries the account
  `Bearer ts_…`, which Cloud verifies with `GET AUTH_URL/v1/auth/me`. The
  `user_id` it returns is openseek-api's `users.id`, which the subscriptions
  hang off.
- **Cloud already calls openseek-api as the user.** Sharing uploads to
  `AUTH_URL/v2/shares` with the request's own bearer (`src/share.rs`).

**Decision: Cloud asks openseek-api to notify the account, using the
account's own bearer.** There is no service-to-service secret, and none
exists today (`docs/cloud-auth.md` defers service authentication).

- **openseek-api** adds `POST /v2/push/notify`:
  - Body `{"event":{"kind":"cloud_finished","session":"…","status":"completed"|"failed","answer":"…"}}`.
  - Uses v2 account auth and sends only to the caller's own subscriptions,
    through the §3 sender.
  - The relay sets `url = /cloud/session/<session>`. Cloud session ids are
    the route's ids, so this opens the conversation directly.
  - Returns 202 once the sends are queued. 404 means push is disabled.
- **cloud-agents** keeps the bearer from the request that started the turn
  in memory for the turn's lifetime. After `store.finish` succeeds, a
  fire-and-forget task posts the event, with a 10 s timeout and no retry.
  Any failure is logged and never changes the turn's outcome. If the user
  signed out during the turn, the token is gone and the 401 means no push,
  which is the right result.
- **Abuse bound.** Any holder of an account token can now push to that
  account's own phones. That harms only the account itself, but a per-account
  limit (60 notify calls a minute, answering 429 above it) keeps a looping
  client from burning the VAPID key's standing with push services. The
  `notify` frame path shares the same limit.
- **Worker:** `cloud_finished` reuses the finish strings, mapping `completed`
  to "Task finished" and `failed` to "Task failed". The body is the answer
  excerpt or the fallback body. There is no device name.

## PR plan

Each PR is correct when merged alone:

1. **openseek, stacked on #2206.**
   - `sw.js` and its staging.
   - The frontend toggle component.
   - The `notify` frame and host emission.
   - Docs.
   - Route tests for the local console and the proxy.

   On a relay without push this shows `Unavailable`, and frames are ignored.
2. **openseek-api.**
   - The `/sw.js` route.
   - Config.
   - The table and routes.
   - `notify` decoding.
   - The `webpush` package and fan-out.
   - `POST /v2/push/notify` and the per-account limit.

   Against today's hosts it serves `/sw.js` and test pushes.
3. **cloud-agents.** The notify call after `store.finish`, tested against a
   fake `AUTH_URL` as `src/share.rs` already is. Against an openseek-api
   without push, the call gets a 404 and the turn is unaffected. This
   repo has its own maintainer, so the PR goes to them for review.

**Acceptance (run by the user):**

1. Deploy the openseek-api PR to staging with a VAPID pair.
2. Publish a browser bundle that contains `sw.js`.
3. Install the staging console on Android and on iOS 16.4+ (Add to Home
   Screen), enable notifications, and send a test push.
4. Close the app, start a run on a signed-in desktop, and get the finish
   push. Tapping it opens that conversation.
5. Repeat with a permission request.
6. Deploy cloud-agents to staging, start a Cloud turn from the phone, close
   the app, and get the finish push. Tapping it opens `/cloud/session/<id>`.

## Open questions

1. **Session-bound rows** (recommended) or account-bound rows. Account-bound
   rows would survive 7 idle days, but a browser that signed out without
   running the page's `DELETE` would keep receiving pushes.
2. Whether the payload may carry the answer excerpt and the approval detail
   (recommended: yes, matching the desktop banner), or only kind and status.
3. Whether a push should be suppressed while the same account has the
   window or a console tab focused on that conversation. v1 always sends,
   so a user at the desk also gets the phone push.
4. Whether agent questions (`user_questions`) should also push. The window
   does not post a banner for them today, so v1 leaves them out to stay at
   parity.
5. Whether the cloud-agents change is ours to open as a PR, or a brief for
   its maintainer.
