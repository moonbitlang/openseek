///|
/// A fixed, canonical directory. It grants no HTTP routes or command access;
/// the caller owns authentication, Host validation, connections and shutdown.
pub struct Directory {
  priv root : @path.Path
}

///|
/// Resolve an existing directory once, using the host's filesystem rules.
pub async fn Directory::Directory(path : String) -> Directory {
  let root = @path.Path(@fs.realpath(path)).normalize()
  guard @fs.kind(root.to_string()) is Directory else {
    fail("Static root must be a directory")
  }
  { root, }
}

///|
/// The canonical host-native directory spelling, for diagnostics and routing.
pub fn Directory::path(self : Directory) -> String {
  self.root.to_string()
}

///|
fn contains(root : @path.Path, candidate : @path.Path) -> Bool {
  let relative = candidate.relative(base=root).normalize()
  let name = relative.to_string()
  let name = if @path.sep == '\\' {
    name.replace_all(old="\\", new="/")
  } else {
    name
  }
  !relative.is_absolute() && name != ".." && !name.has_prefix("../")
}

///|
/// Serve one GET/HEAD request without closing its connection. `path`, when
/// supplied, is a raw URL path after the caller removes its route prefix.
/// Decode percent escapes once, normalize, then check the physical target.
/// Directories are not listed; `index=true` permits their index.html file.
/// `active` lets an owner revoke a response while filesystem I/O is pending.
/// Other filesystem and connection failures raise to the owning handler.
pub async fn Directory::serve(
  self : Directory,
  request : @http.Request,
  conn : @http.ServerConnection,
  path? : String,
  index~ : Bool = false,
  cache_control~ : String = "no-store",
  active~ : () -> Bool = () => true,
) -> Unit {
  guard request.meth is (Get | Head) else {
    status(conn, 405, "Method Not Allowed")
    return
  }
  let raw = path.unwrap_or(request.path)
  let raw = match raw.split_once("?") {
    Some((path, _)) => path.to_owned()
    None => raw
  }
  guard raw.strip_prefix("/") is Some(relative) else {
    status(conn, 404, "Not Found")
    return
  }
  let decoded = @percent.decode(relative.to_owned()) catch {
    _ => {
      status(conn, 404, "Not Found")
      return
    }
  }
  guard !decoded.has_prefix("/") &&
    !decoded.contains("\\") &&
    !decoded.contains(":") &&
    !decoded.any(ch => ch.is_control()) else {
    status(conn, 403, "Forbidden")
    return
  }
  let mut candidate = self.root.join(Path(decoded)).normalize()
  guard contains(self.root, candidate) else {
    status(conn, 403, "Forbidden")
    return
  }
  if index {
    let kind = @fs.kind(candidate.to_string()) catch {
      error => {
        filesystem_error(conn, error)
        return
      }
    }
    if kind is Directory {
      candidate = candidate.join(Path("index.html"))
    }
  }
  let physical = @fs.realpath(candidate.to_string()) catch {
    error => {
      filesystem_error(conn, error)
      return
    }
  }
  guard contains(self.root, Path(physical)) else {
    status(conn, 403, "Forbidden")
    return
  }
  let kind = @fs.kind(physical) catch {
    error => {
      filesystem_error(conn, error)
      return
    }
  }
  guard kind is Regular else {
    status(conn, 404, "Not Found")
    return
  }
  let source = @fs.open(physical, mode=ReadOnly) catch {
    error => {
      filesystem_error(conn, error)
      return
    }
  }
  defer source.close()
  guard source.kind() is Regular else {
    status(conn, 404, "Not Found")
    return
  }
  guard active() else {
    status(conn, 404, "Not Found")
    return
  }
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": content_type(candidate.to_string()),
    "Content-Length": source.size().to_string(),
    "Cache-Control": cache_control,
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Connection": "close",
  })
  if request.meth is Get {
    for ;; {
      guard active() else { return }
      guard source.read_some(max_len=65536) is Some(bytes) else { break }
      conn.write(bytes)
    }
  }
  conn.end_response()
}

///|
async fn filesystem_error(conn : @http.ServerConnection, error : Error) -> Unit {
  match error {
    @os_error.OSError(_) as error if error.is_ENOENT() || error.is_ENOTDIR() =>
      status(conn, 404, "Not Found")
    _ => raise error
  }
}

///|
async fn status(
  conn : @http.ServerConnection,
  code : Int32,
  reason : String,
) -> Unit {
  conn.send_response(code, reason, extra_headers={
    "Content-Length": "0",
    "Cache-Control": "no-store",
    "Connection": "close",
  })
  conn.end_response()
}
