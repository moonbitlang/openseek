///|
/// Where a session keeps compiled snippets between calls.
///
/// A wasm run is built in a persistent per-session directory rather than a
/// fresh temp dir, so the dependency packages a snippet imports are compiled
/// once per session instead of once per call — measured, that is the whole
/// cost of a call: a cold build of the bundled read workflow is ~570ms, a
/// warm one ~25ms when the source is unchanged and ~270ms when only the
/// snippet body changed (the link step dominates that remainder).
///
/// The cache needs an OWNER whose teardown reclaims it: a session's job dir or
/// a read-only role's scratch lab. The lab wins because the kernel profile
/// those roles run under re-allows exactly one writable subtree, and pointing
/// the cache anywhere else would have `moon` denied at its first write. A
/// standalone definition with neither has no later owner, so it keeps the
/// per-call cold build rather than leak a cache directory.
fn build_cache_root(job_dir? : String, scratch_dir? : String) -> String? {
  match (scratch_dir, job_dir) {
    (Some(lab), _) => Some("\{lab}/mbtx-cache")
    (None, Some(spill)) => Some("\{spill}/mbtx-cache")
    (None, None) => None
  }
}

///|
/// The subdirectory of the cache root a program builds in.
///
/// Every script is staged under the same file name, so the DIRECTORY is the
/// key: moon writes each single-file build's artifact to one fixed path under
/// its target directory (`.../single/single.wasm`), and two scripts sharing a
/// target directory would overwrite each other's program — the later build
/// deciding what BOTH execute. Named scripts get a directory of their own,
/// keyed by resolved path, because their content rarely changes and an
/// unchanged staged file is a ~25ms no-op rebuild. Inline snippets, expected
/// to differ every call, share one directory whose value is the warm
/// dependency compilation, not artifact reuse.
///
/// The resolved path, not the filename the model wrote, is what is keyed: a
/// workspace `check.mbtx` and `@builtin/check.mbtx` are different programs.
/// The basename is kept in the name for a person reading the directory; the
/// digest is what makes it unique.
fn cache_key(script_path : String?) -> String {
  match script_path {
    None => "snippet"
    Some(path) => {
      let base = match path.rev_find("/") {
        Some(i) => path[i + 1:]
        None => path
      }
      let name = StringBuilder()
      for c in base.iter().take(40) {
        name.write_char(
          if c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '.' | '-' | '_') {
            c
          } else {
            '_'
          },
        )
      }
      "named-\{name}-\{fnv1a64(path)}"
    }
  }
}

///|
/// The directory a cached build actually runs in: `<key dir>/gen-N`, where N
/// is the key's current generation. A generation is retired (N+1) when a
/// build in it was stopped mid-way, so the next call builds in a fresh
/// directory rather than in one an orphaned compiler may still be writing
/// to. The generation lives in the definition's memory, not on disk: the
/// cache is the session's and so is the definition, and a retirement that
/// cannot fail is the whole point — a metadata file that failed to write, or
/// read back malformed, would have the next call reuse the directory it was
/// meant to fence off. Older generations are swept here, best-effort: by the
/// time a later call arrives the orphan is long gone, and a sweep that still
/// loses the race only leaves garbage the session reclaims.
async fn open_generation(key_dir : String, generation : Int) -> String {
  let name = "gen-\{generation}"
  let dir = "\{key_dir}/\{name}"
  if !@fs.exists(dir) {
    @fs.mkdir(dir, recursive=true)
  }
  for entry in @fs.readdir(key_dir) {
    if entry.has_prefix("gen-") && entry != name {
      @fs.rmdir("\{key_dir}/\{entry}", recursive=true) catch {
        error if @async.is_being_cancelled() => raise error
        _ => ()
      }
    }
  }
  dir
}

///|
/// FNV-1a over the UTF-16 code units of `text`: deterministic across
/// processes (a directory name must be the same in every session that reuses
/// the cache), and short enough to read.
fn fnv1a64(text : String) -> UInt64 {
  let mut hash : UInt64 = 0xcbf29ce484222325
  for c in text {
    hash = (hash ^ c.to_int().to_uint64()) * 0x100000001b3
  }
  hash
}

///|
/// Write `source` to `path` only when the file does not already hold exactly
/// that text. moon decides what to rebuild by modification time, not content,
/// so rewriting an unchanged staged file would recompile the snippet and
/// relink the program on every call — the ~270ms case — where leaving it
/// alone is the ~25ms no-op. Returns whether the file was written.
async fn stage_source(path : String, source : String) -> Bool {
  // Only a genuinely absent file means "nothing staged yet"; a read that
  // fails for any other reason is carried, not read as a stale file to
  // overwrite. Non-UTF-8 content cannot equal `source`, so it is rewritten.
  let current : String? = try @fs.read_file(path).text() catch {
    error if @async.is_being_cancelled() => raise error
    @os_error.OSError(_) as error if error.is_ENOENT() => None
    @os_error.OSError(_) as error => raise error
    _ => None
  } noraise {
    text => Some(text)
  }
  if current == Some(source) {
    return false
  }
  @fs.write_file(path, source, create_mode=CreateOrTruncate)
  true
}

///|
test "cache root prefers the lab, then the job dir, then nothing" {
  assert_eq(
    build_cache_root(job_dir="/spill", scratch_dir="/lab"),
    Some("/lab/mbtx-cache"),
  )
  assert_eq(build_cache_root(job_dir="/spill"), Some("/spill/mbtx-cache"))
  assert_eq(build_cache_root(scratch_dir="/lab"), Some("/lab/mbtx-cache"))
  assert_eq(build_cache_root(), None)
}

///|
test "cache keys: one shared snippet dir, named scripts keyed by resolved path" {
  assert_eq(cache_key(None), "snippet")
  let a = cache_key(Some("/project/check.mbtx"))
  let b = cache_key(Some("/share/workflow/check.mbtx"))
  assert_true(a.has_prefix("named-check.mbtx-"))
  assert_true(b.has_prefix("named-check.mbtx-"))
  assert_not_eq(a, b)
  assert_eq(a, cache_key(Some("/project/check.mbtx")))
  // Unsafe characters never reach the directory name; long names are cut.
  let odd = cache_key(Some("/p/we ird:name\\x.mbtx"))
  assert_true(odd.has_prefix("named-we_ird_name_x.mbtx-"))
  let long = cache_key(Some("/p/" + "a".repeat(60) + ".mbtx"))
  assert_true(long.has_prefix("named-" + "a".repeat(40) + "-"))
  assert_false(long.contains("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
}
