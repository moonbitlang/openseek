// Host-owned package dependency graphs. Unlike source-only editor renderers,
// this view must ask the selected Moon toolchain to resolve the module from
// the concrete checkout that owns the opened `moon.mod`.

///|
/// The argv passed directly to Moon. Keeping it as an array prevents a path or
/// manifest value from ever becoming shell syntax.
fn moon_package_graph_args() -> Array[String] {
  ["tree", "--package", "--json"]
}

///|
/// Resolve the opened manifest through the same ownership and physical
/// containment boundary used by language operations, then return its parent
/// directory as Moon's cwd.
async fn moon_package_graph_cwd(
  payload : MoonPackageGraphPayload,
) -> @pathx.Absolute {
  let location = LanguagePath::resolve(
    payload.session,
    payload.root,
    payload.path,
  )
  let manifest = location.physical_root.join(location.physical_relative)
  guard manifest.to_path().basename() == "moon.mod" else {
    raise PayloadError("path must name moon.mod")
  }
  let kind = @fs.kind(manifest.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => raise HostError("moon.mod is unavailable")
  }
  guard kind is Regular else {
    raise PayloadError("path must name a moon.mod file")
  }
  guard manifest.to_path().dirname().to_absolute() is Some(cwd) else {
    raise HostError("moon.mod parent is not an absolute path")
  }
  cwd.normalize()
}

///|
/// Extract Moon's useful message from a failed structured result. Current
/// output carries an error string; accepting `{message}` as well preserves the
/// diagnostic if Moon evolves the field into a structured error.
fn moon_tree_error_message(error : Json) -> String? {
  let message = match error {
    String(message) => message
    Object(fields) =>
      match fields.get("message") {
        Some(String(message)) => message
        _ => return None
      }
    _ => return None
  }
  let message = message.trim().to_owned()
  if message.is_empty() {
    None
  } else {
    Some(message)
  }
}

///|
/// Recognize Moon's JSON failure envelope independently of the process exit
/// code. This second check is deliberate: a tool that accidentally exits zero
/// with `status: "failed"` still must not feed that JSON to the UML renderer.
fn moon_tree_failure_message(output : String) -> String? {
  let json = @json.parse(output.trim()) catch { _ => return None }
  guard json is Object(fields) &&
    fields.get("status") is Some(String(status)) &&
    status != "success" else {
    return None
  }
  if fields.get("error") is Some(error) &&
    moon_tree_error_message(error) is Some(message) {
    return Some(message)
  }
  Some("moon tree reported status “\{status}”")
}

///|
/// Validate only the stable package-graph envelope before preserving Moon's
/// source verbatim for `uml.render_package_dep_svg`. A non-null `error` or a
/// non-success status is never a graph, even if it happens to contain arrays
/// named `nodes` and `edges`.
fn is_moon_package_graph_source(source : String) -> Bool {
  let json = @json.parse(source.trim()) catch { _ => return false }
  guard json is Object(fields) &&
    fields.get("nodes") is Some(Array(_)) &&
    fields.get("edges") is Some(Array(_)) else {
    return false
  }
  let status_ok = match fields.get("status") {
    None | Some(String("success")) => true
    _ => false
  }
  let error_clear = match fields.get("error") {
    None | Some(Null) => true
    _ => false
  }
  status_ok && error_clear
}

///|
/// Classify one completed Moon process without losing its best diagnostic.
/// Nonzero exits prefer the structured stdout error, then stderr, raw stdout,
/// and finally the exit code. Zero exits still require a successful graph
/// envelope so failed or malformed JSON cannot masquerade as source.
fn moon_package_graph_process_reply(
  code : Int,
  stdout : String,
  stderr : String,
) -> MoonPackageGraphReply {
  let stdout_detail = stdout.trim().to_owned()
  let stderr_detail = stderr.trim().to_owned()
  if code != 0 {
    if moon_tree_failure_message(stdout_detail) is Some(message) {
      return PackageGraphError(message~)
    }
    if !stderr_detail.is_empty() {
      return PackageGraphError(message=stderr_detail)
    }
    if !stdout_detail.is_empty() {
      return PackageGraphError(message=stdout_detail)
    }
    return PackageGraphError(
      message="moon tree --package --json exited with code \{code}",
    )
  }
  if moon_tree_failure_message(stdout_detail) is Some(message) {
    return PackageGraphError(message~)
  }
  if stdout_detail.is_empty() {
    return PackageGraphError(
      message="moon tree --package --json returned empty output",
    )
  }
  guard is_moon_package_graph_source(stdout_detail) else {
    return PackageGraphError(
      message="moon tree --package --json returned invalid package graph JSON",
    )
  }
  PackageGraphSource(source=stdout)
}

///|
/// Run the package graph query in the opened manifest's directory. Toolchain
/// resolution, spawn, text decoding, and timeout failures are reported as an
/// explicit reply variant so the editor can retain and display the source
/// view while explaining why the graph is unavailable.
async fn moon_package_graph_op(
  state : MoonCliState,
  payload : MoonPackageGraphPayload,
) -> MoonPackageGraphReply {
  let cwd = moon_package_graph_cwd(payload)
  guard state.run_moon(moon_package_graph_args(), cwd)
    is Some((code, stdout, stderr)) else {
    return PackageGraphError(message="could not run moon tree --package --json")
  }
  moon_package_graph_process_reply(code, stdout, stderr)
}

///|
test "package graph invokes Moon with the exact argv" {
  assert_eq(moon_package_graph_args(), ["tree", "--package", "--json"])
}

///|
test "package graph accepts only successful graph JSON" {
  let graph = "{\"version\":2,\"status\":\"success\",\"error\":null,\"nodes\":[],\"edges\":[]}"
  assert_eq(
    moon_package_graph_process_reply(0, graph, "ignored stderr"),
    PackageGraphSource(source=graph),
  )
  assert_eq(
    moon_package_graph_process_reply(
      0, "{\"status\":\"failed\",\"error\":\"manifest failed\",\"nodes\":[],\"edges\":[]}",
      "",
    ),
    PackageGraphError(message="manifest failed"),
  )
  assert_eq(
    moon_package_graph_process_reply(0, "{\"nodes\":[]}", ""),
    PackageGraphError(
      message="moon tree --package --json returned invalid package graph JSON",
    ),
  )
  assert_eq(
    moon_package_graph_process_reply(0, "  \n", ""),
    PackageGraphError(
      message="moon tree --package --json returned empty output",
    ),
  )
}

///|
test "package graph process errors retain Moon's best diagnostic" {
  assert_eq(
    moon_package_graph_process_reply(
      2, "{\"status\":\"failed\",\"error\":{\"message\":\"bad dependency\"}}", "less useful stderr",
    ),
    PackageGraphError(message="bad dependency"),
  )
  assert_eq(
    moon_package_graph_process_reply(2, "unstructured stdout", " stderr wins "),
    PackageGraphError(message="stderr wins"),
  )
  assert_eq(
    moon_package_graph_process_reply(2, " stdout fallback ", ""),
    PackageGraphError(message="stdout fallback"),
  )
  assert_eq(
    moon_package_graph_process_reply(2, "", ""),
    PackageGraphError(message="moon tree --package --json exited with code 2"),
  )
}

///|
async test "package graph cwd is the authorized moon.mod parent" {
  let root = @fs.tmpdir(prefix="openseek-package-graph-root-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  defer (@work_dir.revoke_host_workspace("package-graph-test") catch {
    _ => ()
  })
  @fs.mkdir("\{root}/nested/module", recursive=true)
  @fs.write_file(
    "\{root}/nested/module/moon.mod",
    "{}",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{root}/nested/module/README.md",
    "not a manifest",
    create_mode=CreateOrTruncate,
  )
  guard @pathx.Path(root).to_absolute() is Some(root_absolute) &&
    root_absolute.to_uri_path() is Some(root_resource) else {
    fail("test root could not be represented as a frontend resource")
  }
  @work_dir.authorize_host_workspace("package-graph-test", root)
  let cwd = moon_package_graph_cwd({
    session: "package-graph-test",
    root: root_resource,
    path: "nested/module/moon.mod",
  })
  let expected_text = @fs.realpath("\{root}/nested/module")
  guard @pathx.Path(expected_text).to_absolute() is Some(expected) else {
    fail("test module root is not absolute")
  }
  assert_eq(cwd, expected.normalize())
  let wrong_name_rejected = try {
    ignore(
      moon_package_graph_cwd({
        session: "package-graph-test",
        root: root_resource,
        path: "nested/module/README.md",
      }),
    )
    false
  } catch {
    _ => true
  } noraise {
    rejected => rejected
  }
  assert_true(wrong_name_rejected)
}
