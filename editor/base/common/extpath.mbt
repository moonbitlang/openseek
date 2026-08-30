///| Port of `vscode/src/vs/base/common/extpath.ts` (checked-in submodule) — only the members `resources.ts` consumes; the rest are
/// explicit DEFERRED rows in the plan ledger. `isPathSeparator`
/// (extpath.ts:12) is shared with path.mbt's identical private helper.
/// Regex character classes become char loops (D3).

///|
/// `[\\/]` → `sep` global replace (the regex bodies of extpath.ts:22 and
/// extpath.ts:71).
fn replace_path_separators(os_path : String, sep : String) -> String {
  let sb = StringBuilder()
  for unit in os_path.code_units() {
    let code = unit.to_int()
    if is_path_separator(code) {
      sb.write_string(sep)
    } else {
      sb.write_char(Int::unsafe_to_char(code))
    }
  }
  sb.to_string()
}

///|
/// `toSlashes` (extpath.ts:21): takes a Windows OS path and changes backward
/// slashes to forward slashes. This should only be done for OS paths from
/// Windows (or user provided paths potentially from Windows) — using it on a
/// Linux or MacOS path might change it.
fn to_slashes(os_path : String) -> String {
  replace_path_separators(os_path, Posix::sep())
}

///|
/// `toPosixPath` (extpath.ts:32): takes a Windows OS path (backward or
/// forward slashes) and turns it into a posix path — forward slashes, made
/// absolute when it starts with a drive letter (`^[a-zA-Z]:(\/|$)`).
fn to_posix_path(os_path : String) -> String {
  let mut os_path = os_path
  if !os_path.contains("/") {
    os_path = to_slashes(os_path)
  }
  if os_path.length() >= 2 &&
    is_windows_drive_letter(char_code_at(os_path, 0)) &&
    char_code_at(os_path, 1) == char_colon &&
    (os_path.length() == 2 || char_code_at(os_path, 2) == char_forward_slash) {
    // starts with a drive letter
    os_path = "/\{os_path}"
  }
  os_path
}

///|
/// `getRoot` (extpath.ts:47): computes the _root_ of a path, like
/// `getRoot('c:\files') === 'c:\'`, `getRoot('files:///files/path') ===
/// 'files:///'`, or `getRoot('\\server\shares\path') === '\\server\shares\'`.
fn get_root(path : String, sep? : String) -> String {
  let sep = match sep {
    Some(value) => value
    None => Posix::sep()
  }
  if path == "" {
    return ""
  }
  let len = path.length()
  let first_letter = char_code_at(path, 0)
  if is_path_separator(first_letter) {
    if is_path_separator(char_code_at(path, 1)) {
      // UNC candidate \\localhost\shares\ddd
      //               ^^^^^^^^^^^^^^^^^^^
      if !is_path_separator(char_code_at(path, 2)) {
        let start = 3
        let pos = for pos in start..<len {
          if is_path_separator(char_code_at(path, pos)) {
            break pos
          }
        } nobreak {
          len
        }
        if start != pos && !is_path_separator(char_code_at(path, pos + 1)) {
          for pos in (pos + 1)..<len {
            if is_path_separator(char_code_at(path, pos)) {
              // consume this separator
              return replace_path_separators(
                js_slice(path, 0, end=pos + 1),
                sep,
              )
            }
          }
        }
      }
    }

    // /user/far
    // ^
    return sep
  } else if is_windows_drive_letter(first_letter) {
    // check for windows drive letter c:\ or c:
    if char_code_at(path, 1) == char_colon {
      if is_path_separator(char_code_at(path, 2)) {
        // C:\fff
        // ^^^
        return js_slice(path, 0, end=2) + sep
      } else {
        // C:
        // ^^
        return js_slice(path, 0, end=2)
      }
    }
  }

  // check for URI
  // scheme://authority/path
  // ^^^^^^^^^^^^^^^^^^^
  if path.find("://") is Some(scheme_end) {
    for pos in (scheme_end + 3)..<len {
      if is_path_separator(char_code_at(path, pos)) {
        return js_slice(path, 0, end=pos + 1) // consume this separator
      }
    }
  }
  ""
}

///|
/// `isEqualOrParent` (extpath.ts:227), the OS-path string variant consumed
/// by `ExtUri::is_equal_or_parent`. (Monaco's `resources.isEqualOrParent`
/// URI-level bound export lives on `ext_uri` here — one flat package cannot
/// hold both top-level names.)
fn is_equal_or_parent(
  base : String,
  parent_candidate : String,
  ignore_case : Bool,
  force_posix_semantics? : Bool = false,
) -> Bool {
  let separator = if force_posix_semantics { Posix::sep() } else { sep() }
  let mut base = base
  let mut parent_candidate = parent_candidate
  if base == parent_candidate {
    return true
  }
  if base == "" || parent_candidate == "" {
    return false
  }
  if base.contains("..") || parent_candidate.contains("..") {
    base = if force_posix_semantics {
      Posix::normalize(base)
    } else {
      normalize(base)
    }
    parent_candidate = if force_posix_semantics {
      Posix::normalize(parent_candidate)
    } else {
      normalize(parent_candidate)
    }
  }
  if parent_candidate.length() > base.length() {
    return false
  }
  if ignore_case {
    let begins_with = starts_with_ignore_case(base, parent_candidate)
    if !begins_with {
      return false
    }
    if parent_candidate.length() == base.length() {
      return true // same path, different casing
    }
    let mut sep_offset = parent_candidate.length()
    if js_slice(parent_candidate, parent_candidate.length() - 1) == separator {
      sep_offset -= 1 // adjust the expected sep offset in case our candidate already ends in separator character
    }
    return js_slice(base, sep_offset, end=sep_offset + 1) == separator
  }
  if js_slice(parent_candidate, parent_candidate.length() - 1) != separator {
    parent_candidate += separator
  }
  base.has_prefix(parent_candidate)
}

///|
/// `isWindowsDriveLetter` (extpath.ts:275).
fn is_windows_drive_letter(char0 : Int) -> Bool {
  (char0 >= 'A'.to_int() && char0 <= 'Z'.to_int()) ||
  (char0 >= 'a'.to_int() && char0 <= 'z'.to_int())
}
