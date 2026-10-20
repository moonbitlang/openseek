// A development server for the browser console: it serves a locally built
// frontend bundle on loopback and forwards the console's relay traffic, so a
// local build runs against a real account and its devices. Account routes,
// the device roster and the device WebSocket go to the relay; the page's own
// document and files come from the bundle. The route table mirrors
// openseek-api's, which serves the same document on application paths.
//
// Sign-in uses the relay's loopback account flow (the one native clients
// use) rather than the relay's cookie: the proxy runs the PKCE exchange on
// its own `/cb` and hands the account to the page's `seekmoon.account.v1`
// store, after which the page sends `Authorization: Bearer` itself. The
// proxy keeps no credentials and forwards no browser cookies.
//
// With `Demo`, fixed account and roster answers replace the relay, for
// layout and navigation work without network access.

///|
/// Where the console's relay traffic goes.
pub(all) enum Upstream {
  // A relay origin such as `https://seekmoon.moonbitlang.com`.
  Relay(String)
  // Fixed demo answers; device connections are unavailable.
  Demo
}

///|
/// The relay the proxy targets unless told otherwise.
pub const DefaultRelay : String = "https://seekmoon.moonbitlang.com"

///|
/// One sign-in in flight, keyed by its OAuth `state`.
priv struct PendingSignIn {
  verifier : String
  return_to : String
}

///|
/// What the routes share: where traffic goes, the bundle, this listener's
/// port, and the sign-ins it has started.
priv struct Proxy {
  upstream : Upstream
  bundle : String
  port : Int32
  pending : Map[String, PendingSignIn]
}

///|
/// Serve `bundle` (a built `dist/browser` directory) on `127.0.0.1:port`
/// until cancelled, forwarding relay traffic to `upstream`. `on_ready`
/// receives the origin once the port is bound.
pub async fn serve(
  upstream : Upstream,
  bundle~ : String,
  port~ : Int32,
  on_ready? : (String) -> Unit,
) -> Unit {
  let server = @moonback.listen(dual_stack=false, port=port.to_uint16())
  let proxy = { upstream, bundle, port: server.addr.port(), pending: Map([]), }
  if on_ready is Some(on_ready) {
    on_ready("http://127.0.0.1:\{proxy.port}")
  }
  let app = @moonback.App(Module(ctx => proxy.install(ctx)))
  defer app.close()
  app.serve(server)
}

///|
/// Methods the relay API is forwarded for.
let api_methods : Array[@http.RequestMethod] = [Get, Post, Put, Patch, Delete]

///|
fn Proxy::install(self : Proxy, ctx : @moonback.ModuleContext) -> Unit raise {
  // Bundle files first; anything that is not one falls through to the routes.
  ctx.add_middleware(@unstable_static.new(root=self.bundle))
  ctx.get("/v2/auth/login", (req, res) => self.begin_sign_in(req, res))
  ctx.get("/cb", (req, res) => self.finish_sign_in(req, res))
  ctx.get("/v2/devices/:device/ws", (req, res) => {
    match self.upstream {
      Relay(relay) => bridge_socket(req, res, relay~)
      Demo => demo_unavailable(res)
    }
  })
  let api : @moonback.Handler = (req, res) => {
    match self.upstream {
      Relay(relay) => forward(req, res, relay~)
      Demo => demo_api(req, res)
    }
  }
  for meth in api_methods {
    ctx.add_route(meth, "/v1/*path", api)
    ctx.add_route(meth, "/v2/*path", api)
  }
  for path in ["/", "/cloud", "/cloud/*page", "/device/:device/*page"] {
    ctx.get(path, (_, res) => self.send_document(res))
  }
}

///|
/// The entry document at an application path, pinned to the bundle root
/// with `<base href="/">` as openseek-api pins it to its release.
async fn Proxy::send_document(self : Proxy, res : @moonback.Responder) -> Unit {
  let html = @fs.read_file("\{self.bundle}/index.html").text() catch {
    error => {
      @xlog.error(category="console_proxy") <?
        { "event": "bundle_document_unreadable", "error": "\{error}" }
      res.send_void(status=404, headers={ "Cache-Control": "no-store" })
      return
    }
  }
  res.send_html(
    @moonback.Html::raw(
      html.replace(old="<head>", new="<head><base href=\"/\">"),
    ),
    headers={ "Cache-Control": "no-cache" },
  )
}
