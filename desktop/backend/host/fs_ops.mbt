// Host-local filesystem ops backing the editor side-panel. Each request names
// its absolute target directly; none of these operations consult the engine
// or derive a path from a conversation id.

///|
/// A selection artifact is intentionally generous enough for a whole search
/// page, while still preventing one browser request from creating an
/// unbounded hidden workspace file. Refuse rather than truncate: a partial
/// selection must never look authoritative to an agent.
const MaxSemanticSelectionArtifactUnits : Int32 = 8_000_000

///|
fn semantic_selection_artifact_id_is_safe(id : String) -> Bool {
  !id.is_empty() &&
  !id.contains("/") &&
  !id.contains("\\") &&
  !id.contains("..") &&
  !id.contains(":")
}

///|
async fn materialize_semantic_selection_op(
  payload : MaterializeSemanticSelectionPayload,
) -> MaterializeSemanticSelectionReply {
  guard semantic_selection_artifact_id_is_safe(payload.artifact_id) else {
    raise HostError("invalid semantic selection artifact id")
  }
  let mut source_units = 0
  let files : Set[String] = Set([])
  for match_ in payload.matches {
    source_units += match_.matched_source.length() + match_.file.length()
    files.add(match_.file)
  }
  guard source_units <= MaxSemanticSelectionArtifactUnits else {
    raise HostError("semantic selection is too large to materialize")
  }
  let root = WirePath::parse(payload.root).absolute
  let relative_dir = ".openseek/agent-context/semantic-search"
  let dir = root.join(relative_dir)
  @fs.mkdir(dir.to_string(), recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    // `recursive=true` only creates missing parents; an existing artifact
    // directory is the normal steady state. A file squatting on this path
    // surfaces as the write below failing.
    @os_error.OSError(_) as error if error.is_EEXIST() => ()
    error =>
      raise HostError("could not create semantic selection directory: \{error}")
  }
  let header : Json = {
    "version": Json(1),
    "kind": Json("semantic-search-selection"),
    "root": Json(payload.root),
    "patterns": Json(payload.patterns),
    "include": Json(payload.include_glob),
    "exclude": Json(payload.exclude_glob),
    "selected_matches": Json(payload.matches.length()),
    "selected_files": Json(files.length()),
    "instructions": Json(
      "This is an immutable semantic-search selection snapshot. Filter its JSONL match records before reading broadly; the working-tree files are the current source of truth.",
    ),
  }
  let lines : Array[String] = [header.stringify()]
  for match_ in payload.matches {
    let record : Json = {
      "kind": Json("match"),
      "rule_id": Json(match_.rule_id),
      "description": Json(match_.description),
      "file": Json(match_.file),
      "start_line": Json(match_.start_line),
      "start_column": Json(match_.start_column),
      "end_line": Json(match_.end_line),
      "end_column": Json(match_.end_column),
      "matched_source": Json(match_.matched_source),
    }
    lines.push(record.stringify())
  }
  let content = lines.join("\n") + "\n"
  // The frontend's id is unique during one page lifetime, but deliberately
  // is not a persistent identity. A restart can therefore ask for the same
  // id while an earlier Agent still has the old snapshot open. Never replace
  // an existing artifact: choose a suffixed path and create a new immutable
  // snapshot instead. CreateNew arbitrates the final path itself, so a second
  // window cannot win the existence-check/write race and overwrite a reader's
  // snapshot.
  for index = 0; ; index = index + 1 {
    let suffix = if index == 0 { "" } else { "-\{index}" }
    let relative_path = "\{relative_dir}/\{payload.artifact_id}\{suffix}.jsonl"
    let target = root.join(relative_path)
    @fs.write_file(target.to_string(), content, create_mode=CreateNew) catch {
      error if @async.is_being_cancelled() => raise error
      @os_error.OSError(_) as error if error.is_EEXIST() => continue
      error =>
        // Do not remove the path on an unknown write error: another process
        // may own it, and preserving an old snapshot is more important than
        // cleaning an unreferenced partial file. A later retry will choose a
        // suffix if this path remains present.
        raise HostError("could not write semantic selection: \{error}")
    }
    return {
      path: relative_path,
      match_count: payload.matches.length(),
      file_count: files.length(),
    }
  }
}

///|
async test "semantic selections materialize as bounded JSONL below the checkout" {
  let dir = @fs.tmpdir(prefix="openseek-semantic-selection-")
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(@fs.realpath(dir))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  let reply = materialize_semantic_selection_op({
    root,
    artifact_id: "semantic-search-8-3",
    patterns: ["inspect($(x:arg))"],
    include_glob: "src/**",
    exclude_glob: "generated/**",
    matches: [
      {
        rule_id: "inspect",
        description: Some("inspection"),
        file: "src/main.mbt",
        start_line: 4,
        start_column: 1,
        end_line: 4,
        end_column: 12,
        matched_source: "inspect(value)",
      },
    ],
  })
  assert_eq(
    reply.path,
    ".openseek/agent-context/semantic-search/semantic-search-8-3.jsonl",
  )
  assert_eq(reply.match_count, 1)
  assert_eq(reply.file_count, 1)
  let written = @fs.read_file(@pathx.Path(dir).join(reply.path).to_string()).text()
  assert_true(written.contains("\"kind\":\"semantic-search-selection\""))
  assert_true(written.contains("inspect(value)"))
}

///|
async test "semantic selection accepts an existing artifact directory" {
  let dir = @fs.tmpdir(prefix="openseek-semantic-selection-existing-")
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(@fs.realpath(dir))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  let artifact_dir = @pathx.Path(dir).join(
    ".openseek/agent-context/semantic-search",
  )
  @fs.mkdir(artifact_dir.to_string(), recursive=true)
  @fs.write_file(
    artifact_dir.join("previous.jsonl").to_string(),
    "old snapshot\n",
    create_mode=CreateNew,
  )
  let reply = materialize_semantic_selection_op({
    root,
    artifact_id: "semantic-search-existing",
    patterns: ["inspect($(x:arg))"],
    include_glob: "",
    exclude_glob: "",
    matches: [],
  })
  assert_true(reply.path.contains("semantic-search-existing"))
  assert_true(@fs.exists(@pathx.Path(dir).join(reply.path).to_string()))
  assert_eq(
    @fs.read_file(artifact_dir.join("previous.jsonl").to_string()).text(),
    "old snapshot\n",
  )
}

///|
async test "semantic selection materialization rejects path-shaped ids" {
  let dir = @fs.tmpdir(prefix="openseek-semantic-selection-invalid-")
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(@fs.realpath(dir))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  let mut rejected = false
  ignore(
    materialize_semantic_selection_op({
      root,
      artifact_id: "../escape",
      patterns: [],
      include_glob: "",
      exclude_glob: "",
      matches: [],
    }),
  ) catch {
    HostError(_) => rejected = true
    error => raise error
  }
  assert_true(rejected)
}

///|
async test "semantic selection materialization never replaces an old snapshot" {
  let dir = @fs.tmpdir(prefix="openseek-semantic-selection-retry-")
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(@fs.realpath(dir))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  let payload : MaterializeSemanticSelectionPayload = {
    root,
    artifact_id: "semantic-search-1-1",
    patterns: ["inspect($(x:arg))"],
    include_glob: "",
    exclude_glob: "",
    matches: [
      {
        rule_id: "inspect",
        description: Some("first"),
        file: "src/first.mbt",
        start_line: 1,
        start_column: 1,
        end_line: 1,
        end_column: 12,
        matched_source: "inspect(first)",
      },
    ],
  }
  let first = materialize_semantic_selection_op(payload)
  let first_path = @pathx.Path(dir).join(first.path).to_string()
  let first_content = @fs.read_file(first_path).text()
  let second = materialize_semantic_selection_op({
    ..payload,
    matches: [
      {
        ..payload.matches[0],
        description: Some("second"),
        matched_source: "inspect(second)",
      },
    ],
  })
  assert_true(second.path != first.path)
  assert_eq(@fs.read_file(first_path).text(), first_content)
  let second_path = @pathx.Path(dir).join(second.path).to_string()
  assert_true(@fs.read_file(second_path).text().contains("inspect(second)"))
}

///|
async fn read_directory_op(payload : ReadDirPayload) -> ReadDirReply {
  let dir = WirePath::parse(payload.path).absolute
  // A requested root can be created lazily by the engine. Treat a missing
  // directory as empty so the panel can keep its ordinary loading behavior.
  if !@fs.exists(dir.to_string()) {
    return { entries: [], }
  }
  let names = @fs.readdir(dir.to_string()) catch {
    error => raise HostError("failed to list directory: \{error}")
  }
  // Plain lexicographic order, not `readdir(sort=true)`: that sorts with
  // String's `Compare`, which is shortlex — length before content — and
  // reads wrong in a file listing ("z.mbt" before "main.mbt").
  names.sort_by((a, b) => a.lexical_compare(b))
  let entries : Array[DirEntry] = []
  for name in names {
    let child = dir.join((name : @pathx.Relative)).to_string()
    let is_dir = (@fs.kind(child) catch { _ => Unknown }) is Directory
    entries.push({ name, is_dir, })
  }
  // Directories first, then files; the sort above already orders each
  // group by name, and the partition preserves that order.
  let dirs = entries.filter(entry => entry.is_dir)
  let files = entries.filter(entry => !entry.is_dir)
  { entries: dirs + files, }
}

///|
async fn read_file_op(payload : ReadFilePayload) -> ReadFileReply {
  let file = if payload.root is Some(root) {
    WirePath::parse(root).resolve(payload.path)
  } else {
    WirePath::parse(payload.path).absolute
  }
  let native = file.to_string()
  let source = @fs.open(native, mode=ReadOnly) catch {
    error => raise HostError("failed to read file: \{error}")
  }
  defer source.close()
  let office_media_type = match office_media_type(file.to_string()) {
    Some(media_type) => Some(media_type)
    None => {
      // Retain signature-based PDF routing even for a file with no .pdf
      // suffix. Only the small header is read before the allocation limit.
      let size = source.size()
      let header = source.read_exactly_at(
        if size < 12 {
          size.to_int()
        } else {
          12
        },
        position=0,
      )
      if @filekind.classify(header) is Pdf {
        Some("application/pdf")
      } else {
        None
      }
    }
  }
  // Check the size before reading the body so a large build artifact produces
  // the notice without a host-sized allocation.
  let size_limit = match office_media_type {
    Some(_) => @openpath.MaxOfficeFileBytes
    None => @openpath.MaxEditorFileBytes
  }
  if source.size() > size_limit.to_int64() {
    return Oversized
  }
  let data = source.read_all() catch {
    error => raise HostError("failed to read file: \{error}")
  }
  // The change-detection baseline, from the same open handle as the content
  // so the two cannot disagree about which version of the file was read.
  let sig = file_stamp(source.mtime(), source.ctime(), source.size()) catch {
    error => raise HostError("failed to read file: \{error}")
  }
  // Classify the bytes already read from this handle. The shared policy trusts
  // raster signatures rather than extensions and returns decoded text without
  // making callers perform a second UTF-8 pass.
  let bytes = data.binary()
  match office_media_type {
    Some(media_type) =>
      BinaryContent(data_base64=@base64.encode(bytes), media_type~, sig~)
    None =>
      match @filekind.classify(bytes) {
        Image(media_type~) =>
          BinaryContent(data_base64=@base64.encode(bytes), media_type~, sig~)
        Utf8Text(content) => {
          let absolute = file.resource_path()
          Content(content~, absolute~, sig~)
        }
        Pdf | UnknownBinary => Binary
      }
  }
}

///|
/// Office packages are ZIP-based and intentionally classified as generic
/// binary by the shared text/image policy. The extension is the host's only
/// format signal here; the viewer performs the structural parse after the
/// bytes arrive in the JS frontend.
fn office_media_type(path : String) -> String? {
  let lower = path.to_lower()
  if lower.has_suffix(".docx") {
    Some(
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    )
  } else if lower.has_suffix(".xlsx") {
    Some("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  } else if lower.has_suffix(".pdf") {
    Some("application/pdf")
  } else {
    None
  }
}

///|
async test "PDF reads preserve bytes and use the document limit with or without an extension" {
  let dir = @fs.tmpdir(prefix="openseek-read-pdf-")
  defer @fs.rmdir(dir, recursive=true)
  let bytes = @utf8.encode(
    "%PDF-1.7\n" + "x".repeat(@openpath.MaxEditorFileBytes + 1),
  )
  for name in ["report.PDF", "report-without-extension"] {
    let file = "\{dir}/\{name}"
    @fs.write_file(file, bytes, create_mode=CreateOrTruncate)
    let absolute = @pathx.Path(@fs.realpath(file))
      .to_absolute()
      .unwrap()
      .to_uri_path()
      .unwrap()
    match read_file_op({ path: absolute, root: None, }) {
      BinaryContent(data_base64~, media_type~, sig~) => {
        assert_eq(media_type, "application/pdf")
        assert_eq(@base64.decode(data_base64), bytes)
        assert_true(!sig.is_empty())
      }
      _ => fail("PDF reads must retain the original binary payload")
    }
    @fs.write_file(
      file,
      "%PDF-1.7\n" + "x".repeat(@openpath.MaxOfficeFileBytes),
      create_mode=TruncateExisting,
    )
    assert_eq(read_file_op({ path: absolute, root: None, }), Oversized)
  }
}

///|
async test "binary file reads expose only recognized raster signatures" {
  let dir = "_build/host-read-file-image-test"
  if @fs.exists(dir) {
    @fs.rmdir(dir, recursive=true)
  }
  @fs.mkdir(dir, recursive=true)
  let image = "\{dir}/image.png"
  @fs.write_file(image, b"\x89PNG\r\n\x1a\nsmall", create_mode=CreateOrTruncate)
  let absolute = @pathx.Path(@fs.realpath(image))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  assert_true(
    read_file_op({ path: absolute, root: None, })
    is BinaryContent(
      data_base64="iVBORw0KGgpzbWFsbA==",
      media_type="image/png",
      sig=_
    ),
  )
  let root = @pathx.Path(@fs.realpath(dir))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  assert_true(
    read_file_op({ path: "image.png", root: Some(root), })
    is BinaryContent(
      data_base64="iVBORw0KGgpzbWFsbA==",
      media_type="image/png",
      sig=_
    ),
  )
  let disguised = "\{dir}/not-an-image.png"
  @fs.write_file(disguised, b"\xffnot an image", create_mode=CreateOrTruncate)
  let disguised_absolute = @pathx.Path(@fs.realpath(disguised))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  assert_eq(read_file_op({ path: disguised_absolute, root: None, }), Binary)
  @fs.rmdir(dir, recursive=true)
}

///|
async test "Office file reads return original package bytes and media type" {
  let dir = "_build/host-read-file-office-test"
  if @fs.exists(dir) {
    @fs.rmdir(dir, recursive=true)
  }
  @fs.mkdir(dir, recursive=true)
  let xlsx = "\{dir}/example.xlsx"
  let package_bytes = b"PK\x03\x04office fixture"
  @fs.write_file(xlsx, package_bytes, create_mode=CreateOrTruncate)
  let absolute = @pathx.Path(@fs.realpath(xlsx))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  match read_file_op({ path: absolute, root: None, }) {
    BinaryContent(data_base64~, media_type~, sig~) => {
      assert_eq(
        media_type, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      )
      assert_eq(data_base64, @base64.encode(package_bytes))
      assert_true(!sig.is_empty())
    }
    _ => fail("an .xlsx read must preserve its original package bytes")
  }
  @fs.rmdir(dir, recursive=true)
}

///|
/// The filesystem signatures of the open tabs' files (see `StatFilesPayload`).
/// Each path answers for itself: one file the host cannot inspect neither
/// fails the whole reply nor reads as deleted — it is reported as exactly
/// that.
async fn stat_files_op(payload : StatFilesPayload) -> StatFilesReply {
  let stats : Array[FileStat] = []
  for path in payload.paths {
    let file = WirePath::parse(path).absolute
    stats.push({ path, signature: file_signature(file.to_string()), })
  }
  { stats, }
}

///|
/// Include mtime, ctime and size so timestamp-preserving replacements and
/// writes are observable to every viewer. `Missing` is the path
/// no longer resolving to a file — deleted, or an ancestor that stopped being
/// a directory — by far the common failure. Every other stat error is
/// `Failed` with the OS message: the panel then re-reads the file so the
/// read's own error (or the content) replaces the guess, and the log keeps
/// the stat's.
async fn file_signature(absolute : String) -> FileSignature {
  let sig = try {
    // file_size uses lstat in the async library. Resolve first so all three
    // attributes describe the same target as read_file's open handle.
    let target = @fs.realpath(absolute)
    file_stamp(@fs.mtime(target), @fs.ctime(target), @fs.file_size(target))
  } catch {
    @os_error.OSError(_) as error if error.is_ENOENT() || error.is_ENOTDIR() =>
      return Missing
    error => {
      @xlog.warn(category="filesystem") <?
        { "event": "stat_failed", "path": absolute, "error": "\{error}" }
      return Failed("\{error}")
    }
  }
  Present(sig)
}

///|
fn file_stamp(
  mtime : (Int64, Int32),
  ctime : (Int64, Int32),
  size : Int64,
) -> String {
  "\{mtime.0}:\{mtime.1}:\{ctime.0}:\{ctime.1}:\{size}"
}
