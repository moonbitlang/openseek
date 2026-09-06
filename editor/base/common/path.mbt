///| Port of `vscode/src/vs/base/common/path.ts` (vscode's vendored copy of
/// Node v22 `lib/path.js`), checked-in submodule.
///
/// The JS namespace objects `posix`/`win32` become zero-field namespace types
/// `Posix`/`Win32` with static-style methods; JS variadics become
/// `Array[String]` parameters (Deviation D2). `format`/`parse`/
/// `toNamespacedPath` and the unconsumed platform-selected exports are
/// deferred (no consumer). JS `charCodeAt` out-of-range NaN is modeled by
/// `char_code_at` returning `-1`, which fails every comparison the same way.

///|
let char_uppercase_a : Int = 65 // A

///|
let char_lowercase_a : Int = 97 // a

///|
let char_uppercase_z : Int = 90 // Z

///|
let char_lowercase_z : Int = 122 // z

///|
let char_dot : Int = 46 // .

///|
let char_forward_slash : Int = 47 // /

///|
let char_backward_slash : Int = 92 // \

///|
let char_colon : Int = 58 // :

///|
/// JS `str.charCodeAt(i)`: out-of-range reads yield NaN there and `-1` here;
/// both fail every equality/range comparison in this file identically.
fn char_code_at(s : String, index : Int) -> Int {
  if index < 0 || index >= s.length() {
    -1
  } else {
    s[index].to_int()
  }
}

///|
/// JS `String.prototype.slice` (negative indices count from the end, ranges
/// clamp). Cut points in this file always land on ASCII separators, so the
/// surrogate-boundary conversion cannot fail.
fn js_slice(s : String, start : Int, end? : Int) -> String {
  let len = s.length()
  let mut start = start
  let mut end = end.unwrap_or(len)
  if start < 0 {
    start += len
    if start < 0 {
      start = 0
    }
  }
  if end < 0 {
    end += len
    if end < 0 {
      end = 0
    }
  }
  if start > len {
    start = len
  }
  if end > len {
    end = len
  }
  if start >= end {
    return ""
  }
  s[start:end].to_owned()
}

///|
/// JS `str.lastIndexOf(needle)` (`-1` when absent).
fn last_index_of(s : String, needle : String) -> Int {
  s.rev_find(needle).unwrap_or(-1)
}

///|
/// JS `str.indexOf(<single char>, from)` (`-1` when absent).
fn index_of_char(s : String, code : Int, from : Int) -> Int {
  for i in from..<s.length() {
    if s[i].to_int() == code {
      return i
    }
  }
  -1
}

///|
/// JS `str.split(<single-char sep>)` semantics (keeps empty parts).
fn js_split_char(s : String, code : Int) -> Array[String] {
  let parts : Array[String] = []
  let start = for i in 0..<s.length(); start = 0 {
    if s[i].to_int() == code {
      parts.push(js_slice(s, start, end=i))
      continue i + 1
    }
  } nobreak {
    start
  }
  parts.push(js_slice(s, start))
  parts
}

///|
/// `path.ts:84 isPathSeparator`.
fn is_path_separator(code : Int) -> Bool {
  code == char_forward_slash || code == char_backward_slash
}

///|
/// `path.ts:88 isPosixPathSeparator`.
fn is_posix_path_separator(code : Int) -> Bool {
  code == char_forward_slash
}

///|
/// `path.ts:92 isWindowsDeviceRoot`.
fn is_windows_device_root(code : Int) -> Bool {
  (code >= char_uppercase_a && code <= char_uppercase_z) ||
  (code >= char_lowercase_a && code <= char_lowercase_z)
}

///|
/// `path.ts:98 normalizeString` — resolves `.` and `..` elements in a path
/// with directory names.
fn normalize_string(
  path : String,
  allow_above_root : Bool,
  separator : String,
  is_path_separator_fn : (Int) -> Bool,
) -> String {
  let mut res = ""
  let mut last_segment_length = 0
  let mut last_slash = -1
  let mut dots = 0
  let mut code = 0
  let mut i = 0
  while i <= path.length() {
    if i < path.length() {
      code = path[i].to_int()
    } else if is_path_separator_fn(code) {
      break
    } else {
      code = char_forward_slash
    }
    if is_path_separator_fn(code) {
      if last_slash == i - 1 || dots == 1 {
        // NOOP
      } else if dots == 2 {
        if res.length() < 2 ||
          last_segment_length != 2 ||
          char_code_at(res, res.length() - 1) != char_dot ||
          char_code_at(res, res.length() - 2) != char_dot {
          if res.length() > 2 {
            let last_slash_index = last_index_of(res, separator)
            if last_slash_index == -1 {
              res = ""
              last_segment_length = 0
            } else {
              res = js_slice(res, 0, end=last_slash_index)
              last_segment_length = res.length() -
                1 -
                last_index_of(res, separator)
            }
            last_slash = i
            dots = 0
            i += 1
            continue
          } else if res.length() != 0 {
            res = ""
            last_segment_length = 0
            last_slash = i
            dots = 0
            i += 1
            continue
          }
        }
        if allow_above_root {
          res = if res.length() > 0 { "\{res}\{separator}.." } else { ".." }
          last_segment_length = 2
        }
      } else {
        if res.length() > 0 {
          res = res + separator + js_slice(path, last_slash + 1, end=i)
        } else {
          res = js_slice(path, last_slash + 1, end=i)
        }
        last_segment_length = i - last_slash - 1
      }
      last_slash = i
      dots = 0
    } else if code == char_dot && dots != -1 {
      dots += 1
    } else {
      dots = -1
    }
    i += 1
  }
  res
}

///|
/// The `win32` namespace of path.ts (D2) — uninhabited namespace type; only
/// its static-style methods exist.
enum Win32 {}

///|
/// The `posix` namespace of path.ts (D2) — uninhabited namespace type; only
/// its static-style methods exist.
enum Posix {}

///|
/// `path.ts:209 win32.resolve`.
fn Win32::resolve_impl(path_segments : Array[String]) -> String {
  let mut resolved_device = ""
  let mut resolved_tail = ""
  let mut resolved_absolute = false
  let mut i = path_segments.length() - 1
  while i >= -1 {
    let mut path = ""
    if i >= 0 {
      path = path_segments[i]
      // Skip empty entries
      if path is "" {
        i -= 1
        continue
      }
    } else if resolved_device is "" {
      path = cwd()
    } else {
      // Windows has the concept of drive-specific current working
      // directories. If we've resolved a drive letter but not yet an
      // absolute path, get cwd for that drive, or the process cwd if
      // the drive cwd is not available. We're sure the device is not
      // a UNC path at this points, because UNC paths are always absolute.
      path = match env("=\{resolved_device}") {
        Some(value) => value
        None => cwd()
      }
      // Verify that a cwd was found and that it actually points
      // to our drive. If not, default to the drive's root.
      if to_lower_js(js_slice(path, 0, end=2)) != to_lower_js(resolved_device) &&
        char_code_at(path, 2) == char_backward_slash {
        path = "\{resolved_device}\\"
      }
    }
    let len = path.length()
    let mut root_end = 0
    let mut device = ""
    let mut is_abs = false
    let code = char_code_at(path, 0)

    // Try to match a root
    if len == 1 {
      if is_path_separator(code) {
        // `path` contains just a path separator
        root_end = 1
        is_abs = true
      }
    } else if is_path_separator(code) {
      // Possible UNC root

      // If we started with a separator, we know we at least have an
      // absolute path of some kind (UNC or otherwise)
      is_abs = true
      if is_path_separator(char_code_at(path, 1)) {
        // Matched double path separator at beginning
        let mut j = 2
        let mut last = j
        // Match 1 or more non-path separators
        while j < len && !is_path_separator(char_code_at(path, j)) {
          j += 1
        }
        if j < len && j != last {
          let first_part = js_slice(path, last, end=j)
          // Matched!
          last = j
          // Match 1 or more path separators
          while j < len && is_path_separator(char_code_at(path, j)) {
            j += 1
          }
          if j < len && j != last {
            // Matched!
            last = j
            // Match 1 or more non-path separators
            while j < len && !is_path_separator(char_code_at(path, j)) {
              j += 1
            }
            if j == len || j != last {
              // We matched a UNC root
              device = "\\\\\{first_part}\\\{js_slice(path, last, end=j)}"
              root_end = j
            }
          }
        }
      } else {
        root_end = 1
      }
    } else if is_windows_device_root(code) &&
      char_code_at(path, 1) == char_colon {
      // Possible device root
      device = js_slice(path, 0, end=2)
      root_end = 2
      if len > 2 && is_path_separator(char_code_at(path, 2)) {
        // Treat separator following drive name as an absolute path
        // indicator
        is_abs = true
        root_end = 3
      }
    }
    if device.length() > 0 {
      if resolved_device.length() > 0 {
        if to_lower_js(device) != to_lower_js(resolved_device) {
          // This path points to another device so it is not applicable
          i -= 1
          continue
        }
      } else {
        resolved_device = device
      }
    }
    if resolved_absolute {
      if resolved_device.length() > 0 {
        break
      }
    } else {
      resolved_tail = "\{js_slice(path, root_end)}\\\{resolved_tail}"
      resolved_absolute = is_abs
      if is_abs && resolved_device.length() > 0 {
        break
      }
    }
    i -= 1
  }

  // At this point the path should be resolved to a full absolute path,
  // but handle relative paths to be safe (might happen when process.cwd()
  // fails)

  // Normalize the tail path
  resolved_tail = normalize_string(
    resolved_tail,
    !resolved_absolute,
    "\\",
    is_path_separator,
  )
  if resolved_absolute {
    "\{resolved_device}\\\{resolved_tail}"
  } else {
    let joined = resolved_device + resolved_tail
    if joined.length() > 0 {
      joined
    } else {
      "."
    }
  }
}

///|
/// `path.ts:346 win32.normalize` (incl. the CVE-2024-36139 relative-colon
/// guard, path.ts:430-446).
fn Win32::normalize_impl(path : String) -> String {
  let len = path.length()
  if len == 0 {
    return "."
  }
  let mut root_end = 0
  let mut device : String? = None
  let mut is_abs = false
  let code = char_code_at(path, 0)

  // Try to match a root
  if len == 1 {
    // `path` contains just a single char, exit early to avoid
    // unnecessary work
    return if is_posix_path_separator(code) { "\\" } else { path }
  }
  if is_path_separator(code) {
    // Possible UNC root

    // If we started with a separator, we know we at least have an absolute
    // path of some kind (UNC or otherwise)
    is_abs = true
    if is_path_separator(char_code_at(path, 1)) {
      // Matched double path separator at beginning
      let mut j = 2
      let mut last = j
      // Match 1 or more non-path separators
      while j < len && !is_path_separator(char_code_at(path, j)) {
        j += 1
      }
      if j < len && j != last {
        let first_part = js_slice(path, last, end=j)
        // Matched!
        last = j
        // Match 1 or more path separators
        while j < len && is_path_separator(char_code_at(path, j)) {
          j += 1
        }
        if j < len && j != last {
          // Matched!
          last = j
          // Match 1 or more non-path separators
          while j < len && !is_path_separator(char_code_at(path, j)) {
            j += 1
          }
          if j == len {
            // We matched a UNC root only
            // Return the normalized version of the UNC root since there
            // is nothing left to process
            return "\\\\\{first_part}\\\{js_slice(path, last)}\\"
          }
          if j != last {
            // We matched a UNC root with leftovers
            device = Some("\\\\\{first_part}\\\{js_slice(path, last, end=j)}")
            root_end = j
          }
        }
      }
    } else {
      root_end = 1
    }
  } else if is_windows_device_root(code) && char_code_at(path, 1) == char_colon {
    // Possible device root
    device = Some(js_slice(path, 0, end=2))
    root_end = 2
    if len > 2 && is_path_separator(char_code_at(path, 2)) {
      // Treat separator following drive name as an absolute path
      // indicator
      is_abs = true
      root_end = 3
    }
  }
  let mut tail = if root_end < len {
    normalize_string(js_slice(path, root_end), !is_abs, "\\", is_path_separator)
  } else {
    ""
  }
  if tail is "" && !is_abs {
    tail = "."
  }
  if tail.length() > 0 && is_path_separator(char_code_at(path, len - 1)) {
    tail = "\{tail}\\"
  }
  if !is_abs && device is None && path.contains(":") {
    // If the original path was not absolute and if we have not been able to
    // resolve it relative to a particular device, we need to ensure that the
    // `tail` has not become something that Windows might interpret as an
    // absolute path. See CVE-2024-36139.
    if tail.length() >= 2 &&
      is_windows_device_root(char_code_at(tail, 0)) &&
      char_code_at(tail, 1) == char_colon {
      return ".\\\{tail}"
    }
    let mut index = index_of_char(path, char_colon, 0)
    while index != -1 {
      if index == len - 1 || is_path_separator(char_code_at(path, index + 1)) {
        return ".\\\{tail}"
      }
      index = index_of_char(path, char_colon, index + 1)
    }
  }
  match device {
    None => if is_abs { "\\\{tail}" } else { tail }
    Some(device) => if is_abs { "\{device}\\\{tail}" } else { device + tail }
  }
}

///|
/// `path.ts:453 win32.isAbsolute`.
fn Win32::is_absolute_impl(path : String) -> Bool {
  let len = path.length()
  if len == 0 {
    return false
  }
  let code = char_code_at(path, 0)
  is_path_separator(code) ||
  // Possible device root
  (
    len > 2 &&
    is_windows_device_root(code) &&
    char_code_at(path, 1) == char_colon &&
    is_path_separator(char_code_at(path, 2))
  )
}

///|
/// `path.ts:469 win32.join` (incl. UNC double-slash preservation,
/// path.ts:506-534).
fn Win32::join_impl(paths : Array[String]) -> String {
  if paths is [] {
    return "."
  }
  let (joined, first_part) = for
    arg in paths
    joined = (None : String?), first_part = (None : String?) {
    if arg.length() > 0 {
      match joined {
        None => continue Some(arg), Some(arg)
        Some(so_far) => continue Some("\{so_far}\\\{arg}"), first_part
      }
    }
  } nobreak {
    (joined, first_part)
  }
  guard joined is Some(joined_value) else { return "." }
  let mut joined = joined_value

  // Make sure that the joined path doesn't start with two slashes, because
  // normalize() will mistake it for a UNC path then.
  //
  // This step is skipped when it is very clear that the user actually
  // intended to point at a UNC path. This is assumed when the first
  // non-empty string arguments starts with exactly two slashes followed by
  // at least one more non-slash character.
  //
  // Note that for normalize() to treat a path as a UNC path it needs to
  // have at least 2 components, so we don't filter for that here.
  // This means that the user can use join to construct UNC paths from
  // a server name and a share name; for example:
  //   path.join('//server', 'share') -> '\\\\server\\share\\')
  let mut needs_replace = true
  let mut slash_count = 0
  match first_part {
    Some(first_part) if is_path_separator(char_code_at(first_part, 0)) => {
      slash_count += 1
      let first_len = first_part.length()
      if first_len > 1 && is_path_separator(char_code_at(first_part, 1)) {
        slash_count += 1
        if first_len > 2 {
          if is_path_separator(char_code_at(first_part, 2)) {
            slash_count += 1
          } else {
            // We matched a UNC path in the first part
            needs_replace = false
          }
        }
      }
    }
    _ => ()
  }
  if needs_replace {
    // Find any more consecutive slashes we need to replace
    while slash_count < joined.length() &&
          is_path_separator(char_code_at(joined, slash_count)) {
      slash_count += 1
    }

    // Replace the slashes if needed
    if slash_count >= 2 {
      joined = "\\\{js_slice(joined, slash_count)}"
    }
  }
  Win32::normalize(joined)
}

///|
/// `path.ts:544 win32.relative` — solves the relative path from `from` to
/// `to`, lowercase-insensitively; the split-path branch (path.ts:566-600)
/// handles resolve outputs whose lowercase form changed length.
fn Win32::relative_impl(from : String, to : String) -> String {
  if from == to {
    return ""
  }
  let from_orig = Win32::resolve([from])
  let to_orig = Win32::resolve([to])
  if from_orig == to_orig {
    return ""
  }
  let from = to_lower_js(from_orig)
  let to = to_lower_js(to_orig)
  if from == to {
    return ""
  }
  if from_orig.length() != from.length() || to_orig.length() != to.length() {
    let from_split = js_split_char(from_orig, char_backward_slash)
    let to_split = js_split_char(to_orig, char_backward_slash)
    if from_split[from_split.length() - 1] == "" {
      ignore(from_split.pop())
    }
    if to_split[to_split.length() - 1] == "" {
      ignore(to_split.pop())
    }
    let from_len = from_split.length()
    let to_len = to_split.length()
    let length = from_len.min(to_len)
    let mut i = 0
    while i < length {
      if to_lower_js(from_split[i]) != to_lower_js(to_split[i]) {
        break
      }
      i += 1
    }
    if i == 0 {
      return to_orig
    } else if i == length {
      if to_len > length {
        return to_split[i:].join("\\")
      }
      if from_len > length {
        return "\{"..\\".repeat(from_len - 1 - i)}.."
      }
      return ""
    }
    return "..\\".repeat(from_len - i) + to_split[i:].join("\\")
  }

  // Trim any leading backslashes
  let mut from_start = 0
  while from_start < from.length() &&
        char_code_at(from, from_start) == char_backward_slash {
    from_start += 1
  }
  // Trim trailing backslashes (applicable to UNC paths only)
  let mut from_end = from.length()
  while from_end - 1 > from_start &&
        char_code_at(from, from_end - 1) == char_backward_slash {
    from_end -= 1
  }
  let from_len = from_end - from_start

  // Trim any leading backslashes
  let mut to_start = 0
  while to_start < to.length() &&
        char_code_at(to, to_start) == char_backward_slash {
    to_start += 1
  }
  // Trim trailing backslashes (applicable to UNC paths only)
  let mut to_end = to.length()
  while to_end - 1 > to_start &&
        char_code_at(to, to_end - 1) == char_backward_slash {
    to_end -= 1
  }
  let to_len = to_end - to_start

  // Compare paths to find the longest common path from root
  let length = from_len.min(to_len)
  let mut last_common_sep = -1
  let mut i = 0
  while i < length {
    let from_code = char_code_at(from, from_start + i)
    if from_code != char_code_at(to, to_start + i) {
      break
    } else if from_code == char_backward_slash {
      last_common_sep = i
    }
    i += 1
  }

  // We found a mismatch before the first common path separator was seen, so
  // return the original `to`.
  if i != length {
    if last_common_sep == -1 {
      return to_orig
    }
  } else {
    if to_len > length {
      if char_code_at(to, to_start + i) == char_backward_slash {
        // We get here if `from` is the exact base path for `to`.
        // For example: from='C:\\foo\\bar'; to='C:\\foo\\bar\\baz'
        return js_slice(to_orig, to_start + i + 1)
      }
      if i == 2 {
        // We get here if `from` is the device root.
        // For example: from='C:\\'; to='C:\\foo'
        return js_slice(to_orig, to_start + i)
      }
    }
    if from_len > length {
      if char_code_at(from, from_start + i) == char_backward_slash {
        // We get here if `to` is the exact base path for `from`.
        // For example: from='C:\\foo\\bar'; to='C:\\foo'
        last_common_sep = i
      } else if i == 2 {
        // We get here if `to` is the device root.
        // For example: from='C:\\foo\\bar'; to='C:\\'
        last_common_sep = 3
      }
    }
    if last_common_sep == -1 {
      last_common_sep = 0
    }
  }
  let mut out = ""
  // Generate the relative path based on the path difference between `to` and
  // `from`
  let mut i2 = from_start + last_common_sep + 1
  while i2 <= from_end {
    if i2 == from_end || char_code_at(from, i2) == char_backward_slash {
      out += if out is "" { ".." } else { "\\.." }
    }
    i2 += 1
  }
  let mut to_start = to_start + last_common_sep

  // Lastly, append the rest of the destination (`to`) path that comes after
  // the common path parts
  if out.length() > 0 {
    return out + js_slice(to_orig, to_start, end=to_end)
  }
  if char_code_at(to_orig, to_start) == char_backward_slash {
    to_start += 1
  }
  js_slice(to_orig, to_start, end=to_end)
}

///|
/// `path.ts:733 win32.dirname`.
fn Win32::dirname_impl(path : String) -> String {
  let len = path.length()
  if len == 0 {
    return "."
  }
  let mut root_end = -1
  let mut offset = 0
  let code = char_code_at(path, 0)
  if len == 1 {
    // `path` contains just a path separator, exit early to avoid
    // unnecessary work or a dot.
    return if is_path_separator(code) { path } else { "." }
  }

  // Try to match a root
  if is_path_separator(code) {
    // Possible UNC root

    root_end = 1
    offset = 1
    if is_path_separator(char_code_at(path, 1)) {
      // Matched double path separator at beginning
      let mut j = 2
      let mut last = j
      // Match 1 or more non-path separators
      while j < len && !is_path_separator(char_code_at(path, j)) {
        j += 1
      }
      if j < len && j != last {
        // Matched!
        last = j
        // Match 1 or more path separators
        while j < len && is_path_separator(char_code_at(path, j)) {
          j += 1
        }
        if j < len && j != last {
          // Matched!
          last = j
          // Match 1 or more non-path separators
          while j < len && !is_path_separator(char_code_at(path, j)) {
            j += 1
          }
          if j == len {
            // We matched a UNC root only
            return path
          }
          if j != last {
            // We matched a UNC root with leftovers

            // Offset by 1 to include the separator after the UNC root to
            // treat it as a "normal root" on top of a (UNC) root
            root_end = j + 1
            offset = root_end
          }
        }
      }
    }
    // Possible device root
  } else if is_windows_device_root(code) && char_code_at(path, 1) == char_colon {
    root_end = if len > 2 && is_path_separator(char_code_at(path, 2)) {
      3
    } else {
      2
    }
    offset = root_end
  }
  let mut end = -1
  let mut matched_slash = true
  let mut i = len - 1
  while i >= offset {
    if is_path_separator(char_code_at(path, i)) {
      if !matched_slash {
        end = i
        break
      }
    } else {
      // We saw the first non-path separator
      matched_slash = false
    }
    i -= 1
  }
  if end == -1 {
    if root_end == -1 {
      return "."
    }
    end = root_end
  }
  js_slice(path, 0, end~)
}

///|
/// `path.ts:821 win32.basename` (drive-prefix skip + optional suffix
/// reverse-match).
fn Win32::basename_impl(path : String, suffix? : String) -> String {
  let mut start = 0
  let mut end = -1
  let mut matched_slash = true

  // Check for a drive letter prefix so as not to mistake the following
  // path separator as an extra separator at the end of the path that can be
  // disregarded
  if path.length() >= 2 &&
    is_windows_device_root(char_code_at(path, 0)) &&
    char_code_at(path, 1) == char_colon {
    start = 2
  }
  match suffix {
    Some(suffix) if suffix.length() > 0 && suffix.length() <= path.length() => {
      if suffix == path {
        return ""
      }
      let mut ext_idx = suffix.length() - 1
      let mut first_non_slash_end = -1
      let mut i = path.length() - 1
      while i >= start {
        let code = char_code_at(path, i)
        if is_path_separator(code) {
          // If we reached a path separator that was not part of a set of path
          // separators at the end of the string, stop now
          if !matched_slash {
            start = i + 1
            break
          }
        } else {
          if first_non_slash_end == -1 {
            // We saw the first non-path separator, remember this index in case
            // we need it if the extension ends up not matching
            matched_slash = false
            first_non_slash_end = i + 1
          }
          if ext_idx >= 0 {
            // Try to match the explicit extension
            if code == char_code_at(suffix, ext_idx) {
              ext_idx -= 1
              if ext_idx == -1 {
                // We matched the extension, so mark this as the end of our path
                // component
                end = i
              }
            } else {
              // Extension does not match, so our result is the entire path
              // component
              ext_idx = -1
              end = first_non_slash_end
            }
          }
        }
        i -= 1
      }
      if start == end {
        end = first_non_slash_end
      } else if end == -1 {
        end = path.length()
      }
      js_slice(path, start, end~)
    }
    _ => {
      let mut i = path.length() - 1
      while i >= start {
        if is_path_separator(char_code_at(path, i)) {
          // If we reached a path separator that was not part of a set of path
          // separators at the end of the string, stop now
          if !matched_slash {
            start = i + 1
            break
          }
        } else if end == -1 {
          // We saw the first non-path separator, mark this as the end of our
          // path component
          matched_slash = false
          end = i + 1
        }
        i -= 1
      }
      if end == -1 {
        return ""
      }
      js_slice(path, start, end~)
    }
  }
}

///|
/// `path.ts:909 win32.extname`.
fn Win32::extname_impl(path : String) -> String {
  let mut start = 0
  let mut start_dot = -1
  let mut start_part = 0
  let mut end = -1
  let mut matched_slash = true
  // Track the state of characters (if any) we see before our first dot and
  // after any path separator we find
  let mut pre_dot_state = 0

  // Check for a drive letter prefix so as not to mistake the following
  // path separator as an extra separator at the end of the path that can be
  // disregarded
  if path.length() >= 2 &&
    char_code_at(path, 1) == char_colon &&
    is_windows_device_root(char_code_at(path, 0)) {
    start = 2
    start_part = 2
  }
  let mut i = path.length() - 1
  while i >= start {
    let code = char_code_at(path, i)
    if is_path_separator(code) {
      // If we reached a path separator that was not part of a set of path
      // separators at the end of the string, stop now
      if !matched_slash {
        start_part = i + 1
        break
      }
      i -= 1
      continue
    }
    if end == -1 {
      // We saw the first non-path separator, mark this as the end of our
      // extension
      matched_slash = false
      end = i + 1
    }
    if code == char_dot {
      // If this is our first dot, mark it as the start of our extension
      if start_dot == -1 {
        start_dot = i
      } else if pre_dot_state != 1 {
        pre_dot_state = 1
      }
    } else if start_dot != -1 {
      // We saw a non-dot and non-path separator before our dot, so we should
      // have a good chance at having a non-empty extension
      pre_dot_state = -1
    }
    i -= 1
  }
  if start_dot == -1 ||
    end == -1 ||
    // We saw a non-dot character immediately before the dot
    pre_dot_state == 0 ||
    // The (right-most) trimmed path component is exactly '..'
    (pre_dot_state == 1 && start_dot == end - 1 && start_dot == start_part + 1) {
    return ""
  }
  js_slice(path, start_dot, end~)
}

///|
/// `path.ts:1129 win32.sep`.
fn Win32::sep_impl() -> String {
  "\\"
}

///|
/// `path.ts:1130 win32.delimiter`.
fn Win32::delimiter_impl() -> String {
  ";"
}

///|
/// `path.ts:1135 posixCwd` — on win32 converts backslashes to forward
/// slashes and truncates the drive indicator; elsewhere `process.cwd()`.
fn posix_cwd() -> String {
  if platform_is_win32() {
    let cwd = cwd().replace_all(old="\\", new="/")
    let index = cwd.find("/").unwrap_or(-1)
    js_slice(cwd, index)
  } else {
    // We're already on POSIX, no need for any transformations
    cwd()
  }
}

///|
/// `path.ts:1152 posix.resolve`.
fn Posix::resolve_impl(path_segments : Array[String]) -> String {
  let mut resolved_path = ""
  let mut resolved_absolute = false
  let mut i = path_segments.length() - 1
  while i >= 0 && !resolved_absolute {
    let path = path_segments[i]
    // Skip empty entries
    if path is "" {
      i -= 1
      continue
    }
    resolved_path = "\{path}/\{resolved_path}"
    resolved_absolute = char_code_at(path, 0) == char_forward_slash
    i -= 1
  }
  if !resolved_absolute {
    let cwd = posix_cwd()
    resolved_path = "\{cwd}/\{resolved_path}"
    resolved_absolute = char_code_at(cwd, 0) == char_forward_slash
  }

  // At this point the path should be resolved to a full absolute path, but
  // handle relative paths to be safe (might happen when process.cwd() fails)

  // Normalize the path
  resolved_path = normalize_string(
    resolved_path,
    !resolved_absolute,
    "/",
    is_posix_path_separator,
  )
  if resolved_absolute {
    return "/\{resolved_path}"
  }
  if resolved_path.length() > 0 {
    resolved_path
  } else {
    "."
  }
}

///|
/// `path.ts:1189 posix.normalize`.
fn Posix::normalize_impl(path : String) -> String {
  if path is "" {
    return "."
  }
  let is_abs = char_code_at(path, 0) == char_forward_slash
  let trailing_separator = char_code_at(path, path.length() - 1) ==
    char_forward_slash

  // Normalize the path
  let mut path = normalize_string(path, !is_abs, "/", is_posix_path_separator)
  if path is "" {
    if is_abs {
      return "/"
    }
    return if trailing_separator { "./" } else { "." }
  }
  if trailing_separator {
    path = "\{path}/"
  }
  if is_abs {
    "/\{path}"
  } else {
    path
  }
}

///|
/// `path.ts:1216 posix.isAbsolute`.
fn Posix::is_absolute_impl(path : String) -> Bool {
  path.length() > 0 && char_code_at(path, 0) == char_forward_slash
}

///|
/// `path.ts:1221 posix.join`.
fn Posix::join_impl(paths : Array[String]) -> String {
  if paths is [] {
    return "."
  }
  let path = [ for arg in paths if arg != "" => arg ]
  if path is [] {
    return "."
  }
  Posix::normalize(path.join("/"))
}

///|
/// `path.ts:1242 posix.relative`.
fn Posix::relative_impl(from : String, to : String) -> String {
  if from == to {
    return ""
  }

  // Trim leading forward slashes.
  let from = Posix::resolve([from])
  let to = Posix::resolve([to])
  if from == to {
    return ""
  }
  let from_start = 1
  let from_end = from.length()
  let from_len = from_end - from_start
  let to_start = 1
  let to_len = to.length() - to_start

  // Compare paths to find the longest common path from root
  let length = from_len.min(to_len)
  let mut last_common_sep = -1
  let mut i = 0
  while i < length {
    let from_code = char_code_at(from, from_start + i)
    if from_code != char_code_at(to, to_start + i) {
      break
    } else if from_code == char_forward_slash {
      last_common_sep = i
    }
    i += 1
  }
  if i == length {
    if to_len > length {
      if char_code_at(to, to_start + i) == char_forward_slash {
        // We get here if `from` is the exact base path for `to`.
        // For example: from='/foo/bar'; to='/foo/bar/baz'
        return js_slice(to, to_start + i + 1)
      }
      if i == 0 {
        // We get here if `from` is the root
        // For example: from='/'; to='/foo'
        return js_slice(to, to_start + i)
      }
    } else if from_len > length {
      if char_code_at(from, from_start + i) == char_forward_slash {
        // We get here if `to` is the exact base path for `from`.
        // For example: from='/foo/bar/baz'; to='/foo/bar'
        last_common_sep = i
      } else if i == 0 {
        // We get here if `to` is the root.
        // For example: from='/foo/bar'; to='/'
        last_common_sep = 0
      }
    }
  }
  let mut out = ""
  // Generate the relative path based on the path difference between `to`
  // and `from`.
  let mut i2 = from_start + last_common_sep + 1
  while i2 <= from_end {
    if i2 == from_end || char_code_at(from, i2) == char_forward_slash {
      out += if out is "" { ".." } else { "/.." }
    }
    i2 += 1
  }

  // Lastly, append the rest of the destination (`to`) path that comes after
  // the common path parts.
  out + js_slice(to, to_start + last_common_sep)
}

///|
/// `path.ts:1320 posix.dirname`.
fn Posix::dirname_impl(path : String) -> String {
  if path is "" {
    return "."
  }
  let has_root = char_code_at(path, 0) == char_forward_slash
  let mut end = -1
  let mut matched_slash = true
  let mut i = path.length() - 1
  while i >= 1 {
    if char_code_at(path, i) == char_forward_slash {
      if !matched_slash {
        end = i
        break
      }
    } else {
      // We saw the first non-path separator
      matched_slash = false
    }
    i -= 1
  }
  if end == -1 {
    return if has_root { "/" } else { "." }
  }
  if has_root && end == 1 {
    return "//"
  }
  js_slice(path, 0, end~)
}

///|
/// `path.ts:1349 posix.basename` (optional suffix reverse-match).
fn Posix::basename_impl(path : String, suffix? : String) -> String {
  let mut start = 0
  let mut end = -1
  let mut matched_slash = true
  match suffix {
    Some(suffix) if suffix.length() > 0 && suffix.length() <= path.length() => {
      if suffix == path {
        return ""
      }
      let mut ext_idx = suffix.length() - 1
      let mut first_non_slash_end = -1
      let mut i = path.length() - 1
      while i >= 0 {
        let code = char_code_at(path, i)
        if code == char_forward_slash {
          // If we reached a path separator that was not part of a set of path
          // separators at the end of the string, stop now
          if !matched_slash {
            start = i + 1
            break
          }
        } else {
          if first_non_slash_end == -1 {
            // We saw the first non-path separator, remember this index in case
            // we need it if the extension ends up not matching
            matched_slash = false
            first_non_slash_end = i + 1
          }
          if ext_idx >= 0 {
            // Try to match the explicit extension
            if code == char_code_at(suffix, ext_idx) {
              ext_idx -= 1
              if ext_idx == -1 {
                // We matched the extension, so mark this as the end of our path
                // component
                end = i
              }
            } else {
              // Extension does not match, so our result is the entire path
              // component
              ext_idx = -1
              end = first_non_slash_end
            }
          }
        }
        i -= 1
      }
      if start == end {
        end = first_non_slash_end
      } else if end == -1 {
        end = path.length()
      }
      js_slice(path, start, end~)
    }
    _ => {
      let mut i = path.length() - 1
      while i >= 0 {
        if char_code_at(path, i) == char_forward_slash {
          // If we reached a path separator that was not part of a set of path
          // separators at the end of the string, stop now
          if !matched_slash {
            start = i + 1
            break
          }
        } else if end == -1 {
          // We saw the first non-path separator, mark this as the end of our
          // path component
          matched_slash = false
          end = i + 1
        }
        i -= 1
      }
      if end == -1 {
        return ""
      }
      js_slice(path, start, end~)
    }
  }
}

///|
/// `path.ts:1429 posix.extname`.
fn Posix::extname_impl(path : String) -> String {
  let mut start_dot = -1
  let mut start_part = 0
  let mut end = -1
  let mut matched_slash = true
  // Track the state of characters (if any) we see before our first dot and
  // after any path separator we find
  let mut pre_dot_state = 0
  let mut i = path.length() - 1
  while i >= 0 {
    let code = char_code_at(path, i)
    if code == char_forward_slash {
      // If we reached a path separator that was not part of a set of path
      // separators at the end of the string, stop now
      if !matched_slash {
        start_part = i + 1
        break
      }
      i -= 1
      continue
    }
    if end == -1 {
      // We saw the first non-path separator, mark this as the end of our
      // extension
      matched_slash = false
      end = i + 1
    }
    if code == char_dot {
      // If this is our first dot, mark it as the start of our extension
      if start_dot == -1 {
        start_dot = i
      } else if pre_dot_state != 1 {
        pre_dot_state = 1
      }
    } else if start_dot != -1 {
      // We saw a non-dot and non-path separator before our dot, so we should
      // have a good chance at having a non-empty extension
      pre_dot_state = -1
    }
    i -= 1
  }
  if start_dot == -1 ||
    end == -1 ||
    // We saw a non-dot character immediately before the dot
    pre_dot_state == 0 ||
    // The (right-most) trimmed path component is exactly '..'
    (pre_dot_state == 1 && start_dot == end - 1 && start_dot == start_part + 1) {
    return ""
  }
  js_slice(path, start_dot, end~)
}

///|
/// `path.ts:1568 posix.sep`.
fn Posix::sep_impl() -> String {
  "/"
}

///|
/// `path.ts:1569 posix.delimiter`.
fn Posix::delimiter_impl() -> String {
  ":"
}

///|
/// Platform-selected `normalize` (path.ts:1577); picked per call via the
/// D1/D8 seam instead of at module load.
fn normalize(path : String) -> String {
  if platform_is_win32() {
    Win32::normalize(path)
  } else {
    Posix::normalize(path)
  }
}

///|
/// Platform-selected `resolve` (path.ts:1580).
fn resolve(path_segments : Array[String]) -> String {
  if platform_is_win32() {
    Win32::resolve(path_segments)
  } else {
    Posix::resolve(path_segments)
  }
}

///|
/// Platform-selected `relative` (path.ts:1581).
fn relative(from : String, to : String) -> String {
  if platform_is_win32() {
    Win32::relative(from, to)
  } else {
    Posix::relative(from, to)
  }
}

///|
/// Platform-selected `dirname` (path.ts:1582).
pub fn dirname(path : String) -> String {
  if platform_is_win32() {
    Win32::dirname(path)
  } else {
    Posix::dirname(path)
  }
}

///|
/// Platform-selected `sep` (path.ts:1588).
fn sep() -> String {
  if platform_is_win32() {
    Win32::sep()
  } else {
    Posix::sep()
  }
}
