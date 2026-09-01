///|
#cfg(not(platform="windows"))
test "contains normalizes POSIX paths before comparing them" {
  guard @pathx.Path("/ws/proj").to_absolute() is Some(root) else {
    fail("test root was not absolute")
  }
  guard @pathx.Path("/ws/proj/tmp/../src/a.mbt").to_absolute() is Some(file) else {
    fail("test file was not absolute")
  }
  guard @pathx.Path("/ws/project/a.mbt").to_absolute() is Some(sibling) else {
    fail("test sibling was not absolute")
  }
  assert_true(root.contains(file))
  assert_true(root.contains(root))
  assert_false(root.contains(sibling))
  guard @pathx.Path("/ws/proj/dir\\name/a.mbt").to_absolute()
    is Some(backslash_name) else {
    fail("test backslash filename was not absolute")
  }
  guard @pathx.Path("/ws/proj/dir/name/a.mbt").to_absolute()
    is Some(nested_name) else {
    fail("test nested name was not absolute")
  }
  assert_true(root.contains(backslash_name))
  assert_false(backslash_name.contains(nested_name))
}

///|
#cfg(platform="windows")
test "contains normalizes Windows paths before comparing them" {
  guard @pathx.Path("C:\\ws\\proj").to_absolute() is Some(root) else {
    fail("test root was not absolute")
  }
  guard @pathx.Path("C:\\ws\\proj\\tmp\\..\\src\\a.mbt").to_absolute()
    is Some(file) else {
    fail("test file was not absolute")
  }
  guard @pathx.Path("C:/ws/project/a.mbt").to_absolute() is Some(sibling) else {
    fail("test sibling was not absolute")
  }
  assert_true(root.contains(file))
  assert_true(root.contains(root))
  assert_false(root.contains(sibling))
}

///|
test "Relative containment normalizes paths before comparing them" {
  assert_true(@pathx.Relative("src").contains(Relative("src/tmp/../a.mbt")))
  assert_false(
    @pathx.Relative("src").contains(Relative("src/tmp/../../src2/a.mbt")),
  )
}

///|
#cfg(not(platform="windows"))
test "Path converts host-absolute POSIX paths to Absolute" {
  assert_true(
    @pathx.Path("/ws/src/a.mbt").to_absolute()
    is Some(Absolute("/ws/src/a.mbt")),
  )
  // Windows syntax is only absolute on a Windows host.
  for path in ["C:/ws/src/a.mbt", "C:\\ws\\src\\a.mbt", "\\\\server\\share"] {
    assert_true(@pathx.Path(path).to_absolute() is None)
  }
}

///|
#cfg(platform="windows")
test "Path converts host-absolute Windows paths to Absolute" {
  assert_true(
    @pathx.Path("C:/ws/src/a.mbt").to_absolute()
    is Some(Absolute("C:/ws/src/a.mbt")),
  )
  assert_true(
    @pathx.Path("C:\\ws\\src\\a.mbt").to_absolute()
    is Some(Absolute("C:\\ws\\src\\a.mbt")),
  )
  assert_true(
    @pathx.Path("\\\\server\\share\\a.mbt").to_absolute()
    is Some(Absolute("\\\\server\\share\\a.mbt")),
  )
}

///|
test "Path rejects relative conversion" {
  for path in ["", "src/a.mbt", "C:src\\a.mbt"] {
    assert_true(@pathx.Path(path).to_absolute() is None)
  }
}

///|
test "Path classifies non-absolute paths as Relative" {
  assert_true(
    @pathx.Path("src/../main.mbt").to_relative() ==
    Some(Relative("src/../main.mbt")),
  )
  assert_true(@pathx.Path("/workspace").to_relative() is None)
}

///|
test "Path::resolve returns a host-absolute path" {
  let resolved = @pathx.Path(".").resolve()
  assert_true(resolved.to_path().is_host_absolute())
}

///|
#cfg(not(platform="windows"))
test "Absolute::relative_to normalizes POSIX paths" {
  guard @pathx.Path("/ws").to_absolute() is Some(root) else {
    fail("test root was not absolute")
  }
  assert_true(
    @pathx.Path("/ws/tmp/../src/a.mbt").to_absolute() is Some(path) &&
    path.relative_to(root~) == Some(Relative("src/a.mbt")),
  )
  assert_true(
    @pathx.Path("/ws/.").to_absolute() is Some(path) &&
    path.relative_to(root~) is Some(rest) &&
    rest.is_root(),
  )
  assert_true(
    @pathx.Path("/other/a.mbt").to_absolute() is Some(path) &&
    path.relative_to(root~) is None,
  )
  // POSIX path identity remains case-sensitive.
  assert_true(
    @pathx.Path("/WS/src/a.mbt").to_absolute() is Some(path) &&
    path.relative_to(root~) is None,
  )
  // A trailing slash on the root reads the same as none.
  guard @pathx.Path("/ws/").to_absolute() is Some(root_with_slash) else {
    fail("test root with slash was not absolute")
  }
  assert_true(
    @pathx.Path("/ws/a.mbt").to_absolute() is Some(path) &&
    path.relative_to(root=root_with_slash) == Some(Relative("a.mbt")),
  )
}

///|
#cfg(platform="windows")
test "Absolute::relative_to normalizes Windows paths" {
  guard @pathx.Path("C:\\ws").to_absolute() is Some(root) else {
    fail("test root was not absolute")
  }
  assert_true(
    @pathx.Path("C:\\ws\\tmp\\..\\src\\a.mbt").to_absolute() is Some(path) &&
    path.relative_to(root~) == Some(Relative("src/a.mbt")),
  )
  assert_true(
    @pathx.Path("C:\\ws\\.").to_absolute() is Some(path) &&
    path.relative_to(root~) is Some(rest) &&
    rest.is_root(),
  )
  assert_true(
    @pathx.Path("C:\\other\\a.mbt").to_absolute() is Some(path) &&
    path.relative_to(root~) is None,
  )
  // Windows resolves the same drive and workspace components regardless of
  // spelling case, while preserving the target's relative component spelling.
  assert_true(
    @pathx.Path("c:\\WS\\src\\A.mbt").to_absolute() is Some(path) &&
    path.relative_to(root~) == Some(Relative("src/A.mbt")),
  )
  assert_true(
    @pathx.Path("C:\\workspace\\a.mbt").to_absolute() is Some(path) &&
    path.relative_to(root~) is None,
  )
}

///|
test "the root relative path is the zero-segment one" {
  assert_true(@pathx.Relative::root().is_root())
  assert_true(@pathx.Relative("").normalize().is_root())
  assert_true(@pathx.Relative(".").normalize().is_root())
  assert_true(@pathx.Relative("a/..").normalize().is_root())
  assert_false(@pathx.Relative("src").is_root())
}

///|
#cfg(not(platform="windows"))
test "normalize uses POSIX host rules" {
  assert_true(@pathx.Path("a/./b/../c").normalize() == Path("a/c"))
  assert_true(
    @pathx.Path("dir\\name/./file").normalize() == Path("dir\\name/file"),
  )
  assert_true(
    @pathx.Relative("src/tmp/../main.mbt").normalize() ==
    Relative("src/main.mbt"),
  )
  assert_true(
    @pathx.Relative("dir\\name/./file").normalize() ==
    Relative("dir\\name/file"),
  )
  guard @pathx.Path("/a/./b/../c").to_absolute() is Some(absolute) else {
    fail("test path was not absolute")
  }
  assert_true(absolute.normalize() is Absolute("/a/c"))
  guard @pathx.Path("/dir\\name/./file").to_absolute() is Some(backslash_name) else {
    fail("test backslash filename was not absolute")
  }
  assert_true(backslash_name.normalize() is Absolute("/dir\\name/file"))
}

///|
#cfg(platform="windows")
test "normalize uses Windows host rules and typed paths use forward slashes" {
  assert_true(@pathx.Path("a/./b/../c").normalize() == Path("a\\c"))
  assert_true(
    @pathx.Relative("src\\tmp\\..\\main.mbt").normalize() ==
    Relative("src/main.mbt"),
  )
  guard @pathx.Path("C:\\a\\.\\b\\..\\c").to_absolute() is Some(absolute) else {
    fail("test path was not absolute")
  }
  assert_true(absolute.normalize() is Absolute("C:/a/c"))
}

///|
#cfg(not(platform="windows"))
test "other host path operations keep POSIX spellings" {
  assert_eq(@pathx.Path("a").join(Relative("b")).0, "a/b")
  guard @pathx.Path("/a").to_absolute() is Some(root) else {
    fail("test root was not absolute")
  }
  assert_true(root.join(Relative("b/../c")) is Absolute("/a/c"))
  assert_eq(@pathx.Path("a/b.txt").dirname().0, "a")
  assert_eq(@pathx.Path("a/b.txt").basename().to_owned(), "b.txt")
  assert_eq(@pathx.Path("a/b.txt").extname().to_owned(), ".txt")
}

///|
#cfg(platform="windows")
test "other host path operations keep Windows spellings" {
  assert_eq(@pathx.Path("a").join(Relative("b")).0, "a\\b")
  guard @pathx.Path("C:\\a").to_absolute() is Some(root) else {
    fail("test root was not absolute")
  }
  assert_true(root.join(Relative("b/../c")) is Absolute("C:\\a\\c"))
  assert_eq(@pathx.Path("a\\b.txt").dirname().0, "a")
  assert_eq(@pathx.Path("a\\b.txt").basename().to_owned(), "b.txt")
  assert_eq(@pathx.Path("a\\b.txt").extname().to_owned(), ".txt")
}

///|
#cfg(not(platform="windows"))
test "POSIX absolute paths round-trip through URI paths" {
  guard @pathx.Path("/work/a b/#file.mbt").to_absolute() is Some(absolute) else {
    fail("expected an absolute POSIX fixture")
  }
  assert_eq(absolute.to_uri_path(), Some("/work/a b/#file.mbt"))
  assert_eq(
    @pathx.Absolute::from_uri_path("/work/a b/#file.mbt"),
    Some(absolute),
  )
}

///|
#cfg(not(platform="windows"))
test "resource URI conversion rejects double-rooted POSIX paths" {
  guard @pathx.Path("//server/share/a.mbt").to_absolute() is Some(absolute) else {
    fail("expected an absolute POSIX fixture")
  }
  assert_true(absolute.to_uri_path() is None)
  assert_true(@pathx.Absolute::from_uri_path("//server/share/a.mbt") is None)
}

///|
#cfg(platform="windows")
test "Windows drive paths round-trip through URI paths" {
  guard @pathx.Path("C:\\work\\a b\\#file.mbt").to_absolute() is Some(absolute) else {
    fail("expected an absolute Windows fixture")
  }
  assert_eq(absolute.to_uri_path(), Some("/C:/work/a b/#file.mbt"))
  assert_true(
    @pathx.Absolute::from_uri_path("/C:/work/a b/#file.mbt") is Some(decoded) &&
    decoded.normalize() == absolute.normalize(),
  )
}

///|
#cfg(platform="windows")
test "resource URI conversion rejects UNC and root-relative Windows paths" {
  for path in ["\\\\server\\share\\a.mbt", "\\rooted\\a.mbt"] {
    guard @pathx.Path(path).to_absolute() is Some(absolute) else {
      fail("expected an absolute Windows fixture")
    }
    assert_true(absolute.to_uri_path() is None)
  }
  assert_true(@pathx.Absolute::from_uri_path("//server/share/a.mbt") is None)
  assert_true(@pathx.Absolute::from_uri_path("/rooted/a.mbt") is None)
}
