// One file location for Desktop language operations. The frontend supplies
// the exact editor root and a path relative to it; the host keeps both the
// lexical spelling used by Viewer resources and the physical spelling used
// to contain symlinks before invoking MoonBit tooling.

///|
priv struct LanguagePath {
  lexical_root : @pathx.Absolute
  physical_root : @pathx.Absolute
  physical_relative : @pathx.Relative
}

///|
/// Resolve one explicit editor root and relative file path. `root` need not be
/// an attached OpenSeek workspace: a Codex cwd or any linked worktree is
/// already the complete root. The physical containment check still rejects a
/// relative path whose symlink target leaves that root.
async fn LanguagePath::resolve(root : String, path : String) -> LanguagePath {
  guard @pathx.Absolute::from_uri_path(root) is Some(lexical_root) else {
    raise PayloadError("root must be absolute")
  }
  guard @pathx.Path(path).to_absolute() is None else {
    raise PayloadError("path must be relative to root")
  }
  let lexical_root = lexical_root.normalize()
  let relative = @pathx.Relative(path).normalize()
  guard !relative.is_root() else {
    raise PayloadError("path must name a file below root")
  }
  let lexical_file = lexical_root.join(relative).normalize()
  guard lexical_root.contains(lexical_file) else {
    raise HostError("path is outside root")
  }
  let physical_root_text = @fs.realpath(lexical_root.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => raise HostError("root is unavailable")
  }
  let physical_file_text = @fs.realpath(lexical_file.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => raise HostError("path is unavailable")
  }
  guard @pathx.Path(physical_root_text).to_absolute() is Some(physical_root) &&
    @pathx.Path(physical_file_text).to_absolute() is Some(physical_file) else {
    raise HostError("root or path is not a host absolute path")
  }
  guard physical_file.relative_to(root=physical_root) is Some(physical_relative) &&
    !physical_relative.is_root() else {
    raise HostError("path is outside root")
  }
  { lexical_root, physical_root, physical_relative }
}

///|
async test "language paths accept explicit roots and reject escapes" {
  let root = @fs.tmpdir(prefix="openseek-language-root-")
  let outside = @fs.tmpdir(prefix="openseek-language-outside-")
  try {
    @fs.mkdir("\{root}/src", recursive=true)
    @fs.write_file(
      "\{root}/src/main.mbt",
      "fn main {}",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{outside}/secret.mbt",
      "fn secret {}",
      create_mode=CreateOrTruncate,
    )
    @fs.symlink(target="\{outside}/secret.mbt", "\{root}/src/link.mbt")
    let resolved = LanguagePath::resolve(root, "src/main.mbt")
    let traversal_rejected = try {
      ignore(LanguagePath::resolve(root, "../outside.mbt"))
      false
    } catch {
      _ => true
    } noraise {
      rejected => rejected
    }
    let symlink_rejected = try {
      ignore(LanguagePath::resolve(root, "src/link.mbt"))
      false
    } catch {
      _ => true
    } noraise {
      rejected => rejected
    }
    @fs.rmdir(root, recursive=true)
    @fs.rmdir(outside, recursive=true)
    assert_eq(resolved.physical_relative, Relative("src/main.mbt"))
    assert_true(traversal_rejected)
    assert_true(symlink_rejected)
  } catch {
    error => {
      @fs.rmdir(root, recursive=true) catch {
        _ => ()
      }
      @fs.rmdir(outside, recursive=true) catch {
        _ => ()
      }
      raise error
    }
  } noraise {
    _ => ()
  }
}
