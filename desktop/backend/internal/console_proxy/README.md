# Console proxy

Runs a locally built browser console against a real relay, so frontend work
can be checked with a real account, its devices and Cloud without publishing
a bundle.

```sh
just --justfile desktop/justfile console-proxy            # production relay
just --justfile desktop/justfile console-proxy --demo     # no network
just --justfile desktop/justfile console-proxy --relay https://staging.example --port 27191
```

The recipe builds `desktop/dist/browser` and serves it on
`http://127.0.0.1:27190/`. Open `/cloud`, or any application path
(`/cloud/devices`, `/device/<id>/chat`); reloading one serves the document as
openseek-api does.

- **Relay traffic.** `/v1/*` and `/v2/*` requests and the device WebSocket
  (`/v2/devices/<id>/ws`) go to `--relay` (default
  `https://seekmoon.moonbitlang.com`). The page's `Authorization` header is
  forwarded; its cookies and `Origin` are not, and relay cookies are not
  passed back.
- **Sign-in.** The page's sign-in link runs the relay's loopback account
  flow on this port (`/v2/auth/account/start` with a PKCE challenge, the
  relay's redirect to `/cb`, then `/v2/auth/account/exchange`). The resulting
  account is stored in the page's `seekmoon.account.v1` entry, as the Android
  host does; the proxy keeps no credentials. Signing out in the page clears
  it.
- **Demo mode.** `--demo` signs in as a fixed account with one online and one
  offline device. Device connections and Cloud need a relay.

Cloud conversations call the Cloud API directly from the page, not through
this proxy, so they work only where that API accepts this loopback origin.
