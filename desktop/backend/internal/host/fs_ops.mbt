// Host-local filesystem ops backing the editor side-panel. Each request names
// its absolute target directly; none of these operations consult the engine
// or derive a path from a conversation id.

///|
/// A selection artifact is intentionally generous enough for a whole search
/// page, while still preventing one browser request from creating an
/// unbounded hidden workspace file. Refuse rather than truncate: a partial
/// selection must never look authoritative to an agent.
const MaxSemanticSelectionArtifactUnits : Int = 8_000_000

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
  let files : Map[String, Bool] = Map([])
  for match_ in payload.matches {
    source_units += match_.matched_source.length() + match_.file.length()
    files[match_.file] = true
  }
  guard source_units <= MaxSemanticSelectionArtifactUnits else {
    raise HostError("semantic selection is too large to materialize")
  }
  let root = WirePath::parse(payload.root).absolute
  let relative_dir = ".openseek/agent-context/semantic-search"
  let dir = root.join(relative_dir)
  @fs.mkdir(dir.to_string(), recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    @os_error.OSError(_) as error if error.is_EEXIST() => {
      // `async/fs.mkdir` only handles missing parents when recursive=true;
      // Windows reports an existing leaf as ERROR_ALREADY_EXISTS. Treat that
      // normal steady state as success, but never mistake a file at this path
      // for the artifact directory.
      let kind = @fs.kind(dir.to_string()) catch {
        error if @async.is_being_cancelled() => raise error
        error =>
          raise HostError(
            "could not inspect semantic selection directory: \{error}",
          )
      }
      guard kind is Directory else {
        raise HostError("semantic selection path is not a directory")
      }
    }
    error =>
      raise HostError("could not create semantic selection directory: \{error}")
  }
  let header : Json = {
    "version": Json(1),
    "kind": "semantic-search-selection".to_json(),
    "root": payload.root.to_json(),
    "patterns": payload.patterns.to_json(),
    "include": payload.include_glob.to_json(),
    "exclude": payload.exclude_glob.to_json(),
    "selected_matches": payload.matches.length().to_json(),
    "selected_files": files.length().to_json(),
    "instructions": "This is an immutable semantic-search selection snapshot. Filter its JSONL match records before reading broadly; the working-tree files are the current source of truth.".to_json(),
  }
  let lines : Array[String] = [header.stringify()]
  for match_ in payload.matches {
    let record : Json = {
      "kind": "match".to_json(),
      "rule_id": match_.rule_id.to_json(),
      "description": match_.description.to_json(),
      "file": match_.file.to_json(),
      "start_line": match_.start_line.to_json(),
      "start_column": match_.start_column.to_json(),
      "end_line": match_.end_line.to_json(),
      "end_column": match_.end_column.to_json(),
      "matched_source": match_.matched_source.to_json(),
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
    if @fs.exists(target.to_string()) {
      continue
    }
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
        rule_id: Some("inspect"),
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
        rule_id: Some("inspect"),
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
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to list directory: \{error}")
  }
  // Plain lexicographic order, not `readdir(sort=true)`: that sorts with
  // String's `Compare`, which is shortlex — length before content — and
  // reads wrong in a file listing ("z.mbt" before "main.mbt").
  names.sort_by((a, b) => a.lexical_compare(b))
  let entries : Array[DirEntry] = []
  for name in names {
    let child = dir.join((name : @pathx.Relative)).to_string()
    let is_dir = (@fs.kind(child) catch {
        error if @async.is_being_cancelled() => raise error
        _ => Unknown
      })
      is Directory
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
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to read file: \{error}")
  }
  defer source.close()
  // Check the size before reading anything: a multi-gigabyte build artifact
  // must produce the notice, not a host-sized allocation.
  if source.size() > @openpath.MaxEditorFileBytes.to_int64() {
    return Oversized
  }
  let data = source.read_all() catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to read file: \{error}")
  }
  // The change-detection baseline, from the same open handle as the content
  // so the two cannot disagree about which version of the file was read.
  let (seconds, nanos) = source.mtime() catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to read file: \{error}")
  }
  // Classify the bytes already read from this handle. The shared policy trusts
  // raster signatures rather than extensions and returns decoded text without
  // making callers perform a second UTF-8 pass.
  let bytes = data.binary()
  match @filekind.classify(bytes) {
    RasterImage(media_type~) =>
      BinaryContent(data_base64=@base64.encode(bytes), media_type~)
    Utf8Text(content) => {
      let absolute = file.resource_path()
      Content(content~, absolute~, sig="\{seconds}:\{nanos}")
    }
    Binary => Binary
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
  assert_eq(
    read_file_op({ path: absolute, root: None, }),
    BinaryContent(data_base64="iVBORw0KGgpzbWFsbA==", media_type="image/png"),
  )
  let root = @pathx.Path(@fs.realpath(dir))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  assert_eq(
    read_file_op({ path: "image.png", root: Some(root), }),
    BinaryContent(data_base64="iVBORw0KGgpzbWFsbA==", media_type="image/png"),
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
/// The mtime signatures of the open tabs' files (see `StatFilesPayload`).
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
/// `Present("{seconds}:{nanos}")` of the file's mtime. `Missing` is the path
/// no longer resolving to a file — deleted, or an ancestor that stopped being
/// a directory — by far the common failure. Every other stat error is
/// `Failed` with the OS message: the panel then re-reads the file so the
/// read's own error (or the content) replaces the guess, and the log keeps
/// the stat's.
async fn file_signature(absolute : String) -> FileSignature {
  let (seconds, nanos) = @fs.mtime(absolute) catch {
    error if @async.is_being_cancelled() => raise error
    @os_error.OSError(_) as error if error.is_ENOENT() || error.is_ENOTDIR() =>
      return Missing
    error => {
      @xlog.warn(category="filesystem") <?
        { "event": "stat_failed", "path": absolute, "error": "\{error}" }
      return Failed("\{error}")
    }
  }
  Present("\{seconds}:\{nanos}")
}
