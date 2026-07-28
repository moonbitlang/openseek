// Conformance port of `vs/base/test/common/path.test.ts` in the checked-in
// vscode source, suite "Paths (Node Implementation)".
//
// The JS tables call `path.posix.*` / `path.win32.*` explicitly and are
// transcribed against `Posix::` / `Win32::` directly; assertions on the
// platform-selected exports run against both namespaces (or the D8 seam)
// so non-Windows CI exercises the win32 branches too.

///|
/// Shared join table (posix expectations); the win32 run accepts the
/// backslash form of the same result, mirroring the JS test's `actualAlt`.
fn join_cases() -> Array[(Array[String], String)] {
  [
    ([".", "x/b", "..", "/b/c.js"], "x/b/c.js"),
    ([], "."),
    (["/.", "x/b", "..", "/b/c.js"], "/x/b/c.js"),
    (["/foo", "../../../bar"], "/bar"),
    (["foo", "../../../bar"], "../../bar"),
    (["foo/", "../../../bar"], "../../bar"),
    (["foo/x", "../../../bar"], "../bar"),
    (["foo/x", "./bar"], "foo/x/bar"),
    (["foo/x/", "./bar"], "foo/x/bar"),
    (["foo/x/", ".", "bar"], "foo/x/bar"),
    (["./"], "./"),
    ([".", "./"], "./"),
    ([".", ".", "."], "."),
    ([".", "./", "."], "."),
    ([".", "/./", "."], "."),
    ([".", "/////./", "."], "."),
    (["."], "."),
    (["", "."], "."),
    (["", "foo"], "foo"),
    (["foo", "/bar"], "foo/bar"),
    (["", "/foo"], "/foo"),
    (["", "", "/foo"], "/foo"),
    (["", "", "foo"], "foo"),
    (["foo", ""], "foo"),
    (["foo/", ""], "foo/"),
    (["foo", "", "/bar"], "foo/bar"),
    (["./", "..", "/foo"], "../foo"),
    (["./", "..", "..", "/foo"], "../../foo"),
    ([".", "..", "..", "/foo"], "../../foo"),
    (["", "..", "..", "/foo"], "../../foo"),
    (["/"], "/"),
    (["/", "."], "/"),
    (["/", ".."], "/"),
    (["/", "..", ".."], "/"),
    ([""], "."),
    (["", ""], "."),
    ([" /foo"], " /foo"),
    ([" ", "foo"], " /foo"),
    ([" ", "."], " "),
    ([" ", "/"], " /"),
    ([" ", ""], " "),
    (["/", "foo"], "/foo"),
    (["/", "/foo"], "/foo"),
    (["/", "//foo"], "/foo"),
    (["/", "", "/foo"], "/foo"),
    (["", "/", "foo"], "/foo"),
    (["", "/", "/foo"], "/foo"),
  ]
}

///|
/// Windows-specific join expectations (appended to the shared table for the
/// win32-only run in the JS test).
fn join_cases_win32_only() -> Array[(Array[String], String)] {
  [
    // UNC path expected
    (["//foo/bar"], "\\\\foo\\bar\\"),
    (["\\/foo/bar"], "\\\\foo\\bar\\"),
    (["\\\\foo/bar"], "\\\\foo\\bar\\"),
    // UNC path expected - server and share separate
    (["//foo", "bar"], "\\\\foo\\bar\\"),
    (["//foo/", "bar"], "\\\\foo\\bar\\"),
    (["//foo", "/bar"], "\\\\foo\\bar\\"),
    // UNC path expected - questionable
    (["//foo", "", "bar"], "\\\\foo\\bar\\"),
    (["//foo/", "", "bar"], "\\\\foo\\bar\\"),
    (["//foo/", "", "/bar"], "\\\\foo\\bar\\"),
    // UNC path expected - even more questionable
    (["", "//foo", "bar"], "\\\\foo\\bar\\"),
    (["", "//foo/", "bar"], "\\\\foo\\bar\\"),
    (["", "//foo/", "/bar"], "\\\\foo\\bar\\"),
    // No UNC path expected (no double slash in first component)
    (["\\", "foo/bar"], "\\foo\\bar"),
    (["\\", "/foo/bar"], "\\foo\\bar"),
    (["", "/", "/foo/bar"], "\\foo\\bar"),
    // No UNC path expected (no non-slashes in first component - questionable)
    (["//", "foo/bar"], "\\foo\\bar"),
    (["//", "/foo/bar"], "\\foo\\bar"),
    (["\\\\", "/", "/foo/bar"], "\\foo\\bar"),
    (["//"], "\\"),
    // No UNC path expected (share name missing - questionable).
    (["//foo"], "\\foo"),
    (["//foo/"], "\\foo\\"),
    (["//foo", "/"], "\\foo\\"),
    (["//foo", "", "/"], "\\foo\\"),
    // No UNC path expected (too many leading slashes - questionable)
    (["///foo/bar"], "\\foo\\bar"),
    (["////foo", "bar"], "\\foo\\bar"),
    (["\\\\\\/foo/bar"], "\\foo\\bar"),
    // Drive-relative vs drive-absolute paths. This merely describes the
    // status quo, rather than being obviously right
    (["c:"], "c:."),
    (["c:."], "c:."),
    (["c:", ""], "c:."),
    (["", "c:"], "c:."),
    (["c:.", "/"], "c:.\\"),
    (["c:.", "file"], "c:file"),
    (["c:", "/"], "c:\\"),
    (["c:", "file"], "c:\\file"),
  ]
}

///|
test "join" {
  let failures : Array[String] = []
  for case in join_cases() {
    let (args, expected) = case
    let actual = Posix::join(args)
    if actual != expected {
      failures.push(
        "posix.join(\{Repr(args)}) expect=\{expected} actual=\{actual}",
      )
    }
    // For non-Windows specific tests with the Windows join(), we need to try
    // replacing the slashes since the non-Windows specific tests' `expected`
    // use forward slashes
    let win_actual = Win32::join(args)
    let win_actual_alt = win_actual.replace_all(old="\\", new="/")
    if win_actual != expected && win_actual_alt != expected {
      failures.push(
        "win32.join(\{Repr(args)}) expect=\{expected} actual=\{win_actual}",
      )
    }
  }
  for case in join_cases_win32_only() {
    let (args, expected) = case
    let actual = Win32::join(args)
    let actual_alt = actual.replace_all(old="\\", new="/")
    if actual != expected && actual_alt != expected {
      failures.push(
        "win32.join(\{Repr(args)}) expect=\{expected} actual=\{actual}",
      )
    }
  }
  assert_eq(failures.length(), 0, msg=failures.join("\n"))
}

///|
test "dirname" {
  assert_eq(Posix::dirname("/a/b/"), "/a")
  assert_eq(Posix::dirname("/a/b"), "/a")
  assert_eq(Posix::dirname("/a"), "/")
  assert_eq(Posix::dirname(""), ".")
  assert_eq(Posix::dirname("/"), "/")
  assert_eq(Posix::dirname("////"), "/")
  assert_eq(Posix::dirname("//a"), "//")
  assert_eq(Posix::dirname("foo"), ".")
  assert_eq(Win32::dirname("c:\\"), "c:\\")
  assert_eq(Win32::dirname("c:\\foo"), "c:\\")
  assert_eq(Win32::dirname("c:\\foo\\"), "c:\\")
  assert_eq(Win32::dirname("c:\\foo\\bar"), "c:\\foo")
  assert_eq(Win32::dirname("c:\\foo\\bar\\"), "c:\\foo")
  assert_eq(Win32::dirname("c:\\foo\\bar\\baz"), "c:\\foo\\bar")
  assert_eq(Win32::dirname("\\"), "\\")
  assert_eq(Win32::dirname("\\foo"), "\\")
  assert_eq(Win32::dirname("\\foo\\"), "\\")
  assert_eq(Win32::dirname("\\foo\\bar"), "\\foo")
  assert_eq(Win32::dirname("\\foo\\bar\\"), "\\foo")
  assert_eq(Win32::dirname("\\foo\\bar\\baz"), "\\foo\\bar")
  assert_eq(Win32::dirname("c:"), "c:")
  assert_eq(Win32::dirname("c:foo"), "c:")
  assert_eq(Win32::dirname("c:foo\\"), "c:")
  assert_eq(Win32::dirname("c:foo\\bar"), "c:foo")
  assert_eq(Win32::dirname("c:foo\\bar\\"), "c:foo")
  assert_eq(Win32::dirname("c:foo\\bar\\baz"), "c:foo\\bar")
  assert_eq(Win32::dirname("file:stream"), ".")
  assert_eq(Win32::dirname("dir\\file:stream"), "dir")
  assert_eq(Win32::dirname("\\\\unc\\share"), "\\\\unc\\share")
  assert_eq(Win32::dirname("\\\\unc\\share\\foo"), "\\\\unc\\share\\")
  assert_eq(Win32::dirname("\\\\unc\\share\\foo\\"), "\\\\unc\\share\\")
  assert_eq(Win32::dirname("\\\\unc\\share\\foo\\bar"), "\\\\unc\\share\\foo")
  assert_eq(Win32::dirname("\\\\unc\\share\\foo\\bar\\"), "\\\\unc\\share\\foo")
  assert_eq(
    Win32::dirname("\\\\unc\\share\\foo\\bar\\baz"),
    "\\\\unc\\share\\foo\\bar",
  )
  assert_eq(Win32::dirname("/a/b/"), "/a")
  assert_eq(Win32::dirname("/a/b"), "/a")
  assert_eq(Win32::dirname("/a"), "/")
  assert_eq(Win32::dirname(""), ".")
  assert_eq(Win32::dirname("/"), "/")
  assert_eq(Win32::dirname("////"), "/")
  assert_eq(Win32::dirname("foo"), ".")

  // Tests from VSCode
  assert_eq(Posix::dirname("foo/bar"), "foo")
  assert_eq(Win32::dirname("foo\\bar"), "foo")
  assert_eq(Posix::dirname("/foo/bar"), "/foo")
  assert_eq(Win32::dirname("\\foo\\bar"), "\\foo")
  assert_eq(Posix::dirname("/foo"), "/")
  assert_eq(Win32::dirname("\\foo"), "\\")
  assert_eq(Posix::dirname("/"), "/")
  assert_eq(Win32::dirname("\\"), "\\")
  assert_eq(Posix::dirname("foo"), ".")
  assert_eq(Posix::dirname("f"), ".")
  assert_eq(Posix::dirname("f/"), ".")
  assert_eq(Posix::dirname("/folder/"), "/")
  assert_eq(Win32::dirname("c:\\some\\file.txt"), "c:\\some")
  assert_eq(Win32::dirname("c:\\some"), "c:\\")
  assert_eq(Win32::dirname("c:\\"), "c:\\")
  assert_eq(Win32::dirname("c:"), "c:")
  assert_eq(
    Win32::dirname("\\\\server\\share\\some\\path"),
    "\\\\server\\share\\some",
  )
  assert_eq(Win32::dirname("\\\\server\\share\\some"), "\\\\server\\share\\")
  assert_eq(Win32::dirname("\\\\server\\share\\"), "\\\\server\\share\\")
}

///|
/// The extname table runs against posix as-is, against win32 with slashes
/// flipped to backslashes, and against win32 again with a `C:` prefix.
fn extname_cases() -> Array[(String, String)] {
  [
    ("path.test.js", ".js"), // __filename
    ("", ""),
    ("/path/to/file", ""),
    ("/path/to/file.ext", ".ext"),
    ("/path.to/file.ext", ".ext"),
    ("/path.to/file", ""),
    ("/path.to/.file", ""),
    ("/path.to/.file.ext", ".ext"),
    ("/path/to/f.ext", ".ext"),
    ("/path/to/..ext", ".ext"),
    ("/path/to/..", ""),
    ("file", ""),
    ("file.ext", ".ext"),
    (".file", ""),
    (".file.ext", ".ext"),
    ("/file", ""),
    ("/file.ext", ".ext"),
    ("/.file", ""),
    ("/.file.ext", ".ext"),
    (".path/file.ext", ".ext"),
    ("file.ext.ext", ".ext"),
    ("file.", "."),
    (".", ""),
    ("./", ""),
    (".file.ext", ".ext"),
    (".file", ""),
    (".file.", "."),
    (".file..", "."),
    ("..", ""),
    ("../", ""),
    ("..file.ext", ".ext"),
    ("..file", ".file"),
    ("..file.", "."),
    ("..file..", "."),
    ("...", "."),
    ("...ext", ".ext"),
    ("....", "."),
    ("file.ext/", ".ext"),
    ("file.ext//", ".ext"),
    ("file/", ""),
    ("file//", ""),
    ("file./", "."),
    ("file.//", "."),
  ]
}

///|
test "extname" {
  let failures : Array[String] = []
  for case in extname_cases() {
    let (input, expected) = case
    let posix_actual = Posix::extname(input)
    if posix_actual != expected {
      failures.push(
        "posix.extname(\{input}) expect=\{expected} actual=\{posix_actual}",
      )
    }
    let win_input = input.replace_all(old="/", new="\\")
    let win_actual = Win32::extname(win_input)
    if win_actual != expected {
      failures.push(
        "win32.extname(\{win_input}) expect=\{expected} actual=\{win_actual}",
      )
    }
    let drive_input = "C:" + win_input
    let drive_actual = Win32::extname(drive_input)
    if drive_actual != expected {
      failures.push(
        "win32.extname(\{drive_input}) expect=\{expected} actual=\{drive_actual}",
      )
    }
  }
  assert_eq(failures.length(), 0, msg=failures.join("\n"))

  // On Windows, backslash is a path separator.
  assert_eq(Win32::extname(".\\"), "")
  assert_eq(Win32::extname("..\\"), "")
  assert_eq(Win32::extname("file.ext\\"), ".ext")
  assert_eq(Win32::extname("file.ext\\\\"), ".ext")
  assert_eq(Win32::extname("file\\"), "")
  assert_eq(Win32::extname("file\\\\"), "")
  assert_eq(Win32::extname("file.\\"), ".")
  assert_eq(Win32::extname("file.\\\\"), ".")

  // On *nix, backslash is a valid name component like any other character.
  assert_eq(Posix::extname(".\\"), "")
  assert_eq(Posix::extname("..\\"), ".\\")
  assert_eq(Posix::extname("file.ext\\"), ".ext\\")
  assert_eq(Posix::extname("file.ext\\\\"), ".ext\\\\")
  assert_eq(Posix::extname("file\\"), "")
  assert_eq(Posix::extname("file\\\\"), "")
  assert_eq(Posix::extname("file.\\"), ".\\")
  assert_eq(Posix::extname("file.\\\\"), ".\\\\")

  // Tests from VSCode — the JS test uses the platform-selected
  // `path.extname` (deferred: no consumer); both namespaces agree on these
  // separator-free inputs, so exercise both.
  let extnames : Array[(String) -> String] = [
    path => Posix::extname(path),
    path => Win32::extname(path),
  ]
  for extname in extnames {
    assert_eq(extname("far.boo"), ".boo")
    assert_eq(extname("far.b"), ".b")
    assert_eq(extname("far."), ".")
    assert_eq(extname("far.boo/boo.far"), ".far")
    assert_eq(extname("far.boo/boo"), "")
  }
}

///|
test "resolve" {
  let failures : Array[String] = []
  let win32_cases : Array[(Array[String], String)] = [
    (["c:/blah\\blah", "d:/games", "c:../a"], "c:\\blah\\a"),
    (["c:/ignore", "d:\\a/b\\c/d", "\\e.exe"], "d:\\e.exe"),
    (["c:/ignore", "c:/some/file"], "c:\\some\\file"),
    (["d:/ignore", "d:some/dir//"], "d:\\ignore\\some\\dir"),
    (["//server/share", "..", "relative\\"], "\\\\server\\share\\relative"),
    (["c:/", "//"], "c:\\"),
    (["c:/", "//dir"], "c:\\dir"),
    (["c:/", "//server/share"], "\\\\server\\share\\"),
    (["c:/", "//server//share"], "\\\\server\\share\\"),
    (["c:/", "///some//dir"], "c:\\some\\dir"),
    (
      ["C:\\foo\\tmp.3\\", "..\\tmp.3\\cycles\\root.js"],
      "C:\\foo\\tmp.3\\cycles\\root.js",
    ),
  ]
  for case in win32_cases {
    let (args, expected) = case
    let actual = Win32::resolve(args)
    // On non-Windows hosts the JS test accepts the slash-normalized form.
    let actual_alt = actual.replace_all(old="\\", new="/")
    if actual != expected && actual_alt != expected {
      failures.push(
        "win32.resolve(\{Repr(args)}) expect=\{expected} actual=\{actual}",
      )
    }
  }
  let posix_cases : Array[(Array[String], String)] = [
    (["/var/lib", "../", "file/"], "/var/file"),
    (["/var/lib", "/../", "file/"], "/file"),
    (["/some/dir", ".", "/absolute/"], "/absolute"),
    (["/foo/tmp.3/", "../tmp.3/cycles/root.js"], "/foo/tmp.3/cycles/root.js"),
  ]
  for case in posix_cases {
    let (args, expected) = case
    let actual = Posix::resolve(args)
    if actual != expected {
      failures.push(
        "posix.resolve(\{Repr(args)}) expect=\{expected} actual=\{actual}",
      )
    }
  }
  assert_eq(failures.length(), 0, msg=failures.join("\n"))

  // Platform-selected resolve against the real process cwd (the JS test's
  // third table).
  assert_eq(resolve(["."]), cwd())
  assert_eq(resolve(["a/b/c", "../../.."]), cwd())
}

///|
test "basename" {
  // The JS test's platform-selected `path.basename` asserts hold on both
  // namespaces for these inputs; exercise both (deferred platform-selected
  // export).
  let basenames : Array[(String, String?) -> String] = [
    (path, suffix) => Posix::basename(path, suffix?),
    (path, suffix) => Win32::basename(path, suffix?),
  ]
  for basename in basenames {
    assert_eq(basename("path.test.js", None), "path.test.js")
    assert_eq(basename("path.test.js", Some(".js")), "path.test")
    assert_eq(basename(".js", Some(".js")), "")
    assert_eq(basename("", None), "")
    assert_eq(basename("/dir/basename.ext", None), "basename.ext")
    assert_eq(basename("/basename.ext", None), "basename.ext")
    assert_eq(basename("basename.ext", None), "basename.ext")
    assert_eq(basename("basename.ext/", None), "basename.ext")
    assert_eq(basename("basename.ext//", None), "basename.ext")
    assert_eq(basename("aaa/bbb", Some("/bbb")), "bbb")
    assert_eq(basename("aaa/bbb", Some("a/bbb")), "bbb")
    assert_eq(basename("aaa/bbb", Some("bbb")), "bbb")
    assert_eq(basename("aaa/bbb//", Some("bbb")), "bbb")
    assert_eq(basename("aaa/bbb", Some("bb")), "b")
    assert_eq(basename("aaa/bbb", Some("b")), "bb")
    assert_eq(basename("/aaa/bbb", Some("/bbb")), "bbb")
    assert_eq(basename("/aaa/bbb", Some("a/bbb")), "bbb")
    assert_eq(basename("/aaa/bbb", Some("bbb")), "bbb")
    assert_eq(basename("/aaa/bbb//", Some("bbb")), "bbb")
    assert_eq(basename("/aaa/bbb", Some("bb")), "b")
    assert_eq(basename("/aaa/bbb", Some("b")), "bb")
    assert_eq(basename("/aaa/bbb", None), "bbb")
    assert_eq(basename("/aaa/", None), "aaa")
    assert_eq(basename("/aaa/b", None), "b")
    assert_eq(basename("/a/b", None), "b")
    assert_eq(basename("//a", None), "a")
    assert_eq(basename("a", Some("a")), "")
  }

  // On Windows a backslash acts as a path separator.
  assert_eq(Win32::basename("\\dir\\basename.ext"), "basename.ext")
  assert_eq(Win32::basename("\\basename.ext"), "basename.ext")
  assert_eq(Win32::basename("basename.ext"), "basename.ext")
  assert_eq(Win32::basename("basename.ext\\"), "basename.ext")
  assert_eq(Win32::basename("basename.ext\\\\"), "basename.ext")
  assert_eq(Win32::basename("foo"), "foo")
  assert_eq(Win32::basename("aaa\\bbb", suffix="\\bbb"), "bbb")
  assert_eq(Win32::basename("aaa\\bbb", suffix="a\\bbb"), "bbb")
  assert_eq(Win32::basename("aaa\\bbb", suffix="bbb"), "bbb")
  assert_eq(Win32::basename("aaa\\bbb\\\\\\\\", suffix="bbb"), "bbb")
  assert_eq(Win32::basename("aaa\\bbb", suffix="bb"), "b")
  assert_eq(Win32::basename("aaa\\bbb", suffix="b"), "bb")
  assert_eq(Win32::basename("C:"), "")
  assert_eq(Win32::basename("C:."), ".")
  assert_eq(Win32::basename("C:\\"), "")
  assert_eq(Win32::basename("C:\\dir\\base.ext"), "base.ext")
  assert_eq(Win32::basename("C:\\basename.ext"), "basename.ext")
  assert_eq(Win32::basename("C:basename.ext"), "basename.ext")
  assert_eq(Win32::basename("C:basename.ext\\"), "basename.ext")
  assert_eq(Win32::basename("C:basename.ext\\\\"), "basename.ext")
  assert_eq(Win32::basename("C:foo"), "foo")
  assert_eq(Win32::basename("file:stream"), "file:stream")
  assert_eq(Win32::basename("a", suffix="a"), "")

  // On unix a backslash is just treated as any other character.
  assert_eq(Posix::basename("\\dir\\basename.ext"), "\\dir\\basename.ext")
  assert_eq(Posix::basename("\\basename.ext"), "\\basename.ext")
  assert_eq(Posix::basename("basename.ext"), "basename.ext")
  assert_eq(Posix::basename("basename.ext\\"), "basename.ext\\")
  assert_eq(Posix::basename("basename.ext\\\\"), "basename.ext\\\\")
  assert_eq(Posix::basename("foo"), "foo")

  // POSIX filenames may include control characters
  let control_char_filename = "Icon" + "\r"
  assert_eq(
    Posix::basename("/a/b/" + control_char_filename),
    control_char_filename,
  )

  // Tests from VSCode
  assert_eq(Posix::basename("foo/bar"), "bar")
  assert_eq(Win32::basename("foo/bar"), "bar")
  assert_eq(Posix::basename("foo\\bar"), "foo\\bar")
  assert_eq(Win32::basename("foo\\bar"), "bar")
  assert_eq(Posix::basename("/foo/bar"), "bar")
  assert_eq(Win32::basename("/foo/bar"), "bar")
  assert_eq(Posix::basename("\\foo\\bar"), "\\foo\\bar")
  assert_eq(Win32::basename("\\foo\\bar"), "bar")
  assert_eq(Posix::basename("./bar"), "bar")
  assert_eq(Win32::basename("./bar"), "bar")
  assert_eq(Posix::basename(".\\bar"), ".\\bar")
  assert_eq(Win32::basename(".\\bar"), "bar")
  assert_eq(Posix::basename("/bar"), "bar")
  assert_eq(Win32::basename("/bar"), "bar")
  assert_eq(Posix::basename("\\bar"), "\\bar")
  assert_eq(Win32::basename("\\bar"), "bar")
  assert_eq(Posix::basename("bar/"), "bar")
  assert_eq(Win32::basename("bar/"), "bar")
  assert_eq(Posix::basename("bar\\"), "bar\\")
  assert_eq(Win32::basename("bar\\"), "bar")
  assert_eq(Posix::basename("bar"), "bar")
  assert_eq(Win32::basename("bar"), "bar")
  assert_eq(Posix::basename("////////"), "")
  assert_eq(Win32::basename("////////"), "")
  assert_eq(Posix::basename("\\\\\\\\"), "\\\\\\\\")
  assert_eq(Win32::basename("\\\\\\\\"), "")
}

///|
test "relative" {
  let failures : Array[String] = []
  let win32_cases : Array[(String, String, String)] = [
    ("c:/blah\\blah", "d:/games", "d:\\games"),
    ("c:/aaaa/bbbb", "c:/aaaa", ".."),
    ("c:/aaaa/bbbb", "c:/cccc", "..\\..\\cccc"),
    ("c:/aaaa/bbbb", "c:/aaaa/bbbb", ""),
    ("c:/aaaa/bbbb", "c:/aaaa/cccc", "..\\cccc"),
    ("c:/aaaa/", "c:/aaaa/cccc", "cccc"),
    ("c:/", "c:\\aaaa\\bbbb", "aaaa\\bbbb"),
    ("c:/aaaa/bbbb", "d:\\", "d:\\"),
    ("c:/AaAa/bbbb", "c:/aaaa/bbbb", ""),
    ("c:/aaaaa/", "c:/aaaa/cccc", "..\\aaaa\\cccc"),
    ("C:\\foo\\bar\\baz\\quux", "C:\\", "..\\..\\..\\.."),
    ("C:\\foo\\test", "C:\\foo\\test\\bar\\package.json", "bar\\package.json"),
    ("C:\\foo\\bar\\baz-quux", "C:\\foo\\bar\\baz", "..\\baz"),
    ("C:\\foo\\bar\\baz", "C:\\foo\\bar\\baz-quux", "..\\baz-quux"),
    ("\\\\foo\\bar", "\\\\foo\\bar\\baz", "baz"),
    ("\\\\foo\\bar\\baz", "\\\\foo\\bar", ".."),
    ("\\\\foo\\bar\\baz-quux", "\\\\foo\\bar\\baz", "..\\baz"),
    ("\\\\foo\\bar\\baz", "\\\\foo\\bar\\baz-quux", "..\\baz-quux"),
    ("C:\\baz-quux", "C:\\baz", "..\\baz"),
    ("C:\\baz", "C:\\baz-quux", "..\\baz-quux"),
    ("\\\\foo\\baz-quux", "\\\\foo\\baz", "..\\baz"),
    ("\\\\foo\\baz", "\\\\foo\\baz-quux", "..\\baz-quux"),
    ("C:\\baz", "\\\\foo\\bar\\baz", "\\\\foo\\bar\\baz"),
    ("\\\\foo\\bar\\baz", "C:\\baz", "C:\\baz"),
  ]
  for case in win32_cases {
    let (from, to, expected) = case
    let actual = Win32::relative(from, to)
    if actual != expected {
      failures.push(
        "win32.relative(\{from},\{to}) expect=\{expected} actual=\{actual}",
      )
    }
  }
  let posix_cases : Array[(String, String, String)] = [
    ("/var/lib", "/var", ".."),
    ("/var/lib", "/bin", "../../bin"),
    ("/var/lib", "/var/lib", ""),
    ("/var/lib", "/var/apache", "../apache"),
    ("/var/", "/var/lib", "lib"),
    ("/", "/var/lib", "var/lib"),
    ("/foo/test", "/foo/test/bar/package.json", "bar/package.json"),
    ("/Users/a/web/b/test/mails", "/Users/a/web/b", "../.."),
    ("/foo/bar/baz-quux", "/foo/bar/baz", "../baz"),
    ("/foo/bar/baz", "/foo/bar/baz-quux", "../baz-quux"),
    ("/baz-quux", "/baz", "../baz"),
    ("/baz", "/baz-quux", "../baz-quux"),
  ]
  for case in posix_cases {
    let (from, to, expected) = case
    let actual = Posix::relative(from, to)
    if actual != expected {
      failures.push(
        "posix.relative(\{from},\{to}) expect=\{expected} actual=\{actual}",
      )
    }
  }
  assert_eq(failures.length(), 0, msg=failures.join("\n"))
}

///|
test "normalize" {
  assert_eq(Win32::normalize("./fixtures///b/../b/c.js"), "fixtures\\b\\c.js")
  assert_eq(Win32::normalize("/foo/../../../bar"), "\\bar")
  assert_eq(Win32::normalize("a//b//../b"), "a\\b")
  assert_eq(Win32::normalize("a//b//./c"), "a\\b\\c")
  assert_eq(Win32::normalize("a//b//."), "a\\b")
  assert_eq(
    Win32::normalize("//server/share/dir/file.ext"),
    "\\\\server\\share\\dir\\file.ext",
  )
  assert_eq(Win32::normalize("/a/b/c/../../../x/y/z"), "\\x\\y\\z")
  assert_eq(Win32::normalize("C:"), "C:.")
  assert_eq(Win32::normalize("C:..\\abc"), "C:..\\abc")
  assert_eq(Win32::normalize("C:..\\..\\abc\\..\\def"), "C:..\\..\\def")
  assert_eq(Win32::normalize("C:\\."), "C:\\")
  assert_eq(Win32::normalize("file:stream"), "file:stream")
  assert_eq(Win32::normalize("bar\\foo..\\..\\"), "bar\\")
  assert_eq(Win32::normalize("bar\\foo..\\.."), "bar")
  assert_eq(Win32::normalize("bar\\foo..\\..\\baz"), "bar\\baz")
  assert_eq(Win32::normalize("bar\\foo..\\"), "bar\\foo..\\")
  assert_eq(Win32::normalize("bar\\foo.."), "bar\\foo..")
  assert_eq(Win32::normalize("..\\foo..\\..\\..\\bar"), "..\\..\\bar")
  assert_eq(Win32::normalize("..\\...\\..\\.\\...\\..\\..\\bar"), "..\\..\\bar")
  assert_eq(
    Win32::normalize("../../../foo/../../../bar"),
    "..\\..\\..\\..\\..\\bar",
  )
  assert_eq(
    Win32::normalize("../../../foo/../../../bar/../../"),
    "..\\..\\..\\..\\..\\..\\",
  )
  assert_eq(
    Win32::normalize("../foobar/barfoo/foo/../../../bar/../../"),
    "..\\..\\",
  )
  assert_eq(
    Win32::normalize("../.../../foobar/../../../bar/../../baz"),
    "..\\..\\..\\..\\baz",
  )
  assert_eq(Win32::normalize("foo/bar\\baz"), "foo\\bar\\baz")
  assert_eq(Posix::normalize("./fixtures///b/../b/c.js"), "fixtures/b/c.js")
  assert_eq(Posix::normalize("/foo/../../../bar"), "/bar")
  assert_eq(Posix::normalize("a//b//../b"), "a/b")
  assert_eq(Posix::normalize("a//b//./c"), "a/b/c")
  assert_eq(Posix::normalize("a//b//."), "a/b")
  assert_eq(Posix::normalize("/a/b/c/../../../x/y/z"), "/x/y/z")
  assert_eq(Posix::normalize("///..//./foo/.//bar"), "/foo/bar")
  assert_eq(Posix::normalize("bar/foo../../"), "bar/")
  assert_eq(Posix::normalize("bar/foo../.."), "bar")
  assert_eq(Posix::normalize("bar/foo../../baz"), "bar/baz")
  assert_eq(Posix::normalize("bar/foo../"), "bar/foo../")
  assert_eq(Posix::normalize("bar/foo.."), "bar/foo..")
  assert_eq(Posix::normalize("../foo../../../bar"), "../../bar")
  assert_eq(Posix::normalize("../.../.././.../../../bar"), "../../bar")
  assert_eq(Posix::normalize("../../../foo/../../../bar"), "../../../../../bar")
  assert_eq(
    Posix::normalize("../../../foo/../../../bar/../../"),
    "../../../../../../",
  )
  assert_eq(
    Posix::normalize("../foobar/barfoo/foo/../../../bar/../../"),
    "../../",
  )
  assert_eq(
    Posix::normalize("../.../../foobar/../../../bar/../../baz"),
    "../../../../baz",
  )
  assert_eq(Posix::normalize("foo/bar\\baz"), "foo/bar\\baz")
}

///|
test "isAbsolute" {
  assert_eq(Win32::is_absolute("/"), true)
  assert_eq(Win32::is_absolute("//"), true)
  assert_eq(Win32::is_absolute("//server"), true)
  assert_eq(Win32::is_absolute("//server/file"), true)
  assert_eq(Win32::is_absolute("\\\\server\\file"), true)
  assert_eq(Win32::is_absolute("\\\\server"), true)
  assert_eq(Win32::is_absolute("\\\\"), true)
  assert_eq(Win32::is_absolute("c"), false)
  assert_eq(Win32::is_absolute("c:"), false)
  assert_eq(Win32::is_absolute("c:\\"), true)
  assert_eq(Win32::is_absolute("c:/"), true)
  assert_eq(Win32::is_absolute("c://"), true)
  assert_eq(Win32::is_absolute("C:/Users/"), true)
  assert_eq(Win32::is_absolute("C:\\Users\\"), true)
  assert_eq(Win32::is_absolute("C:cwd/another"), false)
  assert_eq(Win32::is_absolute("C:cwd\\another"), false)
  assert_eq(Win32::is_absolute("directory/directory"), false)
  assert_eq(Win32::is_absolute("directory\\directory"), false)
  assert_eq(Posix::is_absolute("/home/foo"), true)
  assert_eq(Posix::is_absolute("/home/foo/.."), true)
  assert_eq(Posix::is_absolute("bar/"), false)
  assert_eq(Posix::is_absolute("./baz"), false)

  // Tests from VSCode: absolute paths
  for
    absolute_path in [
      "C:/", "C:\\", "C:/foo", "C:\\foo", "z:/foo/bar.txt", "z:\\foo\\bar.txt", "\\\\localhost\\c$\\foo",
      "/", "/foo",
    ] {
    assert_true(Win32::is_absolute(absolute_path), msg=absolute_path)
  }
  for absolute_path in ["/", "/foo", "/foo/bar.txt"] {
    assert_true(Posix::is_absolute(absolute_path), msg=absolute_path)
  }

  // Relative paths
  for non_absolute_path in ["", "foo", "foo/bar", "./foo", "http://foo.com/bar"] {
    assert_false(Win32::is_absolute(non_absolute_path), msg=non_absolute_path)
  }
  for
    non_absolute_path in [
      "", "foo", "foo/bar", "./foo", "http://foo.com/bar", "z:/foo/bar.txt",
    ] {
    assert_false(Posix::is_absolute(non_absolute_path), msg=non_absolute_path)
  }
}

///|
test "path" {
  // path.sep tests
  assert_eq(Win32::sep(), "\\")
  assert_eq(Posix::sep(), "/")

  // path.delimiter tests
  assert_eq(Win32::delimiter(), ";")
  assert_eq(Posix::delimiter(), ":")

  // The platform-selected exports follow the D8 seam.
  set_is_windows_for_testing(value=true)
  assert_eq(sep(), "\\")
  assert_eq(normalize("foo/bar"), "foo\\bar")
  set_is_windows_for_testing(value=false)
  assert_eq(sep(), "/")
  assert_eq(normalize("foo//bar"), "foo/bar")
  set_is_windows_for_testing()
}
