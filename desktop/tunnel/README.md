# Tunnel control frames

This package defines the four JSON messages exchanged between the desktop
process and the public OpenSeek service while arranging a remote browser
connection. It contains no HTTP server, authentication, socket ownership, or
retry loop.

The server implementation lives in the `openseek-api` repository. The desktop
side is implemented in `desktop/internal/remote`.

## Connection flow

1. The desktop process opens a long-lived WebSocket to `/v1/tunnel` and sends
   `register` with its device token and display name.
2. The service validates the token and replies with either `registered`, which
   contains the device's public id, or `fail`, which rejects the registration.
3. When a browser connects to `/v1/devices/<device>/ws`, the service sends
   `open` with a fresh stream id over the long-lived WebSocket.
4. The desktop process opens `/v1/tunnel/<stream>`. The service then copies
   frames between that data WebSocket and the browser WebSocket.

Only the four messages in steps 1–3 are encoded by this package. After the data
WebSocket is paired, it carries the normal JSON-RPC client protocol unchanged;
`desktop/tunnel` does not inspect those messages.

## Code ownership

- `frame.mbt` owns the JSON shape and strict decoder for `register`,
  `registered`, `open`, and `fail`.
- `desktop/internal/remote/connect.mbt` owns the desktop's WebSockets,
  reconnect behavior, registration state, and one data task per browser.
- `openseek-api` owns the public service, authentication, device ownership,
  stream pairing, and browser-facing endpoints.
- `docs/remote-protocol.md#relay-tunnel` is the full protocol contract and must
  stay synchronized with both repositories.

Malformed or unexpected control messages terminate the current connection.
Ordinary network failures reconnect after a delay. A `fail` message is
different: it rejects the current credentials, so the desktop waits for the
user to sign in again instead of retrying the same token forever.
