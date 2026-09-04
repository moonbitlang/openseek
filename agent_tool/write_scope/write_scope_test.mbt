///|
/// Build a scope over `root` or fail the test with the create error.
async fn scope_of(
  root : String,
  allowed_paths? : Array[String] = [],
) -> @write_scope.WriteScope {
  match @write_scope.WriteScope::create(root~, allowed_paths~) {
    Ok(scope) => scope
    Err(reason) => fail(reason)
  }
}

///|
async fn assert_admits(scope : @write_scope.WriteScope, path : String) -> Unit {
  match scope.deny_reason(path) {
    None => ()
    Some(reason) => fail("expected \{path} admitted, denied: \{reason}")
  }
}

///|
async fn assert_denies(
  scope : @write_scope.WriteScope,
  path : String,
  because~ : String,
) -> Unit {
  match scope.deny_reason(path) {
    Some(reason) => assert_true(reason.contains(because))
    None => fail("expected \{path} denied (\{because}), was admitted")
  }
}

///|
async test "root-only scope admits inside and denies outside" {
  @vfs.with_tmpdir(prefix="write-scope-root-", root => {
    @vfs.FileSystem({ "src/a.mbt": "a", "top.txt": "t" }).write_to(root)
    let scope = scope_of(root)
    assert_admits(scope, "\{root}/src/a.mbt")
    assert_admits(scope, "src/a.mbt")
    assert_admits(scope, "\{root}/src/newdir/deep/new.mbt")
    assert_denies(scope, "/etc/hosts", because="outside the writable root")
    assert_denies(
      scope,
      "\{root}/../outside.txt",
      because="outside the writable root",
    )
    // `..` that stays inside the root is fine after normalization.
    assert_admits(scope, "\{root}/src/../top.txt")
  })
}

///|
async test "allowed prefixes are component-wise" {
  @vfs.with_tmpdir(prefix="write-scope-prefix-", root => {
    @vfs.FileSystem({
      "src/a.mbt": "a",
      "src2/b.mbt": "b",
      "docs/notes/n.md": "n",
    }).write_to(root)
    let scope = scope_of(root, allowed_paths=["src", "docs/notes"])
    assert_admits(scope, "\{root}/src/a.mbt")
    assert_admits(scope, "\{root}/src/sub/new.mbt")
    assert_admits(scope, "\{root}/docs/notes/n.md")
    // `src` must not admit `src2`, and a parent of a prefix is not a target.
    assert_denies(scope, "\{root}/src2/b.mbt", because="allowed_paths")
    assert_denies(scope, "\{root}/docs/other.md", because="allowed_paths")
    assert_denies(scope, "\{root}/docs", because="allowed_paths")
  })
}

///|
#cfg(not(platform="windows"))
async test "symlinks cannot smuggle writes out of scope" {
  @vfs.with_tmpdir(prefix="write-scope-links-", root => {
    @vfs.FileSystem({
      "src/real.mbt": "r",
      "src/inner/i.mbt": "i",
      "outside_prefix/o.mbt": "o",
      "victim/v.mbt": "v",
    }).write_to(root)
    @vfs.with_tmpdir(prefix="write-scope-elsewhere-", elsewhere => {
      @vfs.write_text(elsewhere, "target.txt", "x")
      let scope = scope_of(root, allowed_paths=["src"])
      // Final-component symlink pointing out of the root: denied on the
      // resolved location even though the request is lexically in-scope.
      @fs.symlink(target="\{elsewhere}/target.txt", "\{root}/src/out_link")
      assert_denies(scope, "\{root}/src/out_link", because="resolves outside")
      // Ancestor symlink out of the root: a new file beneath it is denied.
      @fs.symlink(target=elsewhere, "\{root}/src/out_dir")
      assert_denies(
        scope,
        "\{root}/src/out_dir/new.mbt",
        because="resolves outside",
      )
      // In-root but out-of-allowed symlink: root check passes, prefix check
      // on the resolved location fails.
      @fs.symlink(target="\{root}/victim/v.mbt", "\{root}/src/in_root_link")
      assert_denies(scope, "\{root}/src/in_root_link", because="allowed_paths")
      // Dangling symlink fails closed.
      @fs.symlink(target="\{root}/missing.mbt", "\{root}/src/dangling")
      assert_denies(scope, "\{root}/src/dangling", because="does not resolve")
      // Honest paths keep working alongside the links.
      assert_admits(scope, "\{root}/src/inner/i.mbt")
    })
  })
}

///|
async test "create validates root and prefixes strictly" {
  @vfs.with_tmpdir(prefix="write-scope-validate-", root => {
    guard @write_scope.WriteScope::create(root="\{root}/missing")
      is Err(no_root) else {
      fail("expected missing root rejected")
    }
    assert_true(no_root.contains("does not resolve"))
    for
      bad in [
        "", ".", "..", "a/../b", "/abs", "a//b", ".git/hooks", ".worktrees/x",
      ] {
      guard @write_scope.WriteScope::create(root~, allowed_paths=[bad])
        is Err(_) else {
        fail("expected allowed_paths entry rejected: \{bad}")
      }
    }
    guard @write_scope.WriteScope::create(root~, allowed_paths=[
        "src", "docs/notes", "a/b/c",
      ])
      is Ok(_) else {
      fail("expected valid prefixes accepted")
    }
  })
}

///|
async test "the scope root is canonical so resolved comparisons match" {
  // macOS /tmp is a symlink to /private/tmp: creating the scope from the
  // un-resolved spelling must still admit realpath'd targets.
  @vfs.with_tmpdir(prefix="write-scope-canon-", root => {
    @vfs.FileSystem({ "src/a.mbt": "a" }).write_to(root)
    let scope = scope_of(root)
    assert_true(scope.root() == @fs.realpath(root))
    assert_admits(scope, "\{scope.root()}/src/a.mbt")
  })
}

///|
#cfg(not(platform="windows"))
async test "a POSIX backslash is a filename byte, not a separator" {
  @vfs.with_tmpdir(prefix="write-scope-backslash-", root => {
    @vfs.FileSystem({ "src/a.mbt": "a" }).write_to(root)
    let scope = scope_of(root, allowed_paths=["src"])
    // A single component literally named `src\outside` is not under `src`;
    // the surrounding path machinery would treat the backslash as a
    // separator and smuggle it into the allowed prefix, so it fails closed.
    assert_denies(scope, "\{root}/src\\outside", because="backslash")
    // And a backslash-bearing prefix could never authorize anything here,
    // so create rejects it (on Windows it is a separator and normalizes).
    guard @write_scope.WriteScope::create(root~, allowed_paths=[
        "src\\generated",
      ])
      is Err(_) else {
      fail("expected a backslash prefix rejected on POSIX")
    }
  })
}
