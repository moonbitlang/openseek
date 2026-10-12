///| Port of `vscode/src/vs/base/common/resources.ts` in the checked-in vscode
/// source: the reachable `ExtUri` comparison/derivation layer, its three
/// exported instances, and the bound top-level exports used by the viewer.
/// `distinctParents`/`DataUri`/`toLocalResource` are DEFERRED (no consumer).
///
/// The `resource.with_(...)` calls re-validate (D6); every path handed to
/// them keeps the already-validated shape of the input URI, so the `try!`
/// can never abort.
///
/// Two of Monaco's sixteen bound exports — `dirname` and `isEqualOrParent` —
/// are NOT re-exported at top level: Monaco disambiguates them from
/// `paths.dirname` / `extpath.isEqualOrParent` by module, and this flat
/// package cannot; call `ext_uri.dirname` / `ext_uri.is_equal_or_parent`.

///|
/// `originalFSPath` (resources.ts:14).
fn original_fs_path(uri : Uri) -> String {
  uri_to_fs_path(uri, true)
}

///|
/// `ExtUri` (resources.ts:139) — the single `IExtUri` implementation,
/// parameterized by the `_ignorePathCasing` closure.
struct ExtUri {
  ignore_path_casing_fn : (Uri) -> Bool
}

///|
fn ExtUri::ExtUri(ignore_path_casing : (Uri) -> Bool) -> ExtUri {
  { ignore_path_casing_fn: ignore_path_casing, }
}

///|
/// `compare` (resources.ts:143): compares two uris. Must use the ported
/// `strings.compare` — MoonBit's built-in `String` compare is length-first.
fn ExtUri::compare_impl(
  self : ExtUri,
  uri1 : Uri,
  uri2 : Uri,
  ignore_fragment~ : Bool = false,
) -> Int32 {
  if physical_equal(uri1, uri2) {
    return 0
  }
  compare(
    self.get_comparison_key(uri1, ignore_fragment~),
    self.get_comparison_key(uri2, ignore_fragment~),
  )
}

///|
/// `isEqual` (resources.ts:150): tests whether two uris are equal.
fn ExtUri::is_equal_impl(
  self : ExtUri,
  uri1 : Uri?,
  uri2 : Uri?,
  ignore_fragment~ : Bool = false,
) -> Bool {
  match (uri1, uri2) {
    (None, None) => true
    (Some(u1), Some(u2)) =>
      physical_equal(u1, u2) ||
      self.get_comparison_key(u1, ignore_fragment~) ==
      self.get_comparison_key(u2, ignore_fragment~)
    _ => false
  }
}

///|
/// `getComparisonKey` (resources.ts:160): creates a key from a resource URI
/// to be used for resource comparison and for resource maps.
fn ExtUri::get_comparison_key_impl(
  self : ExtUri,
  uri : Uri,
  ignore_fragment~ : Bool = false,
) -> String {
  let path : String? = if (self.ignore_path_casing_fn)(uri) {
    Some(to_lower_js(uri.path))
  } else {
    None
  }
  let fragment : String? = if ignore_fragment { Some("") } else { None }
  (try! uri.with_(path?, fragment?)).to_string()
}

///|
/// `ignorePathCasing` (resources.ts:167): whether the casing of the
/// path-component of the uri should be ignored.
fn ExtUri::ignore_path_casing_impl(self : ExtUri, uri : Uri) -> Bool {
  (self.ignore_path_casing_fn)(uri)
}

///|
/// `isEqualOrParent` (resources.ts:171): tests whether a `parent_candidate`
/// URI is a parent or equal of a given `base` URI.
fn ExtUri::is_equal_or_parent_impl(
  self : ExtUri,
  base : Uri,
  parent_candidate : Uri,
  ignore_fragment~ : Bool = false,
) -> Bool {
  if base.scheme == parent_candidate.scheme {
    if base.scheme == schemas_file {
      return is_equal_or_parent(
          original_fs_path(base),
          original_fs_path(parent_candidate),
          (self.ignore_path_casing_fn)(base),
        ) &&
        base.query == parent_candidate.query &&
        (ignore_fragment || base.fragment == parent_candidate.fragment)
    }
    if is_equal_authority(base.authority, parent_candidate.authority) {
      return is_equal_or_parent(
          base.path,
          parent_candidate.path,
          (self.ignore_path_casing_fn)(base),
          force_posix_semantics=true,
        ) &&
        base.query == parent_candidate.query &&
        (ignore_fragment || base.fragment == parent_candidate.fragment)
    }
  }
  false
}

// --- path math

///|
/// `joinPath` (resources.ts:185).
fn ExtUri::join_path_impl(
  self : ExtUri,
  resource : Uri,
  path_fragment : Array[String],
) -> Uri {
  ignore(self)
  Uri::join_path(resource, path_fragment)
}

///|
/// `basenameOrAuthority` (resources.ts:189).
fn ExtUri::basename_or_authority_impl(self : ExtUri, resource : Uri) -> String {
  let name = self.basename(resource)
  if name != "" {
    name
  } else {
    resource.authority
  }
}

///|
/// `basename` (resources.ts:193): the basename of the path component of an
/// uri.
fn ExtUri::basename_impl(
  self : ExtUri,
  resource : Uri,
  suffix? : String,
) -> String {
  ignore(self)
  Posix::basename(resource.path, suffix?)
}

///|
/// `extname` (resources.ts:197): the extension of the path component of an
/// uri.
fn ExtUri::extname_impl(self : ExtUri, resource : Uri) -> String {
  ignore(self)
  Posix::extname(resource.path)
}

///|
/// `dirname` (resources.ts:201): a URI representing the directory of a URI
/// path.
fn ExtUri::dirname_impl(self : ExtUri, resource : Uri) -> Uri {
  ignore(self)
  if resource.path.length() == 0 {
    return resource
  }
  let mut dir = ""
  if resource.scheme == schemas_file {
    dir = Uri::file(dirname(original_fs_path(resource))).path
  } else {
    dir = Posix::dirname(resource.path)
    if resource.authority != "" &&
      dir.length() > 0 &&
      char_code_at(dir, 0) != char_forward_slash {
      // Monaco logs `dirname(...) resulted in a relative path` here.
      // If a URI contains an authority component, then the path component
      // must either be empty or begin with a slash ("/") character
      dir = "/"
    }
  }
  try! resource.with_(path=dir)
}

///|
/// `normalizePath` (resources.ts:220): resolves `.` and `..` elements of the
/// path with directory names.
fn ExtUri::normalize_path_impl(self : ExtUri, resource : Uri) -> Uri {
  ignore(self)
  if resource.path.length() == 0 {
    return resource
  }
  let normalized_path = if resource.scheme == schemas_file {
    Uri::file(normalize(original_fs_path(resource))).path
  } else {
    Posix::normalize(resource.path)
  }
  try! resource.with_(path=normalized_path)
}

///|
/// `relativePath` (resources.ts:235).
fn ExtUri::relative_path_impl(self : ExtUri, from : Uri, to : Uri) -> String? {
  if from.scheme != to.scheme ||
    !is_equal_authority(from.authority, to.authority) {
    return None
  }
  if from.scheme == schemas_file {
    let rel = relative(original_fs_path(from), original_fs_path(to))
    return Some(if platform_is_win32() { to_slashes(rel) } else { rel })
  }
  let from_path = if from.path == "" { "/" } else { from.path }
  let to_path = if to.path == "" { "/" } else { to.path }
  let from_path = if (self.ignore_path_casing_fn)(from) {
    // make casing of fromPath match toPath
    let len = from_path.length().min(to_path.length())
    let i = for i = 0; i < len; {
      if from_path[i].to_int() != to_path[i].to_int() {
        if to_lower_js(js_slice(from_path, i, end=i + 1)) !=
          to_lower_js(js_slice(to_path, i, end=i + 1)) {
          break i
        }
      }
      continue i + 1
    } nobreak {
      i
    }
    js_slice(to_path, 0, end=i) + js_slice(from_path, i)
  } else {
    from_path
  }
  Some(Posix::relative(from_path, to_path))
}

///|
/// `resolvePath` (resources.ts:260): resolves an absolute or relative path
/// against a base URI. The path can be relative or absolute posix or a
/// Windows path.
fn ExtUri::resolve_path_impl(self : ExtUri, base : Uri, path : String) -> Uri {
  ignore(self)
  if base.scheme == schemas_file {
    let new_uri = Uri::file(resolve([original_fs_path(base), path]))
    return try! base.with_(authority=new_uri.authority, path=new_uri.path)
  }
  let path = to_posix_path(path) // we allow path to be a windows path
  try! base.with_(path=Posix::resolve([base.path, path]))
}

// --- misc

///|
/// `isAbsolutePath` (resources.ts:276).
fn ExtUri::is_absolute_path_impl(self : ExtUri, resource : Uri) -> Bool {
  ignore(self)
  resource.path != "" && char_code_at(resource.path, 0) == char_forward_slash
}

///|
/// `isEqualAuthority` (resources.ts:280): tests whether the two authorities
/// are the same.
fn ExtUri::is_equal_authority_impl(
  self : ExtUri,
  a1 : String,
  a2 : String,
) -> Bool {
  ignore(self)
  a1 == a2 || equals_ignore_case(a1, a2)
}

///|
/// `hasTrailingPathSeparator` (resources.ts:284): true if the URI path has a
/// trailing path separator.
fn ExtUri::has_trailing_path_separator_impl(
  self : ExtUri,
  resource : Uri,
  sep? : String,
) -> Bool {
  ignore(self)
  let sep = match sep {
    Some(value) => value
    None => if platform_is_win32() { Win32::sep() } else { Posix::sep() }
  }
  if resource.scheme == schemas_file {
    let fsp = original_fs_path(resource)
    fsp.length() > get_root(fsp).length() &&
    js_slice(fsp, fsp.length() - 1) == sep
  } else {
    let p = resource.path
    // ignore the slash at offset 0; the regex guard is
    // `^[a-zA-Z]:(\/$|\\$)` on the fsPath (drive roots keep their slash)
    let fsp = resource.fs_path()
    let is_drive_root = fsp.length() == 3 &&
      is_windows_drive_letter(char_code_at(fsp, 0)) &&
      char_code_at(fsp, 1) == char_colon &&
      (
        char_code_at(fsp, 2) == char_forward_slash ||
        char_code_at(fsp, 2) == char_backward_slash
      )
    p.length() > 1 &&
    char_code_at(p, p.length() - 1) == char_forward_slash &&
    !is_drive_root
  }
}

///|
/// `removeTrailingPathSeparator` (resources.ts:294): removes a trailing path
/// separator, if there's one. Important: doesn't remove the first slash —
/// that would make the URI invalid.
fn ExtUri::remove_trailing_path_separator_impl(
  self : ExtUri,
  resource : Uri,
  sep? : String,
) -> Uri {
  ignore(self)
  // Make sure that the path isn't a drive letter. A trailing separator
  // there is not removable. (Monaco calls the module-level bound export,
  // i.e. `ext_uri`'s, regardless of the instance.)
  if has_trailing_path_separator(resource, sep?) {
    return try! resource.with_(
      path=js_slice(resource.path, 0, end=resource.path.length() - 1),
    )
  }
  resource
}

///|
/// `extUri` (resources.ts:327): unbiased utility that takes uris "as they
/// are" — interchangeable with `uri.to_string()` usages:
/// `(a.to_string() == b.to_string()) == ext_uri.is_equal(a, b)`.
let ext_uri_impl : ExtUri = ExtUri(_uri => false)

///|
/// `extUriBiasedIgnorePathCase` (resources.ts:340): BIASED utility that
/// _mostly_ ignores the case of uri paths — a file-scheme resource is on the
/// same platform as the code, so case is ignored on non-Linux platforms.
/// INCOMPATIBLE with `uri.to_string()` usages.
let ext_uri_biased_ignore_path_case_impl : ExtUri = ExtUri(uri => {
  if uri.scheme == schemas_file {
    !is_linux
  } else {
    true
  }
})

///|
/// `extUriIgnorePathCase` (resources.ts:358): BIASED utility that always
/// ignores the casing of uri paths. INCOMPATIBLE with `uri.to_string()`
/// usages.
let ext_uri_ignore_path_case_impl : ExtUri = ExtUri(_uri => true)

// --- bound exports (resources.ts:360-375), delegating to `ext_uri`.
// `dirname` and `isEqualOrParent` are omitted here — see the file header.

///|
pub fn basename_or_authority(resource : Uri) -> String {
  ext_uri_impl.basename_or_authority_impl(resource)
}

///|
fn is_equal_authority(a1 : String, a2 : String) -> Bool {
  ext_uri_impl.is_equal_authority_impl(a1, a2)
}

///|
fn has_trailing_path_separator(resource : Uri, sep? : String) -> Bool {
  ext_uri_impl.has_trailing_path_separator_impl(resource, sep?)
}
