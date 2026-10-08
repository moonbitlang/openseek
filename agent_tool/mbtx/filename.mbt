///|
/// The embedded source a `@builtin/` filename selects, or `None` for an
/// workspace or session filename. Bundled workflows are compiled into the binary
/// (see `generated_bundled_workflows.mbt`), so they run the same whether or not
/// an installation's `share/workflow/` sits beside the executable.
///
/// Raises for an unknown @ namespace or an unknown bundled name, so a typo never
/// falls through to a workspace file.
fn bundled_source(filename : String) -> String? raise {
  guard filename.has_prefix("@") && !@tool_path.is_session(filename) else {
    return None
  }
  guard filename.strip_prefix("@builtin/") is Some(name) else {
    fail(
      "unknown script namespace in \{filename}. Supported namespaces are @builtin/ and @session/. Use ./\{filename} for a literal workspace path",
    )
  }
  guard bundled_workflow(name) is Some(source) else {
    fail("no bundled workflow named \{filename}.\{bundled_workflow_hint}")
  }
  Some(source)
}

///|
let bundled_workflow_hint : String = " Bundled workflows: @builtin/read.mbtx, @builtin/rg.mbtx (ripgrep search), @builtin/check.mbtx, @builtin/test.mbtx, @builtin/check-test.mbtx, @builtin/info-fmt.mbtx, @builtin/check-json.mbtx, @builtin/ci-watch.mbtx (GitHub CI status), @builtin/fix-deprecations.mbtx (ptc=true; one guarded edit per deprecation site). Agent workflows (subrun=true): @builtin/review.mbtx (independent worktree audit; criteria in args), @builtin/change-review.mbtx, @builtin/repo-map.mbtx. Ordinary filenames select workspace files."

///|
/// Resolve a saved workspace or session script; bundled scripts are read-only.
async fn resolve_filename(
  workspace_root : String,
  filename : String,
  session_dir? : String,
) -> String {
  guard !filename.has_prefix("@") || @tool_path.is_session(filename) else {
    fail(
      "\{filename} is a namespaced script and is read-only. Use ./\{filename} for a literal workspace path",
    )
  }
  @tool_path.resolve(workspace_root, filename, session_dir?)
}

///|
async test "only the builtin namespace selects bundled workflows" {
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
      // The generator normalizes CRLF, so a CRLF checkout compares equal.
      Some(
        @fs.read_file("share/workflow/\{name}")
        .text()
        .replace_all(old="\r\n", new="\n"),
      ),
      msg="stale embedded copy of \{name}; run moon check to regenerate",
    )
    assert_true(
      bundled_workflow_hint.contains("@builtin/\{name}"),
      msg="\{name} missing from the bundled workflow hint",
    )
  }
}

///|
/// Resolve the bundled reader's path[:start[:end]] selectors in the host.
async fn resolve_read_args(
  workspace_root : String,
  args : Array[String],
  session_dir? : String,
) -> Array[String] {
  [
    for arg in args => {
      if @tool_path.is_session(arg) {
        match arg.split_once(":") {
          Some((path, lines)) => {
            guard lines
              .split(":")
              .all(part => !part.is_empty() && part.all(c => c.is_ascii_digit())) else {
              fail("invalid @session/ read selector: \{arg}")
            }
            "\{@tool_path.resolve(workspace_root, path.to_owned(), session_dir?)}:\{lines}"
          }
          None => @tool_path.resolve(workspace_root, arg, session_dir?)
        }
      } else {
        arg
      }
    }
  ]
}
