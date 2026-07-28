///| Port of `vscode/src/vs/base/common/uri.ts` (checked-in submodule): the `URI` class, percent encoder/decoder, and `uriToFsPath`.
///
/// Reviewed deviations from the pinned Monaco implementation:
/// - D3: the RFC3986 appendix-B regex and `_rEncodedAsHex` become hand-rolled
///   scanners with identical accept/capture semantics.
/// - D4: JS `encodeURIComponent`/`decodeURIComponent` are reimplemented as
///   UTF-8 percent transcoding (uppercase hex). A lone surrogate aborts the
///   way JS throws `URIError`; invalid `%` sequences / invalid UTF-8 fail so
///   `decode_uri_component_graceful` keeps the raw text.
/// - D5: Monaco's abstract `URI` + caching subclass `Uri` collapse into one
///   struct with `mut` cache fields; `Eq`/`Hash`/`Debug` are manual over the
///   five components so the caches never affect identity. Monaco re-derives
///   when a cached value is falsy (`''`); the `Option` caches keep it — the
///   recomputed value would be identical.
/// - D6: `[UriError]` throws become the `UriError` suberror raised by
///   `Uri::parse` / `Uri::from` / `Uri::with_`; `Uri::file` also validates
///   but its inputs cannot fail validation, so it stays non-raising;
///   `Uri::join_path` on a URI without path aborts (programmer error,
///   matching Monaco's unconditional throw).
/// - D7: `toJSON`/`revive`/`UriState` marshalling is deferred — the remote
///   protocol serializes `to_string()` strings.

///|
/// Validation failure raised by the `Uri` constructors (`[UriError]` throws
/// in uri.ts `_validateUri`, D6).
pub suberror UriError {
  UriError(String)
} derive(Debug)

///|
/// Uniform Resource Identifier (URI) http://tools.ietf.org/html/rfc3986.
/// This class is a simple parser which creates the basic component parts
/// (http://tools.ietf.org/html/rfc3986#section-3) with minimal validation
/// and encoding.
///
/// ```txt
///       foo://example.com:8042/over/there?name=ferret#nose
///       \_/   \______________/\_________/ \_________/ \__/
///        |           |            |            |        |
///     scheme     authority       path        query   fragment
///        |   _____________________|__
///       / \ /                        \
///       urn:example:animal:ferret:nose
/// ```
///
/// Components are stored **decoded** (uri.ts:125-146). The two `mut` fields
/// are the `_formatted`/`_fsPath` lazy caches of the `Uri` subclass
/// (uri.ts:455-477, D5).
pub struct Uri {
  /// scheme is the 'http' part of 'http://www.example.com/some/path?query#fragment'.
  /// The part before the first colon.
  scheme : String
  /// authority is the 'www.example.com' part of 'http://www.example.com/some/path?query#fragment'.
  /// The part between the first double slashes and the next slash.
  authority : String
  /// path is the '/some/path' part of 'http://www.example.com/some/path?query#fragment'.
  path : String
  /// query is the 'query' part of 'http://www.example.com/some/path?query#fragment'.
  query : String
  /// fragment is the 'fragment' part of 'http://www.example.com/some/path?query#fragment'.
  fragment : String
  priv mut formatted_cache : String?
  priv mut fs_path_cache : String?
}

///|
/// Component equality (D5: the caches are identity-irrelevant).
pub impl Eq for Uri with fn equal(self, other) {
  self.scheme == other.scheme &&
  self.authority == other.authority &&
  self.path == other.path &&
  self.query == other.query &&
  self.fragment == other.fragment
}

///|
pub impl Hash for Uri with fn hash_combine(self, hasher) {
  hasher.combine(self.scheme)
  hasher.combine(self.authority)
  hasher.combine(self.path)
  hasher.combine(self.query)
  hasher.combine(self.fragment)
}

///|
/// Mirrors the `debug.description` label `URI(${this.toString()})`
/// (uri.ts:421) without touching the `_formatted` cache.
pub impl Debug for Uri with fn to_repr(self) {
  Repr("URI(\{as_formatted(self, false)})")
}

///|
/// `_schemePattern` (uri.ts:11): `^\w[\w\d+.-]*$` where `\w` is
/// `[A-Za-z0-9_]`.
fn is_scheme_word_char(code : Int) -> Bool {
  (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
  (code >= 'A'.to_int() && code <= 'Z'.to_int()) ||
  (code >= '0'.to_int() && code <= '9'.to_int()) ||
  code == '_'.to_int()
}

///|
fn scheme_matches_pattern(scheme : String) -> Bool {
  if scheme.length() == 0 {
    return false
  }
  if !is_scheme_word_char(scheme[0].to_int()) {
    return false
  }
  for i in 1..<scheme.length() {
    let code = scheme[i].to_int()
    if !is_scheme_word_char(code) &&
      code != '+'.to_int() &&
      code != '.'.to_int() &&
      code != '-'.to_int() {
      return false
    }
  }
  true
}

///|
/// The `matchAll(/[^\w\d+.-]/gu)` detail of the illegal-scheme error
/// (uri.ts:25-28): first offending code point, its code-unit index, and the
/// total count.
fn scheme_illegal_detail(scheme : String) -> String {
  let mut count = 0
  let mut first = ""
  let mut first_index = -1
  let mut i = 0
  while i < scheme.length() {
    let unit = scheme[i].to_int()
    let mut width = 1
    let mut ch = ""
    if is_high_surrogate(unit) &&
      i + 1 < scheme.length() &&
      is_low_surrogate(scheme[i + 1].to_int()) {
      width = 2
      ch = js_slice(scheme, i, end=i + 2)
    } else {
      ch = js_slice(scheme, i, end=i + 1)
    }
    let code = unit
    let is_legal = width == 1 &&
      (
        is_scheme_word_char(code) ||
        code == '+'.to_int() ||
        code == '.'.to_int() ||
        code == '-'.to_int()
      )
    if !is_legal {
      if first_index == -1 {
        first = ch
        first_index = i
      }
      count += 1
    }
    i += width
  }
  if count > 0 {
    " Found '\{first}' at index \{first_index} (\{count} total)"
  } else {
    ""
  }
}

///|
/// `_validateUri` (uri.ts:15).
fn validate_uri(ret : Uri, strict : Bool) -> Unit raise UriError {
  // scheme, must be set
  if ret.scheme == "" && strict {
    raise UriError(
      "[UriError]: Scheme is missing: {scheme: \"\", authority: \"\{ret.authority}\", path: \"\{ret.path}\", query: \"\{ret.query}\", fragment: \"\{ret.fragment}\"}",
    )
  }

  // scheme, https://tools.ietf.org/html/rfc3986#section-3.1
  // ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
  if ret.scheme != "" && !scheme_matches_pattern(ret.scheme) {
    raise UriError(
      "[UriError]: Scheme contains illegal characters.\{scheme_illegal_detail(ret.scheme)} (len:\{ret.scheme.length()})",
    )
  }

  // path, http://tools.ietf.org/html/rfc3986#section-3.3
  // If a URI contains an authority component, then the path component
  // must either be empty or begin with a slash ("/") character.  If a URI
  // does not contain an authority component, then the path cannot begin
  // with two slash characters ("//").
  if ret.path != "" {
    if ret.authority != "" {
      if char_code_at(ret.path, 0) != char_forward_slash {
        raise UriError(
          "[UriError]: If a URI contains an authority component, then the path component must either be empty or begin with a slash (\"/\") character",
        )
      }
    } else if char_code_at(ret.path, 0) == char_forward_slash &&
      char_code_at(ret.path, 1) == char_forward_slash {
      raise UriError(
        "[UriError]: If a URI does not contain an authority component, then the path cannot begin with two slash characters (\"//\")",
      )
    }
  }
}

///|
/// `_schemeFix` (uri.ts:54): for a while uris *without* schemes were allowed
/// and this is the migration for them — empty scheme + non-strict falls back
/// to the file-scheme.
fn scheme_fix(scheme : String, strict : Bool) -> String {
  if scheme == "" && !strict {
    return "file"
  }
  scheme
}

///|
/// `_referenceResolution` (uri.ts:62) — implements a bit of
/// https://tools.ietf.org/html/rfc3986#section-5: the slash-character is the
/// 'default base' as constructing URIs relative to other URIs is unsupported.
fn reference_resolution(scheme : String, path : String) -> String {
  match scheme {
    "https" | "http" | "file" =>
      if path == "" {
        "/"
      } else if char_code_at(path, 0) != char_forward_slash {
        "/" + path
      } else {
        path
      }
    _ => path
  }
}

///|
/// The validating string-overload constructor (uri.ts:161-180):
/// schemeFix → referenceResolution → validateUri.
fn Uri::new_(
  scheme : String,
  authority : String,
  path : String,
  query : String,
  fragment : String,
  strict : Bool,
) -> Uri raise UriError {
  let scheme = scheme_fix(scheme, strict)
  let path = reference_resolution(scheme, path)
  let uri : Uri = {
    scheme,
    authority,
    path,
    query,
    fragment,
    formatted_cache: None,
    fs_path_cache: None,
  }
  validate_uri(uri, strict)
  uri
}

///|
/// Hand-rolled scanner for `_regexp` (uri.ts:84), the RFC3986 appendix-B
/// component split `^(([^:/?#]+?):)?(\/\/([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?`
/// (D3). Returns the raw (undecoded) components.
fn parse_components(value : String) -> (String, String, String, String, String) {
  let len = value.length()
  let mut pos = 0

  // scheme: `([^:/?#]+?):` — at least one class char before the first ':'.
  let mut scheme = ""
  let mut i = 0
  let mut scheme_end = -1
  while i < len {
    let code = value[i].to_int()
    if code == char_colon {
      scheme_end = i
      break
    }
    if code == char_forward_slash ||
      code == '?'.to_int() ||
      code == '#'.to_int() {
      break
    }
    i += 1
  }
  if scheme_end > 0 {
    scheme = js_slice(value, 0, end=scheme_end)
    pos = scheme_end + 1
  }

  // authority: `(\/\/([^/?#]*))?`
  let mut authority = ""
  if char_code_at(value, pos) == char_forward_slash &&
    char_code_at(value, pos + 1) == char_forward_slash {
    let start = pos + 2
    let mut j = start
    while j < len {
      let code = value[j].to_int()
      if code == char_forward_slash ||
        code == '?'.to_int() ||
        code == '#'.to_int() {
        break
      }
      j += 1
    }
    authority = js_slice(value, start, end=j)
    pos = j
  }

  // path: `([^?#]*)`
  let path_start = pos
  let mut j = pos
  while j < len {
    let code = value[j].to_int()
    if code == '?'.to_int() || code == '#'.to_int() {
      break
    }
    j += 1
  }
  let path = js_slice(value, path_start, end=j)
  pos = j

  // query: `(\?([^#]*))?`
  let mut query = ""
  if char_code_at(value, pos) == '?'.to_int() {
    let start = pos + 1
    let mut k = start
    while k < len && value[k].to_int() != '#'.to_int() {
      k += 1
    }
    query = js_slice(value, start, end=k)
    pos = k
  }

  // fragment: `(#(.*))?` — JS `.` (no /s flag) stops at line terminators.
  let mut fragment = ""
  if char_code_at(value, pos) == '#'.to_int() {
    let start = pos + 1
    let mut k = start
    while k < len {
      let code = value[k].to_int()
      if code == '\n'.to_int() ||
        code == '\r'.to_int() ||
        code == 0x2028 ||
        code == 0x2029 {
        break
      }
      k += 1
    }
    fragment = js_slice(value, start, end=k)
  }
  (scheme, authority, path, query, fragment)
}

///|
/// `URI.parse` (uri.ts:271): creates a new URI from a string, e.g.
/// `http://www.example.com/some/path`, `file:///usr/home`, or
/// `scheme:with/path`. Components are percent-decoded before validation.
pub fn Uri::parse(value : String, strict? : Bool = false) -> Uri raise UriError {
  let (scheme, authority, path, query, fragment) = parse_components(value)
  Uri::new_(
    scheme,
    percent_decode(authority),
    percent_decode(path),
    percent_decode(query),
    percent_decode(fragment),
    strict,
  )
}

///|
/// `URI.file` (uri.ts:307): creates a new URI from a file system path, e.g.
/// `c:\my\files`, `/usr/home`, or `\\server\share\some\path`.
///
/// The *difference* between `Uri::parse` and `Uri::file` is that the latter
/// treats the argument as path, not as stringified-uri: the path might
/// contain characters that are interpreted (`#` and `?`).
///
/// Validation cannot fail on this shape (scheme `file`, slash-rooted path),
/// so unlike `parse`/`from` this stays non-raising (D6).
pub fn Uri::file(path : String) -> Uri {
  let mut path = path
  let mut authority = ""

  // normalize to fwd-slashes on windows,
  // on other systems bwd-slashes are valid
  // filename character, eg /f\oo/ba\r.txt
  if platform_is_win32() {
    path = path.replace_all(old="\\", new="/")
  }

  // check for authority as used in UNC shares
  // or use the path as given
  if char_code_at(path, 0) == char_forward_slash &&
    char_code_at(path, 1) == char_forward_slash {
    let idx = index_of_char(path, char_forward_slash, 2)
    if idx == -1 {
      authority = js_slice(path, 2)
      path = "/"
    } else {
      authority = js_slice(path, 2, end=idx)
      path = js_slice(path, idx)
      if path == "" {
        path = "/"
      }
    }
  }
  try! Uri::new_("file", authority, path, "", "", false)
}

///|
/// `URI.from` (uri.ts:341): creates a new URI from uri components with
/// validation — use for untrusted components from storage, user input,
/// command arguments etc. Unless `strict` the scheme defaults to `file`.
pub fn Uri::from(
  scheme~ : String,
  authority? : String = "",
  path? : String = "",
  query? : String = "",
  fragment? : String = "",
  strict? : Bool = false,
) -> Uri raise UriError {
  Uri::new_(scheme, authority, path, query, fragment, strict)
}

///|
/// `URI.with` (uri.ts:218). Monaco's undefined/null distinction maps to
/// optional named args: omitted = keep, `Some("")` = clear (Monaco maps null
/// to `''` anyway, uri.ts:227-249, D6). Returns `self` unchanged when every
/// component matches (uri.ts:251).
pub fn Uri::with_(
  self : Uri,
  scheme? : String,
  authority? : String,
  path? : String,
  query? : String,
  fragment? : String,
) -> Uri raise UriError {
  let scheme = match scheme {
    Some(value) => value
    None => self.scheme
  }
  let authority = match authority {
    Some(value) => value
    None => self.authority
  }
  let path = match path {
    Some(value) => value
    None => self.path
  }
  let query = match query {
    Some(value) => value
    None => self.query
  }
  let fragment = match fragment {
    Some(value) => value
    None => self.fragment
  }
  if scheme == self.scheme &&
    authority == self.authority &&
    path == self.path &&
    query == self.query &&
    fragment == self.fragment {
    return self
  }
  Uri::new_(scheme, authority, path, query, fragment, false)
}

///|
/// `URI.joinPath` (uri.ts:360): join a URI path with path fragments and
/// normalize the resulting path. Aborts on a URI without path, matching
/// Monaco's unconditional throw (programmer error, D6).
pub fn Uri::join_path(uri : Uri, path_fragment : Array[String]) -> Uri {
  if uri.path == "" {
    abort(
      "[UriError]: cannot call joinPath on URI without path: \{uri.to_string()}",
    )
  }
  let new_path = if platform_is_win32() && uri.scheme == "file" {
    Uri::file(Win32::join([uri_to_fs_path(uri, true)] + path_fragment)).path
  } else {
    Posix::join([uri.path] + path_fragment)
  }
  // The joined path keeps the validated shape of `uri.path`, so the
  // re-validation inside `with_` cannot fail (D6).
  try! uri.with_(path=new_path)
}

///|
/// `toString(skipEncoding)` (uri.ts:386, caching override uri.ts:467-477):
/// guaranteed to round-trip through `Uri::parse` into an equal URI. The
/// result is percent-encoded (mostly ignoring scheme-specific rules) and is
/// meant for externalization or transport, not display.
pub fn Uri::to_string(self : Uri, skip_encoding? : Bool = false) -> String {
  if !skip_encoding {
    match self.formatted_cache {
      Some(formatted) => formatted
      None => {
        let formatted = as_formatted(self, false)
        self.formatted_cache = Some(formatted)
        formatted
      }
    }
  } else {
    // we don't cache that
    as_formatted(self, true)
  }
}

///|
/// The `fsPath` getter (uri.ts:209, caching override uri.ts:460-465):
/// platform-specific file system path for this URI. Handles UNC paths
/// (`file://server/share` → `//server/share` resp. `\\server\share`) and
/// normalizes windows drive letters to lower-case. Does not validate the
/// path and does not look at the scheme.
pub fn Uri::fs_path(self : Uri) -> String {
  match self.fs_path_cache {
    Some(fs_path) => fs_path
    None => {
      let fs_path = uri_to_fs_path(self, false)
      self.fs_path_cache = Some(fs_path)
      fs_path
    }
  }
}

///|
/// `encodeTable` (uri.ts:517) — reserved characters
/// https://tools.ietf.org/html/rfc3986#section-2.2.
fn encode_table(code : Int) -> String? {
  match code {
    58 => Some("%3A") // gen-delims: colon
    47 => Some("%2F") // slash
    63 => Some("%3F") // question mark
    35 => Some("%23") // hash
    91 => Some("%5B") // open square bracket
    93 => Some("%5D") // close square bracket
    64 => Some("%40") // at sign
    33 => Some("%21") // sub-delims: exclamation mark
    36 => Some("%24") // dollar sign
    38 => Some("%26") // ampersand
    39 => Some("%27") // single quote
    40 => Some("%28") // open paren
    41 => Some("%29") // close paren
    42 => Some("%2A") // asterisk
    43 => Some("%2B") // plus
    44 => Some("%2C") // comma
    59 => Some("%3B") // semicolon
    61 => Some("%3D") // equals
    32 => Some("%20") // space
    _ => None
  }
}

///|
let hex_digits_upper : String = "0123456789ABCDEF"

///|
fn write_percent_byte(sb : StringBuilder, byte : Int) -> Unit {
  sb.write_char('%')
  sb.write_char(Int::unsafe_to_char(hex_digits_upper[byte >> 4].to_int()))
  sb.write_char(Int::unsafe_to_char(hex_digits_upper[byte & 0xF].to_int()))
}

///|
/// The delegated-span replacement for JS `encodeURIComponent` (uri.ts:564,
/// 599; D4): UTF-8 percent-encode every code point in `[start, end)` of `s`
/// with uppercase hex. Chars reaching this path are exactly those outside
/// the fast-path sets, and `encodeURIComponent` escapes all of them. A lone
/// surrogate aborts the way JS throws `URIError`.
fn write_native_encoded(
  sb : StringBuilder,
  s : String,
  start : Int,
  end : Int,
) -> Unit {
  let mut i = start
  while i < end {
    let unit = s[i].to_int()
    let mut code_point = unit
    if is_high_surrogate(unit) {
      if i + 1 < end && is_low_surrogate(s[i + 1].to_int()) {
        code_point = 0x10000 +
          ((unit - 0xD800) << 10) +
          (s[i + 1].to_int() - 0xDC00)
        i += 1
      } else {
        abort("URIError: URI malformed")
      }
    } else if is_low_surrogate(unit) {
      abort("URIError: URI malformed")
    }
    if code_point < 0x80 {
      write_percent_byte(sb, code_point)
    } else if code_point < 0x800 {
      write_percent_byte(sb, 0xC0 | (code_point >> 6))
      write_percent_byte(sb, 0x80 | (code_point & 0x3F))
    } else if code_point < 0x10000 {
      write_percent_byte(sb, 0xE0 | (code_point >> 12))
      write_percent_byte(sb, 0x80 | ((code_point >> 6) & 0x3F))
      write_percent_byte(sb, 0x80 | (code_point & 0x3F))
    } else {
      write_percent_byte(sb, 0xF0 | (code_point >> 18))
      write_percent_byte(sb, 0x80 | ((code_point >> 12) & 0x3F))
      write_percent_byte(sb, 0x80 | ((code_point >> 6) & 0x3F))
      write_percent_byte(sb, 0x80 | (code_point & 0x3F))
    }
    i += 1
  }
}

///|
/// `encodeURIComponentFast` (uri.ts:541): unreserved fast path (`isPath`
/// keeps `/`, `isAuthority` keeps `[ ] :`), table escapes, delayed
/// native-encode spans, and allocate-only-on-change (`None` result means the
/// input passed through untouched).
fn encode_uri_component_fast(
  uri_component : String,
  is_path : Bool,
  is_authority : Bool,
) -> String {
  let mut res : StringBuilder? = None
  let mut native_encode_pos = -1
  for pos in 0..<uri_component.length() {
    let code = uri_component[pos].to_int()

    // unreserved characters: https://tools.ietf.org/html/rfc3986#section-2.3
    if (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
      (code >= 'A'.to_int() && code <= 'Z'.to_int()) ||
      (code >= '0'.to_int() && code <= '9'.to_int()) ||
      code == '-'.to_int() ||
      code == '.'.to_int() ||
      code == '_'.to_int() ||
      code == '~'.to_int() ||
      (is_path && code == char_forward_slash) ||
      (is_authority && code == '['.to_int()) ||
      (is_authority && code == ']'.to_int()) ||
      (is_authority && code == char_colon) {
      // check if we are delaying native encode
      if native_encode_pos != -1 {
        match res {
          Some(sb) =>
            write_native_encoded(sb, uri_component, native_encode_pos, pos)
          None => () // unreachable: a delayed span implies an allocation
        }
        native_encode_pos = -1
      }
      // check if we write into a new string (by default we try to return the param)
      match res {
        Some(sb) => sb.write_char(Int::unsafe_to_char(code))
        None => ()
      }
    } else {
      // encoding needed, we need to allocate a new string
      if res is None {
        let sb = StringBuilder::new()
        sb.write_string(js_slice(uri_component, 0, end=pos))
        res = Some(sb)
      }

      // check with default table first
      match encode_table(code) {
        Some(escaped) => {
          // check if we are delaying native encode
          if native_encode_pos != -1 {
            match res {
              Some(sb) =>
                write_native_encoded(sb, uri_component, native_encode_pos, pos)
              None => ()
            }
            native_encode_pos = -1
          }
          // append escaped variant to result
          match res {
            Some(sb) => sb.write_string(escaped)
            None => ()
          }
        }
        None =>
          // use native encode only when needed
          if native_encode_pos == -1 {
            native_encode_pos = pos
          }
      }
    }
  }
  if native_encode_pos != -1 {
    match res {
      Some(sb) =>
        write_native_encoded(
          sb,
          uri_component,
          native_encode_pos,
          uri_component.length(),
        )
      None => ()
    }
  }
  match res {
    Some(sb) => sb.to_string()
    None => uri_component
  }
}

///|
/// `encodeURIComponentMinimal` (uri.ts:605): only `#` and `?` are escaped.
/// Literal runs are copied as substring chunks (boundaries sit on the ASCII
/// `#`/`?`, so surrogate pairs are never split).
fn encode_uri_component_minimal(path : String) -> String {
  let mut res : StringBuilder? = None
  let mut chunk_start = 0
  for pos in 0..<path.length() {
    let code = path[pos].to_int()
    if code == '#'.to_int() || code == '?'.to_int() {
      let sb = match res {
        None => {
          let sb = StringBuilder::new()
          res = Some(sb)
          sb
        }
        Some(sb) => sb
      }
      sb.write_string(js_slice(path, chunk_start, end=pos))
      match encode_table(code) {
        Some(escaped) => sb.write_string(escaped)
        None => () // unreachable: `#` and `?` are in the table
      }
      chunk_start = pos + 1
    }
  }
  match res {
    None => path
    Some(sb) => {
      sb.write_string(js_slice(path, chunk_start))
      sb.to_string()
    }
  }
}

///|
/// `uriToFsPath` (uri.ts:626): computes `fsPath` for the given uri — UNC
/// form for file-URIs with authority, lower-cased drive letters unless
/// `keep_drive_letter_casing`, and backslashes on windows.
pub fn uri_to_fs_path(uri : Uri, keep_drive_letter_casing : Bool) -> String {
  let mut value = ""
  if uri.authority != "" && uri.path.length() > 1 && uri.scheme == "file" {
    // unc path: file://shares/c$/far/boo
    value = "//" + uri.authority + uri.path
  } else if char_code_at(uri.path, 0) == char_forward_slash &&
    (
      (
        char_code_at(uri.path, 1) >= 'A'.to_int() &&
        char_code_at(uri.path, 1) <= 'Z'.to_int()
      ) ||
      (
        char_code_at(uri.path, 1) >= 'a'.to_int() &&
        char_code_at(uri.path, 1) <= 'z'.to_int()
      )
    ) &&
    char_code_at(uri.path, 2) == char_colon {
    if !keep_drive_letter_casing {
      // windows drive letter: file:///c:/far/boo
      value = to_lower_js(js_slice(uri.path, 1, end=2)) + js_slice(uri.path, 2)
    } else {
      value = js_slice(uri.path, 1)
    }
  } else {
    // other path
    value = uri.path
  }
  if platform_is_win32() {
    value = value.replace_all(old="/", new="\\")
  }
  value
}

///|
/// `_asFormatted` (uri.ts:656): create the external version of a uri.
fn as_formatted(uri : Uri, skip_encoding : Bool) -> String {
  let encoder : (String, Bool, Bool) -> String = if !skip_encoding {
    encode_uri_component_fast
  } else {
    (component, _is_path, _is_authority) => {
      encode_uri_component_minimal(component)
    }
  }
  let mut res = ""
  let scheme = uri.scheme
  let mut authority = uri.authority
  let mut path = uri.path
  let query = uri.query
  let fragment = uri.fragment
  if scheme != "" {
    res = res + scheme + ":"
  }
  if authority != "" || scheme == "file" {
    res = res + "//"
  }
  if authority != "" {
    let mut idx = index_of_char(authority, '@'.to_int(), 0)
    if idx != -1 {
      // <user>@<auth>
      let userinfo = js_slice(authority, 0, end=idx)
      authority = js_slice(authority, idx + 1)
      idx = last_index_of_char(userinfo, char_colon)
      if idx == -1 {
        res = res + encoder(userinfo, false, false)
      } else {
        // <user>:<pass>@<auth>
        res = res + encoder(js_slice(userinfo, 0, end=idx), false, false)
        res = res + ":"
        res = res + encoder(js_slice(userinfo, idx + 1), false, true)
      }
      res = res + "@"
    }
    authority = to_lower_js(authority)
    idx = last_index_of_char(authority, char_colon)
    if idx == -1 {
      res = res + encoder(authority, false, true)
    } else {
      // <auth>:<port>
      res = res + encoder(js_slice(authority, 0, end=idx), false, true)
      res = res + js_slice(authority, idx)
    }
  }
  if path != "" {
    // lower-case windows drive letters in /C:/fff or C:/fff
    if path.length() >= 3 &&
      char_code_at(path, 0) == char_forward_slash &&
      char_code_at(path, 2) == char_colon {
      let code = char_code_at(path, 1)
      if code >= 'A'.to_int() && code <= 'Z'.to_int() {
        path = "/" +
          Int::unsafe_to_char(code + 32).to_string() +
          ":" +
          js_slice(path, 3) // "/c:".length === 3
      }
    } else if path.length() >= 2 && char_code_at(path, 1) == char_colon {
      let code = char_code_at(path, 0)
      if code >= 'A'.to_int() && code <= 'Z'.to_int() {
        path = Int::unsafe_to_char(code + 32).to_string() +
          ":" +
          js_slice(path, 2) // "/c:".length === 3
      }
    }
    // encode the rest of the path
    res = res + encoder(path, true, false)
  }
  if query != "" {
    res = res + "?" + encoder(query, false, false)
  }
  if fragment != "" {
    res = res +
      "#" +
      (if !skip_encoding {
        encode_uri_component_fast(fragment, false, false)
      } else {
        fragment
      })
  }
  res
}

///|
fn last_index_of_char(s : String, code : Int) -> Int {
  for i = s.length() - 1; i >= 0; i = i - 1 {
    if s[i].to_int() == code {
      return i
    }
  }
  -1
}

///|
/// Internal decode failure — only used to drive
/// `decode_uri_component_graceful`'s keep-raw fallback (D4).
priv suberror UriDecodeError {
  UriDecodeError(String)
}

///|
fn hex_digit_value(code : Int) -> Int raise UriDecodeError {
  if code >= '0'.to_int() && code <= '9'.to_int() {
    code - '0'.to_int()
  } else if code >= 'A'.to_int() && code <= 'F'.to_int() {
    code - 'A'.to_int() + 10
  } else if code >= 'a'.to_int() && code <= 'f'.to_int() {
    code - 'a'.to_int() + 10
  } else {
    raise UriDecodeError("URI malformed")
  }
}

///|
/// Reads a `%XX` escape starting at `at`: `%` plus two hex digits.
fn read_percent_byte(s : String, at : Int) -> Int raise UriDecodeError {
  if at + 2 >= s.length() || s[at].to_int() != '%'.to_int() {
    raise UriDecodeError("URI malformed")
  }
  (hex_digit_value(s[at + 1].to_int()) << 4) |
  hex_digit_value(s[at + 2].to_int())
}

///|
/// JS `decodeURIComponent` reimplemented as strict UTF-8 percent
/// transcoding (D4): invalid `%` sequences, invalid/overlong UTF-8, and
/// surrogate/out-of-range code points all fail, exactly the inputs that make
/// the JS builtin throw `URIError`.
fn decode_uri_component(str : String) -> String raise UriDecodeError {
  let sb = StringBuilder::new()
  let len = str.length()
  let mut i = 0
  let mut chunk_start = 0
  while i < len {
    if str[i].to_int() == '%'.to_int() {
      sb.write_string(js_slice(str, chunk_start, end=i))
      let byte0 = read_percent_byte(str, i)
      if byte0 < 0x80 {
        sb.write_char(Int::unsafe_to_char(byte0))
        i += 3
      } else {
        // multi-byte sequence: every continuation must itself be a
        // percent-escape (a literal char in between makes JS throw)
        let (extra, min_second, max_second) = if byte0 >= 0xC2 && byte0 <= 0xDF {
          (1, 0x80, 0xBF)
        } else if byte0 == 0xE0 {
          (2, 0xA0, 0xBF)
        } else if byte0 >= 0xE1 && byte0 <= 0xEC {
          (2, 0x80, 0xBF)
        } else if byte0 == 0xED {
          (2, 0x80, 0x9F)
        } else if byte0 >= 0xEE && byte0 <= 0xEF {
          (2, 0x80, 0xBF)
        } else if byte0 == 0xF0 {
          (3, 0x90, 0xBF)
        } else if byte0 >= 0xF1 && byte0 <= 0xF3 {
          (3, 0x80, 0xBF)
        } else if byte0 == 0xF4 {
          (3, 0x80, 0x8F)
        } else {
          raise UriDecodeError("URI malformed")
        }
        let mut code_point = match extra {
          1 => byte0 & 0x1F
          2 => byte0 & 0x0F
          _ => byte0 & 0x07
        }
        for k in 1..<=extra {
          let cont = read_percent_byte(str, i + 3 * k)
          let (min, max) = if k == 1 {
            (min_second, max_second)
          } else {
            (0x80, 0xBF)
          }
          if cont < min || cont > max {
            raise UriDecodeError("URI malformed")
          }
          code_point = (code_point << 6) | (cont & 0x3F)
        }
        sb.write_char(Int::unsafe_to_char(code_point))
        i += 3 * (extra + 1)
      }
      chunk_start = i
    } else {
      i += 1
    }
  }
  sb.write_string(js_slice(str, chunk_start))
  sb.to_string()
}

///|
/// `decodeURIComponentGraceful` (uri.ts:728): decode; on failure keep the
/// raw 3-char prefix and retry the rest recursively.
fn decode_uri_component_graceful(str : String) -> String {
  decode_uri_component(str) catch {
    UriDecodeError(_) =>
      if str.length() > 3 {
        js_slice(str, 0, end=3) +
        decode_uri_component_graceful(js_slice(str, 3))
      } else {
        str
      }
  }
}

///|
/// `%XY` where X and Y are `[0-9A-Za-z]` — the (deliberately loose)
/// `_rEncodedAsHex` character class (uri.ts:740).
fn is_encoded_as_hex_at(str : String, pos : Int) -> Bool {
  fn hexish(code : Int) -> Bool {
    (code >= '0'.to_int() && code <= '9'.to_int()) ||
    (code >= 'A'.to_int() && code <= 'Z'.to_int()) ||
    (code >= 'a'.to_int() && code <= 'z'.to_int())
  }

  pos + 2 < str.length() &&
  str[pos].to_int() == '%'.to_int() &&
  hexish(str[pos + 1].to_int()) &&
  hexish(str[pos + 2].to_int())
}

///|
/// `percentDecode` (uri.ts:742): pass through when no `(%[0-9A-Za-z]{2})+`
/// run exists; otherwise replace each maximal run gracefully (scanner
/// replaces the regex, D3).
fn percent_decode(str : String) -> String {
  let len = str.length()
  let mut pos = 0
  let mut found = false
  while pos < len {
    if is_encoded_as_hex_at(str, pos) {
      found = true
      break
    }
    pos += 1
  }
  if !found {
    return str
  }
  let sb = StringBuilder::new()
  let mut chunk_start = 0
  let mut i = 0
  while i < len {
    if is_encoded_as_hex_at(str, i) {
      let run_start = i
      while is_encoded_as_hex_at(str, i) {
        i += 3
      }
      sb.write_string(js_slice(str, chunk_start, end=run_start))
      sb.write_string(
        decode_uri_component_graceful(js_slice(str, run_start, end=i)),
      )
      chunk_start = i
    } else {
      i += 1
    }
  }
  sb.write_string(js_slice(str, chunk_start))
  sb.to_string()
}
