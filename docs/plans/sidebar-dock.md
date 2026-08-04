# Sidebar Dock: Mixed Tab Strip For Editor, Browser, And Future Views

## Goal

Rebuild the right-hand panel as a dock whose single tab strip mixes
heterogeneous tabs — files (the existing editor), browser preview pages (new),
and future kinds such as subagent viewers — in the style of the Codex desktop
client. P1 ships the dock refactor plus an iframe-backed browser scaffold; the
browser engine is later swapped for a native CEF browser view upstreamed in
proton (P2) without reworking the dock. The editor's current behavior must not
regress.

## Accepted Design

### Strip ownership

- A new `desktop/frontend/dock/` package owns the strip as the single source
  of truth: `tabs : Array[DockTab]` (strip order) plus `active : DockTab?`,
  with the invariant that `active` is `None` exactly when the strip is
  empty. An empty strip renders the launcher menu — that is a view branch on
  `tabs.is_empty()`, not a stored mode.

  ```
  enum DockTab {
    File(path~ : @pathx.Relative)   // document state stays in fileeditor
    Browser(id~ : Int)              // page state lives in preview
    FilePicker                      // transient open-a-file tab; at most one
    // future: Subagent(id~ : ...)
  }
  ```

- `FilePicker` is the one transient tab kind (Codex's "open file" tab): the
  launcher's Files row opens it, or re-activates the existing one — at most
  one lives in the strip. Its body shows the workspace tree with a
  pick-a-file placeholder. Choosing a file replaces the picker in place with
  that file's `File` tab; if the file is already open, the existing `File`
  tab is activated and the picker closes. It closes like any tab and holds
  no document state, so park/restore treats it as a plain strip entry.
- Clicking the file pane's own tree (visible beside the viewer when a
  `File` tab is active) keeps today's rule: open the path's tab or
  re-activate it if already open.
- No projection/reconciliation design: `fileeditor` stops owning any strip
  state. Two owners of membership with one owner of order is a standing bug
  source; the strip is hoisted wholesale instead.
- `fileeditor` is demoted to a document subsystem: it keeps the per-path
  document table (content, mtime signature, staleness), the file tree, LSP,
  and the watcher. The list of open files flows in one direction — the root
  update projects `Array[@pathx.Relative]` out of the dock strip into
  `fileeditor.Ctx` for stat/watch/reload sweeps. Nothing flows back.
- `TabActivated` / `TabClosed` move from `fileeditor.Msg` to the dock's `Msg`;
  a tree click (`FileSelected`) becomes an intent the root update turns into a
  dock open-tab message.

### Rendering: hosts stay mounted, CSS switches

- Every tab-kind host is rendered permanently and hidden by CSS — never
  unmounted. This is load-bearing: the editor viewer, xterm, and iframes are
  imperative hosts under Rabbita's positional diffing, and an iframe that
  leaves the DOM (or is reparented) reloads its document unconditionally.
- File tabs share the one editor viewer host, exactly as today.
- The `FilePicker` tab reuses the file view's chrome — the tree stays, the
  viewer area shows an open-a-file placeholder; no new host.
- Each `Browser(id)` tab owns one iframe element (`browser-host-<id>`),
  attached imperatively on first use (the terminal package's pattern) inside
  one stable container. Inactive iframes are CSS-hidden, never detached.
- The dock view renders the strip and the body: active `File` embeds the
  fileeditor viewer + tree, active `Browser` embeds the preview toolbar + that
  tab's iframe, and an empty strip renders the launcher menu.
- P2 forward-compatibility: each `Browser` tab later maps to one native CEF
  browser view; the dock still only decides which tab is visible and where its
  bounds are. The strip machine does not change.

### Conversation switch: per-conversation strips, keep-alive iframes

- The whole strip is parked and restored per `ConversationKey`, generalizing
  fileeditor's `remembered` machinery (which moves into the dock): a
  remembered strip is the ordered `Array[DockTab]` identities plus the active
  tab. Agent-opened pages belong to their conversation, same as files.
- Semantics and implementation are deliberately split: parking drops file
  content (cheap to re-read, a pure function of the path) but browser iframes
  are keyed by their global id and stay mounted across parks, so returning to
  a conversation does not reload its pages. A page's value is its live state
  (scroll, form, SPA memory), which no re-navigation can reproduce.
- Live iframes are capped (LRU, initial cap 8). An evicted tab keeps its strip
  entry and reloads its URL on next activation.

### Preview package (browser subsystem, P1 = iframe)

- `desktop/frontend/preview/` owns per-page state:

  ```
  struct PageState { url : String, input : String }  // input = address draft
  struct State { pages : Map[Int, PageState], next_id : Int }
  ```

- Toolbar: address bar (auto-prefix `http://`, recognizes localhost), reload
  (imperative `src` reset), open-in-system-browser. Tab label shows the host
  (`localhost:5173`) with a generic globe icon.
- No back/forward in the iframe phase. The joint session history is shared by
  the top page and every live iframe (including hidden background tabs whose
  SPAs push entries), `history.back()` targets whichever frame owns the
  adjacent entry with no API to scope or introspect it, button enablement
  cannot be computed, and a cross-origin iframe's current URL is unreadable so
  the address bar would lie after navigating. A self-maintained URL stack is
  worse: in-page navigations are invisible to the embedder, so the stack
  diverges immediately and "back" destroys real history. Full navigation
  (`GoBack`/`CanGoBack`/`OnAddressChange`) arrives with the native view in P2.
- No favicon fetching: the app page is a `proton://` origin and its http(s)
  subresource fetches silently hang inside CEF's network service (known bug);
  an `<img>` pointed at a site's favicon would hit the same stall.
- Non-localhost input warns that external sites usually refuse framing
  (`X-Frame-Options`/`frame-ancestors` denials are undetectable from the
  embedder — the frame just stays blank) instead of letting the user hit a
  silent white pane.

### Entry points and routing

- `ExternalLinkClicked` in the root update splits: loopback URLs
  (`localhost`, `127.0.0.1`, `[::1]`) open (or re-activate a same-URL)
  Browser tab in the dock; everything else keeps today's
  open-in-system-browser path. The capture-phase listener in
  `external_links.mbt` is unchanged — the decision lives in update.
- The split is by host, not scheme, because `http(s)` says nothing about
  whether the target permits framing: most external sites an agent links
  (GitHub, Google, docs) send `X-Frame-Options`/`frame-ancestors` denials, a
  denial is invisible to the embedder (the load event fires, the pane stays
  blank), and probing response headers first is impossible — http(s) fetches
  from the proton:// origin are exactly the requests that hang in CEF.
  Loopback hosts are both the target scenario (dev servers) and in practice
  never frame-blocking. The predicate is one function — widening it (say to
  private-LAN hosts) is a one-line change — and P2's native view flips the
  default so external links open in the dock too.
- Opening tabs is launcher-driven, Codex-style: with an empty strip the dock
  body is a centered launcher menu of the kinds the dock can open; with tabs
  present, the strip's `+` opens the same menu as an anchored popup. P1
  rows: Browser (opens a blank Browser tab with the address bar focused) and
  Files (see below). Future kinds — review, subagent viewers — become new
  rows without changing the mechanism. Per-row keyboard shortcuts are M3
  polish. Every row must open its result in the sidebar — which is why
  there is no Terminal row: the terminal deliberately lives in the bottom
  dock, and a sidebar launcher entry that pops a panel elsewhere would
  mislead.
- The Files row opens the `FilePicker` tab, re-activating the existing one
  if the strip already has it. A fuzzy quick-open (Cmd-P style) can later
  complement this path.
- No tab drag-reorder in P1 (positional vdom diffing makes a DnD strip a
  project of its own).
- The terminal keeps its bottom dock and separate toggle; it joins neither
  the strip nor the launcher menu. If a sidebar terminal is ever wanted, it
  arrives as a `DockTab::Terminal` variant with its own launcher row — the
  dock design does not block it.

### Layout mechanics

- The drag-to-resize handle (CSS custom property `--editor-width`, handle
  element, clamp bounds in `index.html`'s grid) is hoisted from `fileeditor`
  to the dock package unchanged in behavior — it always resized the whole
  panel, so ownership follows the panel.
- Narrow layout keeps the existing semantics: one full-width pane; the file
  view keeps its tree-drill-down behavior, the browser view fills the pane.
- Rabbita discipline throughout: pure `update`, plain-data models, imperative
  DOM only inside named hosts, idempotence tests for every new message.

## Milestones

- **M0 — iframe probe (gates M2).** A minimal proton app proving whether an
  `<iframe src="http://localhost:...">` subframe navigation loads under a
  `proton://` page at all. The known CEF hang was diagnosed for fetch/XHR/
  EventSource from the proton origin; subframe navigation is unverified.
  Deliberately out of scope for the probe: in-iframe WebSocket/HMR and
  WebGPU — verified later against real dev servers if it ever matters.
  Record the result in this document.

  **Result (2026-08-03): FAILED — the iframe scaffold is not viable.** Probe
  harness: untracked `probe_iframe/` module (add `./probe_iframe` to
  `moon.work`, `PROTON_NATIVE_DIST=<assembled dist> moon build probe_iframe
  --target native`, run against a local logging HTTP server). Findings, each
  verified against the server's request log plus `PROTON_NATIVE_LOG` traces:
  - `<iframe src="http://127.0.0.1:...">` under a `proton://` page: the
    request never reaches the server (30 s), and the parent frame's
    `load_end` never fires — the subframe navigation stalls exactly like the
    known fetch/XHR hang.
  - The same iframe under a `file://` host page also never issues the
    request, so the stall is not proton-scheme registration; it hits
    renderer-initiated http requests from any non-http document origin.
  - Renderer-initiated **top-level** navigation from the proton:// page
    (`location.href = "http://127.0.0.1:..."`) also vanishes — no request,
    no `load_start`. So no "navigate the pane" workaround exists either.
  - Controls proving the rest of the stack is healthy: a browser-initiated
    top-level http load (host-side `load_url`, proton `url` entry) loads the
    document, an `<img>` subresource, an in-page `fetch`, and the favicon
    instantly; and a same-origin `proton://` iframe loads normally
    (`status=200`). Iframe machinery and the network service are both fine —
    only proton-origin-initiated http traffic is swallowed.
  - Consequence: M2 ships the launcher/dock UI over the placeholder pane;
    real page rendering arrives with P2's native CEF browser view, which
    navigates browser-initiated — precisely the path the probe proved works.

  **Addendum (2026-08-04): an http:// parent page revives the iframe.**
  Probed: a top-level `http://127.0.0.1:18923/` page embedding an iframe
  from a *different* loopback port (18924) loads instantly under CEF, and
  in-iframe fetch works — the swallow only hits renderer-initiated http
  requests from non-http document origins. And proton's runtime already
  supports exposing the bridge to an http origin: `BridgeConfig.dev_origins`
  → wire `origin_policy: { mode: "app_and_dev_origins", dev_origins }` →
  enforced renderer-side in `cef_common/bridge_policy.c`. Our pinned lepus
  gates it behind dev mode (`PROTON_DEV`, `bridge_page_policy_for_entry`),
  but upstream main removed that gate in the 0.1.14 chain (fd15942,
  2026-07-31; field renamed `entry_origin`): a production `Url` entry now
  gets the bridge at its origin unconditionally — no upstream PR needed,
  only a submodule bump (our pin 2652522 is 24 commits behind 744615c).
  Remaining costs of this route: the host static server (the loopback OAuth
  listener is prior art), entry/packaging adjustments, a persisted port
  (origin changes wipe localStorage), and the residual iframe limits stay
  (external sites still XFO-refuse framing — routing stays loopback-only;
  no back/forward). Decision pending: pursue this as the P1 browser host,
  or keep the placeholder-pane plan and leave real rendering to P2 — see
  the P2 section: upstream is building the native view right now.
- **M1 — strip hoist.** The dock package plus the fileeditor demotion, as a
  pure behavior-preserving refactor: after M1 the app renders and behaves
  identically to today (file tabs only), with dock and fileeditor each under
  their own blackbox tests. The empty panel keeps today's tree-plus-
  placeholder body; the launcher arrives with M2.

  **Status (2026-08-03): DONE.** `desktop/frontend/dock/` (state/update/
  view + 8 blackbox tests) owns `open`/`tabs`/`active`/`remembered`;
  fileeditor demoted to the document table (`docs : Map[Relative, Doc]`,
  strip fields and `ToggleFilePanel`/`TabActivated`/`TabClosed` removed,
  `Ctx` carries the projection); root update wires `Dock(...)`, intercepts
  `FileSelected`, and syncs dock-then-fileeditor; root view assembles
  `div.editor` from dock strip + fileeditor breadcrumb/body (child order
  unchanged). `moon -C desktop check --deny-warn` clean on js and native;
  js suite 743/743 (dock 8, fileeditor 36, root 302 included); interface
  diffs match the API diff below. Not yet committed.
- **M1.5 — transport unification (unlocks M2's iframes).** The user chose
  the full version of the http-parent route: instead of bridging proton://
  to an http origin, the window itself moves onto `http://127.0.0.1:<port>/`
  and the in-process `__MoonBit__` bridge is deleted — the desktop window
  becomes the same JSON-RPC WebSocket client a relay browser is
  (docs/remote-protocol.md is updated as the contract).

  **Status (2026-08-04): DONE (code + tests; live E2E is the user's).**
  - Pre-probe: WS-from-http-origin under CEF verified with the probe_iframe
    `url` harness + a hand-rolled WS server — handshake (with
    `Origin: http://127.0.0.1:<port>`), both frame directions, all instant.
  - Host: `internal/remote/local.mbt` `LocalServer` (loopback bind with
    persisted-port preference, static bundle serving with traversal-proof
    routes, `/ws` upgrade guarded by a per-launch entropy token + exact
    Origin match) feeding the same `WsClientActor` as the relay;
    `local_ops.mbt` carries the loopback-only methods (`shell.open_external`
    moved from the extension, new `notification.show`); the delivery filter
    (`notification_for_client`) now also gates `notification.click` to
    loopback. `main.mbt` builds the window with `@proton.url` on
    `LocalServer::entry_url()`, pumps native notification clicks into the
    hub, and drops the whole extension/window-lifecycle wiring;
    `internal/extension/` is deleted and the `proton_ext`/`proton_contract`
    deps removed. Port persists via `internal/host/local_port.mbt`
    (`local_http.json`) so the origin — and localStorage UI prefs — survive
    relaunches. No lepus bump needed: `Url` entries need no bridge at all.
  - Frontend: `bridge_request`/`bridge_request_in_order` collapse to
    `ws_request`; `ws_connect` takes the channel (`Local` → same-origin
    `/ws?token=` from the entry query); the proton install/event-wiring
    half of bridge.mbt is gone; `BridgeUnavailable` died with it (loss =
    `ChannelDown`×3); system notifications post over the wire; the shell
    executables name their identity (`boot(desktop~)` →
    `initial_model(desktop~)`) replacing every runtime protocol sniff —
    including the external-link capture listener, which now takes the flag
    instead of testing `location.protocol` (else the desktop window would
    have opened externals as CEF popups).
  - Validation: js 741/741, native 1911/1911, `moon build --target native`
    links, both checks warning-free; mbti diffs are exactly the intended
    surface (interop −5 proton fns, `ws_connect(ChannelId, …)`,
    `boot(desktop~)`, host +port persistence, remote +LocalServer/extras).
  - Deliberate cost: the old `proton://app/` origin's localStorage is
    unreachable — legacy client-held engine keys (pre-host-store builds)
    can no longer migrate and users coming from very old builds re-enter
    them in Settings; UI prefs reset once.
- **M2 — browser tabs.** The preview package, iframe hosts, link routing,
  address bar, and the launcher (empty-strip pane, `+` popup menu, the
  `FilePicker` tab). With M1.5 in, the window is an http origin, so real
  iframes are live again: loopback-host framing works (M0 addendum);
  external sites still XFO-refuse and route to the system browser.
- **M3 — polish.** Remembered strips including browser tabs, iframe LRU
  keep-alive, narrow layout pass.

## M1 Wiring Decisions (settled at implementation start)

- `@dock.State = { open, tabs : Array[DockTab], active : DockTab?, owner :
  ConversationKey?, remembered : Map[ConversationKey, RememberedStrip] }`;
  `RememberedStrip = { tabs, active }`. The panel-visibility `open` flag moves
  here from fileeditor (the panel is the dock now). M1's `DockTab` has only
  `File(path~)`; `Browser`/`FilePicker` arrive with M2 so no unreachable view
  arms exist in a behavior-preserving refactor.
- `@dock.Msg = TogglePanel | TabActivated(DockTab) | TabClosed(DockTab)`;
  `update` is the pure strip machine (close picks right neighbor, else left,
  else None). Pure helpers: `open_file(state, path)` (append-or-activate),
  `sync(state, owner)` (park/restore per conversation, pure — document
  reloads stay fileeditor's), `file_paths(state)` (the projection).
- Root orchestrates cross-package effects by comparing `dock.active` before/
  after a dock message: activation change → `@fileeditor.activate(path)` /
  clear; a close also drops the closed path's document + parked view state;
  panel-open toggle → mount commands + read-active-if-loading. The tree click
  (`FileSelected`) is intercepted in the root update (the
  `EditorCommentAdded` pattern): dock appends/activates the tab, fileeditor
  loads the document.
- fileeditor demotion: `State` loses `open`/`tabs`/`active`/`remembered`;
  gains `docs : Map[@pathx.Relative, Doc]` with `Doc = { name, state :
  TabState, stale }` (TabState and its constructors keep their names — only
  strip membership moves out). `Ctx` gains `panel_open : Bool`, `open_files :
  Array[@pathx.Relative]`, `active_file : @pathx.Relative?` — all projected
  from the dock by the root each dispatch. The watcher condition becomes
  `ctx.panel_open || !ctx.open_files.is_empty()`.
- Post-dispatch sync order matters: `@dock.sync` first (strip parked/
  restored), then `@fileeditor.sync` sees the fresh projection and re-roots
  the document table (docs rebuilt as `TabLoading` from `ctx.open_files`,
  active read issued when the panel is open).
- View split keeps today's DOM exactly: the root view builds `div.editor`
  from dock parts (`resize_handle_view`, `tabs_bar`) followed by fileeditor
  parts (breadcrumb, body). `tabs_bar` takes root-computed
  `TabChip = { tab, label, title, missing }` view-models so the dock never
  reads document state (labels/deleted-style come from fileeditor's table).
- Deviation settled while implementing: `editor_resize.mbt` STAYS in
  fileeditor for now — its drag shares `drag_size`/`end_drag`/root-style
  refs with the tree resizer and re-measures the viewer (`mounted_viewer`),
  all fileeditor internals. The CSS contract (`--editor-width`, element ids)
  is unchanged and the dock owns panel visibility; moving the file is
  mechanical if a later milestone wants it.

## Target Files And Surfaces

- New `desktop/frontend/dock/`: strip state machine (`state.mbt`,
  `update.mbt`, `view.mbt`, resize), blackbox tests for open/activate/close/
  park/restore/LRU transitions.
- New `desktop/frontend/preview/`: page state, toolbar view, iframe host
  attach/reload commands, URL normalization; blackbox tests.
- `desktop/frontend/fileeditor/state.mbt`, `update.mbt`, `view.mbt`,
  `editor_panel.mbt`: remove `tabs`/`active`/`remembered` and the strip view;
  keep the document table, tree, LSP, watcher; `Ctx` gains the projected
  open-file list.
- `desktop/frontend/fileeditor/editor_resize.mbt`: moves to the dock package;
  CSS contract (`--editor-width`, clamp bounds) unchanged.
- `desktop/frontend/model.mbt`: `dock : @dock.State` and
  `preview : @preview.State` join `file_panel : @fileeditor.State`.
- `desktop/frontend/update.mbt`: root wiring (`Dock(...)`, `Preview(...)`
  wraps), `file_ctx` projection, the `ExternalLinkClicked` split, and the
  conversation-switch park/restore call moving from fileeditor sync to dock
  sync.
- `desktop/frontend/view.mbt`: the right panel renders the dock view; topbar
  toggles unchanged.
- `desktop/app.css`, `desktop/index.html`: strip styles, stacked hidden
  hosts, grid variable ownership.
- Generated `pkg.generated.mbti` files for the touched frontend packages.

## API And Interface Diff

- New public packages `@dock` (opaque `State`, `pub(all) enum DockTab`,
  `Msg`, `update`/`sync`/`panel_view`) and `@preview` (opaque `State`, `Msg`,
  toolbar/view entry points), following the one-package-per-component
  convention.
- `@fileeditor.State` loses `tabs`, `active`, `remembered`;
  `RememberedTab(s)` move to the dock generalized over `DockTab`;
  `@fileeditor.Msg` loses `TabActivated`/`TabClosed`; `Ctx` gains the open
  file list.
- The root package stays private; no host/extension or wire-protocol changes
  in P1 (the iframe needs no new ops).

## Open Questions

- M2 scope under the placeholder outcome: whether `ExternalLinkClicked`
  should already intercept loopback links into a placeholder Browser tab, or
  keep sending every link to the system browser until P2 renders real pages
  (decide when M2 starts).
- Whether the dock's open state and active tab persist across app restart
  (decide at M3; the `TreeLayoutStorageKey` pattern is available).
- LRU cap value (initial 8) — revisit once real memory numbers exist.

## Deferred (P2): Native Browser View

The iframe is a scaffold. The endgame — matching the Codex client, which uses
Electron's `WebContentsView` — is a proton-upstream API creating per-tab CEF
browsers as native child views of the main window: bounds synced from the
panel rect over a bridge op, navigation events (`OnAddressChange`, title,
loading) pumped back for the address bar, persistent cookie storage
(cache_path) so logins survive restarts, `window.open` routed to the system
browser. Known costs accepted in advance: per-platform native work (macOS
first), native views z-order above all HTML (constrain or temporarily hide
overlays), and focus/shortcut handoff between the page and the app. The dock
and preview state machines carry over unchanged; only the host behind each
`Browser` tab swaps.

**Upstream is building exactly this (found 2026-08-04).** Branch
`origin/feat/web-contents-view` in moonbit-community/proton (last commit
2026-08-04, active): `ViewHandle` (set_bounds/set_visible/set_z_order,
load_url/load_html, back/forward/reload/stop, eval, devtools, close),
`App::on_view_event` with `ViewEvent::LoadingChanged / Navigated /
TitleUpdated / LoadFailed` — the address bar's whole wishlist — engines for
macOS, Windows, and Linux, an e2e scenario, and example
`52_web_contents_view` reworked into "a built-in browser demo". Not merged
to main yet; API may still churn; a bump requires a runtime rebuild (native
ABI additions). When it lands, the dock's `Browser` tab host can skip the
iframe entirely.

## Next Implementation Step

M0 (failed → escape route probed), M1 (strip hoist), and M1.5 (transport
unification; window on `http://127.0.0.1`) are implemented, all uncommitted.
Next: the user's live E2E pass on M1.5 (window paint over the loopback
origin, run round-trip, terminal, notification click, external links,
reload-reconnect), then M2 — the preview package with real iframes for
loopback URLs, the launcher (empty-strip pane + `+` popup + `FilePicker`
tab), and the routing recorded under Open Questions.

## Validation Plan

- Dock strip machine: blackbox tests covering open/activate/close ordering,
  same-URL reuse, the launcher-on-empty-strip invariant, `FilePicker`
  open/dedupe/replace-in-place/close transitions (including picking an
  already-open file), park/restore round-trips per conversation, LRU
  eviction order, and idempotence of every new message.
- Fileeditor: existing tests keep passing with strip fields removed; document
  table sweeps driven by the projected open-file list get their own cases.
- Root update: idempotence tests for the `ExternalLinkClicked` split and the
  conversation-switch park/restore path.
- M1 exit criterion: no user-visible behavior change (file tabs, tree,
  resize, narrow layout, conversation switch all as today).
- Run `moon -C desktop check --target native --deny-warn` and
  `moon -C desktop check --target js --deny-warn`; focused package tests,
  then the full desktop test suite.
- Run `moon -C desktop fmt` and default-target `moon -C desktop info`; review
  generated interface diffs against the API diff above.
- User-run E2E on the packaged app: open files, switch conversations, open a
  localhost preview from a transcript link, verify no reload on switch-back,
  evict past the LRU cap, narrow layout.
