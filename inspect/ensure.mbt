// One server per set of sessions: `/api/info` identifies a server by what it
// serves, a busy port running an `inspect` for the same sessions is reused
// instead of failing, and `--ensure` gives each session root a stable,
// token-protected home on loopback for tools like the TUI to share.

///|
/// This server's name as `/api/info` reports it.
let inspect_server_name : String = "moonbitlang/inspect"

///|
/// This module's version as `/api/info` reports it. Must equal `version` in
/// moon.mod; a test keeps them in step.
let inspect_version : String = "0.1.0"

///|
/// FNV-1a over the UTF-8 bytes of `text`: a stable, dependency-free hash for
/// naming what a server serves and for deriving its `--ensure` port.
fn fnv1a64(text : String) -> UInt64 {
  let mut hash = 0xcbf29ce484222325UL
  for byte in @utf8.encode(text) {
    hash = hash ^ byte.to_uint64()
    hash = hash * 0x100000001b3UL
  }
  hash
}

///|
/// What a server serves, as a short opaque string: a hash of the real paths of
/// its session root and search directories. Two servers with the same identity
/// list the same sessions, so the second can hand over to the first. Paths that
/// do not exist are hashed as given.
async fn server_identity(
  session_root : String,
  search_dirs : Array[String],
) -> String {
  let dirs = []
  for dir in search_dirs {
    dirs.push(canonical_path(dir))
  }
  dirs.sort()
  let key = [canonical_path(session_root), ..dirs].join("\n")
  fnv1a64(key).to_string(radix=16)
}

///|
async fn canonical_path(path : String) -> String {
  @fs.realpath(path) catch {
    _ => path
  }
}

///|
/// The `/api/info` reply. It is the one route `--ensure` serves without a
/// token, and it reveals nothing but the server's name, version and identity.
fn info_reply(identity : String) -> Reply {
  json_reply({
    "server": inspect_server_name,
    "version": inspect_version,
    "identity": identity,
  })
}

///|
/// Whether the server at `host:port` is an `inspect` serving `identity`. False
/// for a closed port, another program, or an `inspect` serving other sessions.
async fn probe_inspect(host : String, port : Int, identity : String) -> Bool {
  let reply = @async.with_timeout_opt(3000, () => {
    @http.get("http://\{host}:\{port}/api/info")
  }) catch {
    _ => return false
  }
  guard reply is Some((response, body)) && response.code == 200 else {
    return false
  }
  let info = @json.parse(body.text()) catch { _ => return false }
  guard info is { "server": String(server), "identity": String(served), .. } else {
    return false
  }
  server == inspect_server_name && served == identity
}

///|
/// First port of the range `--ensure` derives its ports from.
let ensure_port_base : Int = 41000

///|
/// Size of that range: 41000–41899.
let ensure_port_span : Int = 900

///|
/// How many consecutive ports `--ensure` tries before giving up.
let ensure_port_tries : Int = 16

///|
/// The ports `--ensure` tries for `identity`, in order: a window starting at a
/// port derived from it, so a session root always lands on the same port unless
/// something else already holds it.
fn ensure_ports(identity : String) -> Array[Int] {
  let start = (fnv1a64(identity) % ensure_port_span.to_uint64()).to_int()
  let ports = []
  for i in 0..<ensure_port_tries {
    ports.push(ensure_port_base + (start + i) % ensure_port_span)
  }
  ports
}

///|
/// What `--ensure` leaves in the session root for the next caller: where the
/// server listens and the token its URLs need. Readable only by the user.
priv struct ServerRecord {
  port : Int
  token : String
  version : String
} derive(ToJson, FromJson)

///|
fn record_path(session_root : String) -> String {
  join_path(session_root, "inspect.json")
}

///|
async fn read_record(path : String) -> ServerRecord? {
  let text = @fs.read_file(path).text() catch { _ => return None }
  let json = @json.parse(text) catch { _ => return None }
  Some(@json.from_json(json)) catch {
    _ => None
  }
}

///|
/// Write the record atomically and owner-only: a reader sees the old record or
/// the new one, never half of one, and other users never see the token.
async fn write_record(path : String, record : ServerRecord) -> Unit {
  let tmp = "\{path}.\{record.port}.tmp"
  @fs.write_file(
    tmp,
    ToJson::to_json(record).stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  @fs.rename(tmp, path, replace=true)
}

///|
/// A fresh 128-bit token, hex. Seeded from `/dev/urandom` where there is one;
/// elsewhere (native Windows) from the clock and the session root, which is
/// weaker, but the server only listens on loopback and checks `Host`, so the
/// token guards against other local users rather than the network.
async fn new_token(salt : String) -> String {
  let rand = @random.Rand::chacha8(seed=token_seed(salt))
  let builder = StringBuilder()
  for _ in 0..<2 {
    let part = rand.uint64().to_string(radix=16)
    for _ in part.length()..<16 {
      builder.write_char('0')
    }
    builder.write_string(part)
  }
  builder.to_string()
}

///|
async fn token_seed(salt : String) -> Bytes {
  let from_os : Bytes? = try {
    let file = @fs.open("/dev/urandom", mode=ReadOnly)
    defer file.close()
    Some(file.read_exactly(32))
  } catch {
    _ => None
  }
  match from_os {
    Some(bytes) if bytes.length() == 32 => bytes
    _ => {
      let now = @async.now()
      let parts = [
        fnv1a64("\{now}\n\{salt}"),
        fnv1a64("\{salt}\n\{now}"),
        fnv1a64("\{now * 31}"),
        fnv1a64(salt),
      ]
      let bytes = FixedArray::make(32, b'\x00')
      for i, part in parts {
        for j in 0..<8 {
          bytes[i * 8 + j] = ((part >> (j * 8)) & 0xFFUL).to_byte()
        }
      }
      Bytes::from_array(bytes)
    }
  }
}

///|
/// What an `--ensure` server checks on every request but `/api/info`.
priv struct Guard {
  token : String
  port : Int
}

///|
/// The cookie a browser keeps the token in after opening the printed URL.
/// Cookies are shared by every port of a host, so the name carries the port.
fn Guard::cookie_name(self : Guard) -> String {
  "openseek_inspect_\{self.port}"
}

///|
/// The `Set-Cookie` value that lets the page's own requests (the bundle, the
/// session API) through after it was opened with `?t=<token>`.
fn Guard::cookie(self : Guard) -> String {
  "\{self.cookie_name()}=\{self.token}; Path=/; HttpOnly; SameSite=Strict"
}

///|
/// Whether a request carries the token, as `?t=` or as the cookie.
fn Guard::authorized(
  self : Guard,
  path : String,
  headers : Map[@http.CaseInsensitiveString, String],
) -> Bool {
  query_param(path, "t") == Some(self.token) ||
  cookie_value(
    headers.get(@http.CaseInsensitiveString("cookie")),
    self.cookie_name(),
  ) ==
  Some(self.token)
}

///|
/// Whether the `Host` header names this server on loopback. A page on another
/// site that rebinds its DNS name to 127.0.0.1 sends its own name here.
fn Guard::host_allowed(
  self : Guard,
  headers : Map[@http.CaseInsensitiveString, String],
) -> Bool {
  match headers.get(@http.CaseInsensitiveString("host")) {
    Some(host) =>
      host == "127.0.0.1:\{self.port}" ||
      host == "localhost:\{self.port}" ||
      host == "[::1]:\{self.port}"
    None => false
  }
}

///|
/// The value of cookie `name` in a `Cookie` header (`a=1; b=2`), if present.
fn cookie_value(header : String?, name : String) -> String? {
  guard header is Some(header) else { return None }
  for pair in header.split(";") {
    match pair.trim().split_once("=") {
      Some((key, value)) if key == name => return Some(value.to_owned())
      _ => ()
    }
  }
  None
}

///|
/// The URL an `--ensure` server is opened with.
fn ensure_url(port : Int, token : String) -> String {
  "http://127.0.0.1:\{port}/?t=\{token}"
}

///|
/// How `--ensure` got its server: bound a port and must serve on it, or found
/// one already serving these sessions.
priv enum Ensured {
  Started(@http.Server, Int, String)
  Reused(Int, String)
}

///|
/// Find or start the one server for these sessions. Each candidate port is
/// either bound (the OS allows only one listener, so two callers cannot both
/// win) or probed: an `inspect` there serving the same identity, whose record
/// names that port, is reused. The record is written right after binding and
/// before serving, so a caller whose probe gets an answer also finds it.
async fn ensure_server(
  session_root : String,
  identity : String,
  ports : Array[Int],
) -> Ensured {
  let record_file = record_path(session_root)
  for port in ports {
    let addr = @socket.Addr::parse("127.0.0.1:\{port}")
    let bound = Some(@http.Server(addr)) catch { _ => None }
    match bound {
      Some(server) => {
        let token = new_token("\{identity}\n\{port}")
        write_record(record_file, { port, token, version: inspect_version, })
        return Started(server, port, token)
      }
      None =>
        if probe_inspect("127.0.0.1", port, identity) &&
          read_record(record_file) is Some(record) &&
          record.port == port {
          return Reused(port, record.token)
        }
    }
  }
  fail(
    "inspect --ensure: no free port among \{ports[0]}..\{ports[ports.length() - 1]}",
  )
}

///|
/// Drop the record if it still describes this server, so a later `--ensure`
/// does not trust a port that is gone. A newer server's record is left alone.
async fn remove_own_record(
  session_root : String,
  port : Int,
  token : String,
) -> Unit {
  let path = record_path(session_root)
  if read_record(path) is Some(record) &&
    record.port == port &&
    record.token == token {
    @fs.remove(path) catch {
      _ => ()
    }
  }
}

///|
test "ensure_ports stay in range and are stable per identity" {
  let ports = ensure_ports("abc")
  assert_eq(ports.length(), ensure_port_tries)
  assert_eq(ports, ensure_ports("abc"))
  for port in ports {
    assert_true(
      port >= ensure_port_base && port < ensure_port_base + ensure_port_span,
    )
  }
  // Consecutive, wrapping inside the range.
  for i in 1..<ports.length() {
    let expected = if ports[i - 1] + 1 == ensure_port_base + ensure_port_span {
      ensure_port_base
    } else {
      ports[i - 1] + 1
    }
    assert_eq(ports[i], expected)
  }
  assert_true(ensure_ports("abc") != ensure_ports("abd"))
}

///|
test "cookie_value finds one cookie among several" {
  assert_eq(
    cookie_value(
      Some("a=1; openseek_inspect_41000=tok; b=2"),
      "openseek_inspect_41000",
    ),
    Some("tok"),
  )
  assert_eq(
    cookie_value(Some("openseek_inspect_41001=tok"), "openseek_inspect_41000"),
    None,
  )
  assert_eq(cookie_value(None, "x"), None)
}

///|
test "the guard wants the token and a loopback Host" {
  let access : Guard = { token: "tok", port: 41000, }
  let headers : Map[@http.CaseInsensitiveString, String] = {
    "Host": "127.0.0.1:41000",
  }
  assert_true(access.authorized("/?t=tok", headers))
  assert_false(access.authorized("/?t=nope", headers))
  assert_false(access.authorized("/api/sessions", headers))
  let with_cookie : Map[@http.CaseInsensitiveString, String] = {
    "Cookie": "openseek_inspect_41000=tok",
  }
  assert_true(access.authorized("/api/sessions", with_cookie))
  assert_true(access.host_allowed(headers))
  assert_true(access.host_allowed({ "host": "localhost:41000" }))
  assert_false(access.host_allowed({ "Host": "evil.example:41000" }))
  assert_false(access.host_allowed({ "Host": "127.0.0.1:41001" }))
  assert_false(access.host_allowed({}))
  inspect(
    access.cookie(),
    content="openseek_inspect_41000=tok; Path=/; HttpOnly; SameSite=Strict",
  )
}
