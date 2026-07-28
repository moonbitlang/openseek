// Conformance port of `vs/base/test/common/resources.test.ts` in the checked-in
// vscode source, suite "Resources".
// `distinctParents` covers a DEFERRED member and is not transcribed.
//
// The `isWindows` branches run under the D8 seam (both ways where the JS
// test only ran the host's); URIs are created after setting the seam
// because `fs_path`/`to_string` cache (D5). `dirname`/`isEqualOrParent`
// URI-level calls go through `ext_uri` (bound exports omitted — see
// resources.mbt header).

///|
fn assert_equal_uri(
  actual : Uri,
  expected : Uri,
  msg? : String,
  ignore_case? : Bool = false,
) -> Unit raise {
  let util = if ignore_case { ext_uri_ignore_path_case } else { ext_uri }
  if !util.is_equal(Some(expected), Some(actual)) {
    assert_eq(actual.to_string(), expected.to_string(), msg?)
  }
}

///|
test "dirname" {
  set_is_windows_for_testing(value=true)
  assert_eq(
    ext_uri.dirname(Uri::file("c:\\some\\file\\test.txt")).to_string(),
    "file:///c%3A/some/file",
  )
  assert_eq(
    ext_uri.dirname(Uri::file("c:\\some\\file")).to_string(),
    "file:///c%3A/some",
  )
  assert_eq(
    ext_uri.dirname(Uri::file("c:\\some\\file\\")).to_string(),
    "file:///c%3A/some",
  )
  assert_eq(ext_uri.dirname(Uri::file("c:\\some")).to_string(), "file:///c%3A/")
  assert_eq(ext_uri.dirname(Uri::file("C:\\some")).to_string(), "file:///c%3A/")
  assert_eq(ext_uri.dirname(Uri::file("c:\\")).to_string(), "file:///c%3A/")
  ignore(
    ext_uri.dirname(
      Uri::from(scheme="file", authority="/users/someone/portal.h"),
    ),
  )
  set_is_windows_for_testing(value=false)
  assert_eq(
    ext_uri.dirname(Uri::file("/some/file/test.txt")).to_string(),
    "file:///some/file",
  )
  assert_eq(
    ext_uri.dirname(Uri::file("/some/file/")).to_string(),
    "file:///some",
  )
  assert_eq(
    ext_uri.dirname(Uri::file("/some/file")).to_string(),
    "file:///some",
  )
  // does not explode (https://github.com/microsoft/vscode/issues/41987)
  ignore(
    ext_uri.dirname(
      Uri::from(scheme="file", authority="/users/someone/portal.h"),
    ),
  )
  set_is_windows_for_testing()
  assert_eq(
    ext_uri.dirname(Uri::parse("foo://a/some/file/test.txt")).to_string(),
    "foo://a/some/file",
  )
  assert_eq(
    ext_uri.dirname(Uri::parse("foo://a/some/file/")).to_string(),
    "foo://a/some",
  )
  assert_eq(
    ext_uri.dirname(Uri::parse("foo://a/some/file")).to_string(),
    "foo://a/some",
  )
  assert_eq(ext_uri.dirname(Uri::parse("foo://a/some")).to_string(), "foo://a/")
  assert_eq(ext_uri.dirname(Uri::parse("foo://a/")).to_string(), "foo://a/")
  assert_eq(ext_uri.dirname(Uri::parse("foo://a")).to_string(), "foo://a")
  assert_eq(
    ext_uri.dirname(Uri::parse("foo://a/b/c?q")).to_string(),
    "foo://a/b?q",
  )
}

///|
test "basename" {
  set_is_windows_for_testing(value=true)
  assert_eq(basename(Uri::file("c:\\some\\file\\test.txt")), "test.txt")
  assert_eq(basename(Uri::file("c:\\some\\file")), "file")
  assert_eq(basename(Uri::file("c:\\some\\file\\")), "file")
  assert_eq(basename(Uri::file("C:\\some\\file\\")), "file")
  set_is_windows_for_testing(value=false)
  assert_eq(basename(Uri::file("/some/file/test.txt")), "test.txt")
  assert_eq(basename(Uri::file("/some/file/")), "file")
  assert_eq(basename(Uri::file("/some/file")), "file")
  assert_eq(basename(Uri::file("/some")), "some")
  set_is_windows_for_testing()
  assert_eq(basename(Uri::parse("foo://a/some/file/test.txt")), "test.txt")
  assert_eq(basename(Uri::parse("foo://a/some/file/")), "file")
  assert_eq(basename(Uri::parse("foo://a/some/file")), "file")
  assert_eq(basename(Uri::parse("foo://a/some")), "some")
  assert_eq(basename(Uri::parse("foo://a/")), "")
  assert_eq(basename(Uri::parse("foo://a")), "")
}

///|
test "joinPath" {
  set_is_windows_for_testing(value=true)
  assert_eq(
    join_path(Uri::file("c:\\foo\\bar"), ["/file.js"]).to_string(),
    "file:///c%3A/foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::file("c:\\foo\\bar\\"), ["file.js"]).to_string(),
    "file:///c%3A/foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::file("c:\\foo\\bar\\"), ["/file.js"]).to_string(),
    "file:///c%3A/foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::file("c:\\"), ["/file.js"]).to_string(),
    "file:///c%3A/file.js",
  )
  assert_eq(
    join_path(Uri::file("c:\\"), ["bar/file.js"]).to_string(),
    "file:///c%3A/bar/file.js",
  )
  assert_eq(
    join_path(Uri::file("c:\\foo"), ["./file.js"]).to_string(),
    "file:///c%3A/foo/file.js",
  )
  assert_eq(
    join_path(Uri::file("c:\\foo"), ["/./file.js"]).to_string(),
    "file:///c%3A/foo/file.js",
  )
  assert_eq(
    join_path(Uri::file("C:\\foo"), ["../file.js"]).to_string(),
    "file:///c%3A/file.js",
  )
  assert_eq(
    join_path(Uri::file("C:\\foo\\."), ["../file.js"]).to_string(),
    "file:///c%3A/file.js",
  )
  set_is_windows_for_testing(value=false)
  assert_eq(
    join_path(Uri::file("/foo/bar"), ["/file.js"]).to_string(),
    "file:///foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::file("/foo/bar"), ["file.js"]).to_string(),
    "file:///foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::file("/foo/bar/"), ["/file.js"]).to_string(),
    "file:///foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::file("/"), ["/file.js"]).to_string(),
    "file:///file.js",
  )
  assert_eq(
    join_path(Uri::file("/foo/bar"), ["./file.js"]).to_string(),
    "file:///foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::file("/foo/bar"), ["/./file.js"]).to_string(),
    "file:///foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::file("/foo/bar"), ["../file.js"]).to_string(),
    "file:///foo/file.js",
  )
  set_is_windows_for_testing()
  assert_eq(
    join_path(Uri::parse("foo://a/foo/bar"), []).to_string(),
    "foo://a/foo/bar",
  )
  assert_eq(
    join_path(Uri::parse("foo://a/foo/bar"), ["/file.js"]).to_string(),
    "foo://a/foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::parse("foo://a/foo/bar"), ["file.js"]).to_string(),
    "foo://a/foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::parse("foo://a/foo/bar/"), ["/file.js"]).to_string(),
    "foo://a/foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::parse("foo://a/"), ["/file.js"]).to_string(),
    "foo://a/file.js",
  )
  assert_eq(
    join_path(Uri::parse("foo://a/foo/bar/"), ["./file.js"]).to_string(),
    "foo://a/foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::parse("foo://a/foo/bar/"), ["/./file.js"]).to_string(),
    "foo://a/foo/bar/file.js",
  )
  assert_eq(
    join_path(Uri::parse("foo://a/foo/bar/"), ["../file.js"]).to_string(),
    "foo://a/foo/file.js",
  )
  assert_eq(
    join_path(
      Uri::from(
        scheme="myScheme",
        authority="authority",
        path="/path",
        query="query",
        fragment="fragment",
      ),
      ["/file.js"],
    ).to_string(),
    "myScheme://authority/path/file.js?query#fragment",
  )
}

///|
test "normalizePath" {
  set_is_windows_for_testing(value=true)
  assert_eq(
    normalize_path(Uri::file("c:\\foo\\.\\bar")).to_string(),
    "file:///c%3A/foo/bar",
  )
  assert_eq(
    normalize_path(Uri::file("c:\\foo\\.")).to_string(),
    "file:///c%3A/foo",
  )
  assert_eq(
    normalize_path(Uri::file("c:\\foo\\.\\")).to_string(),
    "file:///c%3A/foo/",
  )
  assert_eq(
    normalize_path(Uri::file("c:\\foo\\..")).to_string(),
    "file:///c%3A/",
  )
  assert_eq(
    normalize_path(Uri::file("c:\\foo\\..\\bar")).to_string(),
    "file:///c%3A/bar",
  )
  assert_eq(
    normalize_path(Uri::file("c:\\foo\\..\\..\\bar")).to_string(),
    "file:///c%3A/bar",
  )
  assert_eq(
    normalize_path(Uri::file("c:\\foo\\foo\\..\\..\\bar")).to_string(),
    "file:///c%3A/bar",
  )
  assert_eq(
    normalize_path(Uri::file("C:\\foo\\foo\\.\\..\\..\\bar")).to_string(),
    "file:///c%3A/bar",
  )
  assert_eq(
    normalize_path(Uri::file("C:\\foo\\foo\\.\\..\\some\\..\\bar")).to_string(),
    "file:///c%3A/foo/bar",
  )
  set_is_windows_for_testing(value=false)
  assert_eq(
    normalize_path(Uri::file("/foo/./bar")).to_string(),
    "file:///foo/bar",
  )
  assert_eq(normalize_path(Uri::file("/foo/.")).to_string(), "file:///foo")
  assert_eq(normalize_path(Uri::file("/foo/./")).to_string(), "file:///foo/")
  assert_eq(normalize_path(Uri::file("/foo/..")).to_string(), "file:///")
  assert_eq(normalize_path(Uri::file("/foo/../bar")).to_string(), "file:///bar")
  assert_eq(
    normalize_path(Uri::file("/foo/../../bar")).to_string(),
    "file:///bar",
  )
  assert_eq(
    normalize_path(Uri::file("/foo/foo/../../bar")).to_string(),
    "file:///bar",
  )
  assert_eq(
    normalize_path(Uri::file("/foo/foo/./../../bar")).to_string(),
    "file:///bar",
  )
  assert_eq(
    normalize_path(Uri::file("/foo/foo/./../some/../bar")).to_string(),
    "file:///foo/bar",
  )
  assert_eq(normalize_path(Uri::file("/f")).to_string(), "file:///f")
  set_is_windows_for_testing()
  assert_eq(
    normalize_path(Uri::parse("foo://a/foo/./bar")).to_string(),
    "foo://a/foo/bar",
  )
  assert_eq(
    normalize_path(Uri::parse("foo://a/foo/.")).to_string(),
    "foo://a/foo",
  )
  assert_eq(
    normalize_path(Uri::parse("foo://a/foo/./")).to_string(),
    "foo://a/foo/",
  )
  assert_eq(
    normalize_path(Uri::parse("foo://a/foo/..")).to_string(),
    "foo://a/",
  )
  assert_eq(
    normalize_path(Uri::parse("foo://a/foo/../bar")).to_string(),
    "foo://a/bar",
  )
  assert_eq(
    normalize_path(Uri::parse("foo://a/foo/../../bar")).to_string(),
    "foo://a/bar",
  )
  assert_eq(
    normalize_path(Uri::parse("foo://a/foo/foo/../../bar")).to_string(),
    "foo://a/bar",
  )
  assert_eq(
    normalize_path(Uri::parse("foo://a/foo/foo/./../../bar")).to_string(),
    "foo://a/bar",
  )
  assert_eq(
    normalize_path(Uri::parse("foo://a/foo/foo/./../some/../bar")).to_string(),
    "foo://a/foo/bar",
  )
  assert_eq(normalize_path(Uri::parse("foo://a")).to_string(), "foo://a")
  assert_eq(normalize_path(Uri::parse("foo://a/")).to_string(), "foo://a/")
  assert_eq(
    normalize_path(Uri::parse("foo://a/foo/./bar?q=1")).to_string(),
    Uri::parse("foo://a/foo/bar?q%3D1").to_string(),
  )
}

///|
test "isAbsolute" {
  set_is_windows_for_testing(value=true)
  assert_eq(is_absolute_path(Uri::file("c:\\foo\\")), true)
  assert_eq(is_absolute_path(Uri::file("C:\\foo\\")), true)
  assert_eq(is_absolute_path(Uri::file("bar")), true) // URI normalizes all file URIs to be absolute
  set_is_windows_for_testing(value=false)
  assert_eq(is_absolute_path(Uri::file("/foo/bar")), true)
  assert_eq(is_absolute_path(Uri::file("bar")), true) // URI normalizes all file URIs to be absolute
  set_is_windows_for_testing()
  assert_eq(is_absolute_path(Uri::parse("foo:foo")), false)
  assert_eq(is_absolute_path(Uri::parse("foo://a/foo/.")), true)
}

///|
fn assert_trailing_separator(u1 : Uri, expected : Bool) -> Unit raise {
  assert_eq(has_trailing_path_separator(u1), expected, msg=u1.to_string())
}

///|
fn assert_remove_trailing_separator(u1 : Uri, expected : Uri) -> Unit raise {
  assert_equal_uri(
    remove_trailing_path_separator(u1),
    expected,
    msg=u1.to_string(),
  )
}

///|
fn assert_add_trailing_separator(u1 : Uri, expected : Uri) -> Unit raise {
  assert_equal_uri(
    add_trailing_path_separator(u1),
    expected,
    msg=u1.to_string(),
  )
}

///|
test "trailingPathSeparator" {
  assert_trailing_separator(Uri::parse("foo://a/foo"), false)
  assert_trailing_separator(Uri::parse("foo://a/foo/"), true)
  assert_trailing_separator(Uri::parse("foo://a/"), false)
  assert_trailing_separator(Uri::parse("foo://a"), false)
  assert_remove_trailing_separator(
    Uri::parse("foo://a/foo"),
    Uri::parse("foo://a/foo"),
  )
  assert_remove_trailing_separator(
    Uri::parse("foo://a/foo/"),
    Uri::parse("foo://a/foo"),
  )
  assert_remove_trailing_separator(
    Uri::parse("foo://a/"),
    Uri::parse("foo://a/"),
  )
  assert_remove_trailing_separator(Uri::parse("foo://a"), Uri::parse("foo://a"))
  assert_add_trailing_separator(
    Uri::parse("foo://a/foo"),
    Uri::parse("foo://a/foo/"),
  )
  assert_add_trailing_separator(
    Uri::parse("foo://a/foo/"),
    Uri::parse("foo://a/foo/"),
  )
  assert_add_trailing_separator(Uri::parse("foo://a/"), Uri::parse("foo://a/"))
  assert_add_trailing_separator(Uri::parse("foo://a"), Uri::parse("foo://a/"))
  set_is_windows_for_testing(value=true)
  assert_trailing_separator(Uri::file("c:\\a\\foo"), false)
  assert_trailing_separator(Uri::file("c:\\a\\foo\\"), true)
  assert_trailing_separator(Uri::file("c:\\"), false)
  assert_trailing_separator(Uri::file("\\\\server\\share\\some\\"), true)
  assert_trailing_separator(Uri::file("\\\\server\\share\\"), false)
  assert_remove_trailing_separator(
    Uri::file("c:\\a\\foo"),
    Uri::file("c:\\a\\foo"),
  )
  assert_remove_trailing_separator(
    Uri::file("c:\\a\\foo\\"),
    Uri::file("c:\\a\\foo"),
  )
  assert_remove_trailing_separator(Uri::file("c:\\"), Uri::file("c:\\"))
  assert_remove_trailing_separator(
    Uri::file("\\\\server\\share\\some\\"),
    Uri::file("\\\\server\\share\\some"),
  )
  assert_remove_trailing_separator(
    Uri::file("\\\\server\\share\\"),
    Uri::file("\\\\server\\share\\"),
  )
  assert_add_trailing_separator(
    Uri::file("c:\\a\\foo"),
    Uri::file("c:\\a\\foo\\"),
  )
  assert_add_trailing_separator(
    Uri::file("c:\\a\\foo\\"),
    Uri::file("c:\\a\\foo\\"),
  )
  assert_add_trailing_separator(Uri::file("c:\\"), Uri::file("c:\\"))
  assert_add_trailing_separator(
    Uri::file("\\\\server\\share\\some"),
    Uri::file("\\\\server\\share\\some\\"),
  )
  assert_add_trailing_separator(
    Uri::file("\\\\server\\share\\some\\"),
    Uri::file("\\\\server\\share\\some\\"),
  )
  set_is_windows_for_testing(value=false)
  assert_trailing_separator(Uri::file("/foo/bar"), false)
  assert_trailing_separator(Uri::file("/foo/bar/"), true)
  assert_trailing_separator(Uri::file("/"), false)
  assert_remove_trailing_separator(Uri::file("/foo/bar"), Uri::file("/foo/bar"))
  assert_remove_trailing_separator(
    Uri::file("/foo/bar/"),
    Uri::file("/foo/bar"),
  )
  assert_remove_trailing_separator(Uri::file("/"), Uri::file("/"))
  assert_add_trailing_separator(Uri::file("/foo/bar"), Uri::file("/foo/bar/"))
  assert_add_trailing_separator(Uri::file("/foo/bar/"), Uri::file("/foo/bar/"))
  assert_add_trailing_separator(Uri::file("/"), Uri::file("/"))
  set_is_windows_for_testing()
}

///|
fn assert_relative_path(
  u1 : Uri,
  u2 : Uri,
  expected_path : String?,
  ignore_join? : Bool = false,
  ignore_case? : Bool = false,
) -> Unit raise {
  let util = if ignore_case { ext_uri_ignore_path_case } else { ext_uri }
  assert_true(
    util.relative_path(u1, u2) == expected_path,
    msg="from \{u1.to_string()} to \{u2.to_string()}: got \{Repr(util.relative_path(u1, u2))}, want \{Repr(expected_path)}",
  )
  if expected_path is Some(path) && !ignore_join {
    assert_equal_uri(
      remove_trailing_path_separator(join_path(u1, [path])),
      remove_trailing_path_separator(u2),
      msg="joinPath on relativePath should be equal",
      ignore_case~,
    )
  }
}

///|
test "relativePath" {
  assert_relative_path(
    Uri::parse("foo://a/foo"),
    Uri::parse("foo://a/foo/bar"),
    Some("bar"),
  )
  assert_relative_path(
    Uri::parse("foo://a/foo"),
    Uri::parse("foo://a/foo/bar/"),
    Some("bar"),
  )
  assert_relative_path(
    Uri::parse("foo://a/foo"),
    Uri::parse("foo://a/foo/bar/goo"),
    Some("bar/goo"),
  )
  assert_relative_path(
    Uri::parse("foo://a/"),
    Uri::parse("foo://a/foo/bar/goo"),
    Some("foo/bar/goo"),
  )
  assert_relative_path(
    Uri::parse("foo://a/foo/xoo"),
    Uri::parse("foo://a/foo/bar"),
    Some("../bar"),
  )
  assert_relative_path(
    Uri::parse("foo://a/foo/xoo/yoo"),
    Uri::parse("foo://a"),
    Some("../../.."),
    ignore_join=true,
  )
  assert_relative_path(
    Uri::parse("foo://a/foo"),
    Uri::parse("foo://a/foo/"),
    Some(""),
  )
  assert_relative_path(
    Uri::parse("foo://a/foo/"),
    Uri::parse("foo://a/foo"),
    Some(""),
  )
  assert_relative_path(
    Uri::parse("foo://a/foo/"),
    Uri::parse("foo://a/foo/"),
    Some(""),
  )
  assert_relative_path(
    Uri::parse("foo://a/foo"),
    Uri::parse("foo://a/foo"),
    Some(""),
  )
  assert_relative_path(
    Uri::parse("foo://a"),
    Uri::parse("foo://a"),
    Some(""),
    ignore_join=true,
  )
  assert_relative_path(Uri::parse("foo://a/"), Uri::parse("foo://a/"), Some(""))
  assert_relative_path(
    Uri::parse("foo://a/"),
    Uri::parse("foo://a"),
    Some(""),
    ignore_join=true,
  )
  assert_relative_path(
    Uri::parse("foo://a/foo?q"),
    Uri::parse("foo://a/foo/bar#h"),
    Some("bar"),
    ignore_join=true,
  )
  assert_relative_path(Uri::parse("foo://"), Uri::parse("foo://a/b"), None)
  assert_relative_path(Uri::parse("foo://a2/b"), Uri::parse("foo://a/b"), None)
  assert_relative_path(Uri::parse("goo://a/b"), Uri::parse("foo://a/b"), None)
  assert_relative_path(
    Uri::parse("foo://a/foo"),
    Uri::parse("foo://A/FOO/bar/goo"),
    Some("bar/goo"),
    ignore_case=true,
  )
  assert_relative_path(
    Uri::parse("foo://a/foo"),
    Uri::parse("foo://A/FOO/BAR/GOO"),
    Some("BAR/GOO"),
    ignore_case=true,
  )
  assert_relative_path(
    Uri::parse("foo://a/foo/xoo"),
    Uri::parse("foo://A/FOO/BAR/GOO"),
    Some("../BAR/GOO"),
    ignore_case=true,
  )
  assert_relative_path(
    Uri::parse("foo:///c:/a/foo"),
    Uri::parse("foo:///C:/a/foo/xoo/"),
    Some("xoo"),
    ignore_case=true,
  )
  set_is_windows_for_testing(value=true)
  assert_relative_path(
    Uri::file("c:\\foo\\bar"),
    Uri::file("c:\\foo\\bar"),
    Some(""),
  )
  assert_relative_path(
    Uri::file("c:\\foo\\bar\\huu"),
    Uri::file("c:\\foo\\bar"),
    Some(".."),
  )
  assert_relative_path(
    Uri::file("c:\\foo\\bar\\a1\\a2"),
    Uri::file("c:\\foo\\bar"),
    Some("../.."),
  )
  assert_relative_path(
    Uri::file("c:\\foo\\bar\\"),
    Uri::file("c:\\foo\\bar\\a1\\a2"),
    Some("a1/a2"),
  )
  assert_relative_path(
    Uri::file("c:\\foo\\bar\\"),
    Uri::file("c:\\foo\\bar\\a1\\a2\\"),
    Some("a1/a2"),
  )
  assert_relative_path(
    Uri::file("c:\\"),
    Uri::file("c:\\foo\\bar"),
    Some("foo/bar"),
  )
  assert_relative_path(
    Uri::file("\\\\server\\share\\some\\"),
    Uri::file("\\\\server\\share\\some\\path"),
    Some("path"),
  )
  // ignore joinPath assert: path.join is not root aware
  assert_relative_path(
    Uri::file("\\\\server\\share\\some\\"),
    Uri::file("\\\\server\\share2\\some\\path"),
    Some("../../share2/some/path"),
    ignore_join=true,
  )
  set_is_windows_for_testing(value=false)
  assert_relative_path(
    Uri::file("/a/foo"),
    Uri::file("/a/foo/bar"),
    Some("bar"),
  )
  assert_relative_path(
    Uri::file("/a/foo"),
    Uri::file("/a/foo/bar/"),
    Some("bar"),
  )
  assert_relative_path(
    Uri::file("/a/foo"),
    Uri::file("/a/foo/bar/goo"),
    Some("bar/goo"),
  )
  assert_relative_path(
    Uri::file("/a/"),
    Uri::file("/a/foo/bar/goo"),
    Some("foo/bar/goo"),
  )
  assert_relative_path(
    Uri::file("/"),
    Uri::file("/a/foo/bar/goo"),
    Some("a/foo/bar/goo"),
  )
  assert_relative_path(
    Uri::file("/a/foo/xoo"),
    Uri::file("/a/foo/bar"),
    Some("../bar"),
  )
  assert_relative_path(
    Uri::file("/a/foo/xoo/yoo"),
    Uri::file("/a"),
    Some("../../.."),
  )
  assert_relative_path(Uri::file("/a/foo"), Uri::file("/a/foo/"), Some(""))
  assert_relative_path(
    Uri::file("/a/foo"),
    Uri::file("/b/foo/"),
    Some("../../b/foo"),
  )
  set_is_windows_for_testing()
}

///|
fn assert_resolve(
  u1 : Uri,
  path : String,
  expected : Uri,
  is_win : Bool,
) -> Unit raise {
  let actual = resolve_path(u1, path)
  assert_equal_uri(actual, expected, msg="from \{u1.to_string()} and \{path}")
  let path_is_absolute = if path.contains("/") {
    Posix::is_absolute(path)
  } else {
    Win32::is_absolute(path)
  }
  if !path_is_absolute {
    let mut expected_path = if is_win { to_slashes(path) } else { path }
    expected_path = if expected_path.has_prefix("./") {
      expected_path[2:].to_owned()
    } else {
      expected_path
    }
    assert_true(
      relative_path(u1, actual) == Some(expected_path),
      msg="relativePath (\{u1.to_string()}) on actual (\{actual.to_string()}) should be to path (\{expected_path})",
    )
  }
}

///|
test "resolve" {
  set_is_windows_for_testing(value=true)
  assert_resolve(
    Uri::file("c:\\foo\\bar"),
    "file.js",
    Uri::file("c:\\foo\\bar\\file.js"),
    true,
  )
  assert_resolve(
    Uri::file("c:\\foo\\bar"),
    "t\\file.js",
    Uri::file("c:\\foo\\bar\\t\\file.js"),
    true,
  )
  assert_resolve(
    Uri::file("c:\\foo\\bar"),
    ".\\t\\file.js",
    Uri::file("c:\\foo\\bar\\t\\file.js"),
    true,
  )
  assert_resolve(
    Uri::file("c:\\foo\\bar"),
    "a1/file.js",
    Uri::file("c:\\foo\\bar\\a1\\file.js"),
    true,
  )
  assert_resolve(
    Uri::file("c:\\foo\\bar"),
    "./a1/file.js",
    Uri::file("c:\\foo\\bar\\a1\\file.js"),
    true,
  )
  assert_resolve(
    Uri::file("c:\\foo\\bar"),
    "\\b1\\file.js",
    Uri::file("c:\\b1\\file.js"),
    true,
  )
  assert_resolve(
    Uri::file("c:\\foo\\bar"),
    "/b1/file.js",
    Uri::file("c:\\b1\\file.js"),
    true,
  )
  assert_resolve(
    Uri::file("c:\\foo\\bar\\"),
    "file.js",
    Uri::file("c:\\foo\\bar\\file.js"),
    true,
  )
  assert_resolve(Uri::file("c:\\"), "file.js", Uri::file("c:\\file.js"), true)
  assert_resolve(
    Uri::file("c:\\"),
    "\\b1\\file.js",
    Uri::file("c:\\b1\\file.js"),
    true,
  )
  assert_resolve(
    Uri::file("c:\\"),
    "/b1/file.js",
    Uri::file("c:\\b1\\file.js"),
    true,
  )
  assert_resolve(
    Uri::file("c:\\"),
    "d:\\foo\\bar.txt",
    Uri::file("d:\\foo\\bar.txt"),
    true,
  )
  assert_resolve(
    Uri::file("\\\\server\\share\\some\\"),
    "b1\\file.js",
    Uri::file("\\\\server\\share\\some\\b1\\file.js"),
    true,
  )
  assert_resolve(
    Uri::file("\\\\server\\share\\some\\"),
    "\\file.js",
    Uri::file("\\\\server\\share\\file.js"),
    true,
  )
  assert_resolve(
    Uri::file("c:\\"),
    "\\\\server\\share\\some\\",
    Uri::file("\\\\server\\share\\some"),
    true,
  )
  assert_resolve(
    Uri::file("\\\\server\\share\\some\\"),
    "c:\\",
    Uri::file("c:\\"),
    true,
  )
  set_is_windows_for_testing(value=false)
  assert_resolve(
    Uri::file("/foo/bar"),
    "file.js",
    Uri::file("/foo/bar/file.js"),
    false,
  )
  assert_resolve(
    Uri::file("/foo/bar"),
    "./file.js",
    Uri::file("/foo/bar/file.js"),
    false,
  )
  assert_resolve(
    Uri::file("/foo/bar"),
    "/file.js",
    Uri::file("/file.js"),
    false,
  )
  assert_resolve(
    Uri::file("/foo/bar/"),
    "file.js",
    Uri::file("/foo/bar/file.js"),
    false,
  )
  assert_resolve(Uri::file("/"), "file.js", Uri::file("/file.js"), false)
  assert_resolve(Uri::file(""), "./file.js", Uri::file("/file.js"), false)
  assert_resolve(Uri::file(""), "/file.js", Uri::file("/file.js"), false)
  assert_resolve(
    Uri::parse("foo://server/foo/bar"),
    "file.js",
    Uri::parse("foo://server/foo/bar/file.js"),
    false,
  )
  assert_resolve(
    Uri::parse("foo://server/foo/bar"),
    "./file.js",
    Uri::parse("foo://server/foo/bar/file.js"),
    false,
  )
  assert_resolve(
    Uri::parse("foo://server/foo/bar"),
    "c:\\a1\\b1",
    Uri::parse("foo://server/c:/a1/b1"),
    false,
  )
  assert_resolve(
    Uri::parse("foo://server/foo/bar"),
    "c:\\",
    Uri::parse("foo://server/c:"),
    false,
  )
  set_is_windows_for_testing()
}

///|
fn assert_is_equal(
  u1 : Uri,
  u2 : Uri,
  ignore_case : Bool?,
  expected : Bool,
) -> Unit raise {
  let util = if ignore_case is Some(true) {
    ext_uri_ignore_path_case
  } else {
    ext_uri
  }
  let relation = if expected { "===" } else { "!==" }
  assert_eq(
    util.is_equal(Some(u1), Some(u2)),
    expected,
    msg="\{u1.to_string()}\{relation}\{u2.to_string()}",
  )
  assert_eq(util.compare(u1, u2) == 0, expected)
  assert_eq(
    util.get_comparison_key(u1) == util.get_comparison_key(u2),
    expected,
    msg="comparison keys \{u1.to_string()}, \{u2.to_string()}",
  )
  assert_eq(
    util.is_equal_or_parent(u1, u2),
    expected,
    msg="isEqualOrParent \{u1.to_string()}, \{u2.to_string()}",
  )
  if !(ignore_case is Some(true)) {
    assert_eq(u1.to_string() == u2.to_string(), expected)
  }
}

///|
fn run_is_equal_suite(file_uri : Uri, file_uri2 : Uri) -> Unit raise {
  assert_is_equal(file_uri, file_uri, Some(true), true)
  assert_is_equal(file_uri, file_uri, Some(false), true)
  assert_is_equal(file_uri, file_uri, None, true)
  assert_is_equal(file_uri, file_uri2, Some(true), true)
  assert_is_equal(file_uri, file_uri2, Some(false), false)
  let file_uri3 = Uri::parse("foo://server:453/foo/bar")
  let file_uri4 = Uri::parse("foo://server:453/foo/Bar")
  assert_is_equal(file_uri3, file_uri3, Some(true), true)
  assert_is_equal(file_uri3, file_uri3, Some(false), true)
  assert_is_equal(file_uri3, file_uri3, None, true)
  assert_is_equal(file_uri3, file_uri4, Some(true), true)
  assert_is_equal(file_uri3, file_uri4, Some(false), false)
  assert_is_equal(file_uri, file_uri3, Some(true), false)
  assert_is_equal(
    Uri::parse("file://server"),
    Uri::parse("file://server/"),
    Some(true),
    true,
  )
  assert_is_equal(
    Uri::parse("http://server"),
    Uri::parse("http://server/"),
    Some(true),
    true,
  )
  // only selected scheme have / as the default path
  assert_is_equal(
    Uri::parse("foo://server"),
    Uri::parse("foo://server/"),
    Some(true),
    false,
  )
  assert_is_equal(
    Uri::parse("foo://server/foo"),
    Uri::parse("foo://server/foo/"),
    Some(true),
    false,
  )
  assert_is_equal(
    Uri::parse("foo://server/foo"),
    Uri::parse("foo://server/foo?"),
    Some(true),
    true,
  )
  let file_uri5 = Uri::parse("foo://server:453/foo/bar?q=1")
  let file_uri6 = Uri::parse("foo://server:453/foo/bar#xy")
  assert_is_equal(file_uri5, file_uri5, Some(true), true)
  assert_is_equal(file_uri5, file_uri3, Some(true), false)
  assert_is_equal(file_uri6, file_uri6, Some(true), true)
  assert_is_equal(file_uri6, file_uri5, Some(true), false)
  assert_is_equal(file_uri6, file_uri3, Some(true), false)
}

///|
test "isEqual" {
  set_is_windows_for_testing(value=false)
  run_is_equal_suite(Uri::file("/foo/bar"), Uri::file("/foo/Bar"))
  set_is_windows_for_testing(value=true)
  run_is_equal_suite(Uri::file("c:\\foo\\bar"), Uri::file("C:\\foo\\Bar"))
  set_is_windows_for_testing()
}

///|
fn run_is_equal_or_parent_suite(
  file_uri : Uri,
  file_uri2 : Uri,
  file_uri2b : Uri,
) -> Unit raise {
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(file_uri, file_uri),
    true,
    msg="1",
  )
  assert_eq(ext_uri.is_equal_or_parent(file_uri, file_uri), true, msg="2")
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(file_uri, file_uri2),
    true,
    msg="3",
  )
  assert_eq(ext_uri.is_equal_or_parent(file_uri, file_uri2), true, msg="4")
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(file_uri, file_uri2b),
    true,
    msg="5",
  )
  assert_eq(ext_uri.is_equal_or_parent(file_uri, file_uri2b), false, msg="6")
  assert_eq(ext_uri.is_equal_or_parent(file_uri2, file_uri), false, msg="7")
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(file_uri2b, file_uri2),
    true,
    msg="8",
  )
  let file_uri3 = Uri::parse("foo://server:453/foo/bar/goo")
  let file_uri4 = Uri::parse("foo://server:453/foo/")
  let file_uri5 = Uri::parse("foo://server:453/foo")
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(
      file_uri3,
      file_uri3,
      ignore_fragment=true,
    ),
    true,
    msg="11",
  )
  assert_eq(ext_uri.is_equal_or_parent(file_uri3, file_uri3), true, msg="12")
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(
      file_uri3,
      file_uri4,
      ignore_fragment=true,
    ),
    true,
    msg="13",
  )
  assert_eq(ext_uri.is_equal_or_parent(file_uri3, file_uri4), true, msg="14")
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(
      file_uri3,
      file_uri,
      ignore_fragment=true,
    ),
    false,
    msg="15",
  )
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(
      file_uri5,
      file_uri5,
      ignore_fragment=true,
    ),
    true,
    msg="16",
  )
  let file_uri6 = Uri::parse("foo://server:453/foo?q=1")
  let file_uri7 = Uri::parse("foo://server:453/foo/bar?q=1")
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(file_uri6, file_uri5),
    false,
    msg="17",
  )
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(file_uri6, file_uri6),
    true,
    msg="18",
  )
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(file_uri7, file_uri6),
    true,
    msg="19",
  )
  assert_eq(
    ext_uri_ignore_path_case.is_equal_or_parent(file_uri7, file_uri5),
    false,
    msg="20",
  )
}

///|
test "isEqualOrParent" {
  set_is_windows_for_testing(value=false)
  run_is_equal_or_parent_suite(
    Uri::file("/foo/bar"),
    Uri::file("/foo"),
    Uri::file("/Foo/"),
  )
  set_is_windows_for_testing(value=true)
  run_is_equal_or_parent_suite(
    Uri::file("c:\\foo\\bar"),
    Uri::file("c:\\foo"),
    Uri::file("C:\\Foo\\"),
  )
  set_is_windows_for_testing()
}

///|
test "isEqualOrParent handles ../" {
  set_is_windows_for_testing(value=false)
  let file_uri = Uri::file("/home/user/projects")
  let file_uri2 = Uri::file("/home/user/projects/../../../../tmp/folder")
  assert_eq(ext_uri.is_equal_or_parent(file_uri2, file_uri), false)
  set_is_windows_for_testing()
}

///|
test "compare is code-unit lexicographic, not length-first (test matrix)" {
  // MoonBit's built-in String compare would order "z" before "aa".
  assert_eq(ext_uri.compare(Uri::parse("s://x/z"), Uri::parse("s://x/aa")), 1)
  assert_eq(ext_uri.compare(Uri::parse("s://x/aa"), Uri::parse("s://x/z")), -1)
  assert_eq(ext_uri.compare(Uri::parse("s://x/a"), Uri::parse("s://x/a")), 0)
  // fragment handling
  assert_eq(
    ext_uri.compare(
      Uri::parse("s://x/a#f"),
      Uri::parse("s://x/a"),
      ignore_fragment=true,
    ),
    0,
  )
}
