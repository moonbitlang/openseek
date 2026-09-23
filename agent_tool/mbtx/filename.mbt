///|
/// The embedded source a `@builtin/` filename selects, or `None` for an
/// ordinary workspace filename. Bundled workflows are compiled into the binary
/// (see `generated_bundled_workflows.mbt`), so they run the same whether or not
/// an installation's `share/workflow/` sits beside the executable.
///
/// Raises for an unknown @ namespace or an unknown bundled name, so a typo never
/// falls through to a workspace file.
fn bundled_source(filename : String) -> String? raise {
  guard filename.has_prefix("@") else { return None }
  guard filename.strip_prefix("@builtin/") is Some(name) else {
    fail(
      "unknown script namespace in \{filename}. Only @builtin/ is supported. Use ./\{filename} for a literal workspace path",
    )
  }
  guard bundled_workflow(name) is Some(source) else {
    fail("no bundled workflow named \{filename}.\{bundled_workflow_hint}")
  }
  Some(source)
}

///|
let bundled_workflow_hint : String = " Bundled workflows: @builtin/read.mbtx, @builtin/check.mbtx, @builtin/test.mbtx, @builtin/check-test.mbtx, @builtin/info-fmt.mbtx, @builtin/check-json.mbtx, @builtin/ci-watch.mbtx (GitHub CI status), @builtin/fix-deprecations.mbtx (ptc=true; one guarded edit per deprecation site). Agent workflows (subrun=true): @builtin/review.mbtx (independent worktree audit; criteria in args), @builtin/change-review.mbtx, @builtin/repo-map.mbtx. Ordinary filenames select workspace files."

///|
/// Resolve a workspace script path. Namespaced filenames never name a
/// workspace file; `bundled_source` handles them.
fn resolve_filename(workspace_root : String, filename : String) -> String raise {
  guard !filename.has_prefix("@") else {
    fail(
      "\{filename} is a namespaced script and is read-only. Use ./\{filename} for a literal workspace path",
    )
  }
  @workspace_path.resolve(workspace_root, filename)
}

///|
test "only the builtin namespace selects bundled workflows" {
  assert_true(bundled_source("@builtin/check.mbtx") is Some(_))
  for name in ["check.mbtx", "./@builtin/check.mbtx", "scripts/check.mbtx"] {
    assert_true(bundled_source(name) is None)
  }
  for
    name in [
      "@skill/check.mbtx", "@builtin/", "@builtin/../check.mbtx", "@builtin//check.mbtx",
      "@builtin/a\\check.mbtx", "@builtin/missing.mbtx",
    ] {
    try bundled_source(name) catch {
      _ => ()
    } noraise {
      _ => fail("invalid bundled name accepted: \{name}")
    }
  }
  assert_eq(resolve_filename("/project", "check.mbtx"), "/project/check.mbtx")
  assert_eq(
    resolve_filename("/project", "/other/check.mbtx"),
    "/other/check.mbtx",
  )
  assert_eq(
    resolve_filename("/project", "./@builtin/check.mbtx"),
    "/project/@builtin/check.mbtx",
  )
  try resolve_filename("/project", "@builtin/check.mbtx") catch {
    _ => ()
  } noraise {
    _ => fail("a namespaced filename resolved to a workspace path")
  }
}

///|
async test "every share/workflow script is embedded verbatim and named in the hint" {
  let names = @fs.readdir("share/workflow").filter(name => {
    name.has_suffix(".mbtx")
  })
  assert_true(names.length() > 0)
  for name in names {
    assert_eq(
      bundled_workflow(name),
      Some(@fs.read_file("share/workflow/\{name}").text()),
      msg="stale embedded copy of \{name}; run moon check to regenerate",
    )
    assert_true(
      bundled_workflow_hint.contains("@builtin/\{name}"),
      msg="\{name} missing from the bundled workflow hint",
    )
  }
}
