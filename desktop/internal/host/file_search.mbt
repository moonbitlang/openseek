// VS Code-shaped file search. A cache key names one search session: the first
// request scans its absolute root once, later queries filter that cached
// snapshot, and clearCache is the only operation that retires the session.
// Discovery intentionally has one coordinator instead of a per-connection
// worker pool; a future bundled ripgrep provider can replace this scanner
// without changing the cache/session state machine.

///|
const MaxFileSearchResults : Int = 512

///|
const FileSearchRankingChunkSize : Int = 512

///|
const FileScanCancellationChunkSize : Int = 512

///|
priv struct FileIndexSnapshot {
  files : Array[String]
}

///|
priv struct FileScanEntry {
  name : String
  is_dir : Bool
}

///|
/// File discovery is best-effort: a directory that disappears or becomes
/// unreadable cannot fail the whole scan, while cancellation still stops it.
async fn read_sorted_directory(dir : @pathx.Absolute) -> Array[FileScanEntry] {
  let listing = @fs.opendir(dir.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return []
  }
  defer listing.close()
  let entries : Array[FileScanEntry] = []
  for ;; {
    let entry = listing.next() catch {
      error if @async.is_being_cancelled() => raise error
      _ => None
    }
    guard entry is Some(entry) else { break }
    entries.push({ name: entry.name, is_dir: entry.is_dir, })
  }
  entries.sort_by((left, right) => left.name.lexical_compare(right.name))
  entries
}

///|
fn relative_child(prefix : String, name : String) -> String {
  if prefix.is_empty() {
    name
  } else {
    "\{prefix}/\{name}"
  }
}

///|
async fn collect_directory_listing(
  dir : @pathx.Absolute,
  prefix : String,
  entries : Array[FileScanEntry],
  into : Array[String],
  read : async (@pathx.Absolute) -> Array[FileScanEntry],
) -> Unit {
  let mut processed = 0
  for entry in entries {
    processed += 1
    if processed % FileScanCancellationChunkSize == 0 {
      @async.pause()
    }
    let relative = relative_child(prefix, entry.name)
    if entry.is_dir {
      if @file_search_policy.excludes_directory(relative) {
        continue
      }
      let child = dir.join(Relative(entry.name))
      collect_directory_listing(child, relative, read(child), into, read)
    } else {
      into.push(relative)
    }
  }
}

///|
async fn scan_directory_tree(
  root : @pathx.Absolute,
  read : async (@pathx.Absolute) -> Array[FileScanEntry],
) -> FileIndexSnapshot {
  let files : Array[String] = []
  collect_directory_listing(root, "", read(root), files, read)
  { files, }
}

///|
async fn scan_workspace_files(root : @pathx.Absolute) -> FileIndexSnapshot {
  if !@fs.exists(root.to_string()) {
    return { files: [], }
  }
  scan_directory_tree(root, read_sorted_directory)
}

///|
priv enum FileSearchResponse {
  SearchSucceeded(SearchFilesReply)
  SearchCancelled
  SearchFailed(String)
}

///|
priv enum FileScanOutcome {
  ScanSucceeded(FileIndexSnapshot)
  ScanFailed(String)
}

///|
priv struct PendingFileSearch {
  query : String
  request_id : String
  max_results : Int
  from_cache : Bool
  reply : @async.Queue[FileSearchResponse]
}

///|
priv struct FileSearchComputation {
  files : Array[String]
  limit_hit : Bool
  inspected : Int
}

///|
priv enum FileRankOutcome {
  RankSucceeded(FileSearchComputation)
  RankFailed(String)
}

///|
priv struct FileSearchCache {
  root_key : String
  snapshot : FileIndexSnapshot?
  scan_id : String
}

///|
priv struct RunningFileScan {
  root_key : String
  id : String
  waiters : Array[PendingFileSearch]
  task : @async.Task[Unit]
}

///|
priv struct RunningFileRank {
  cache_key : String
  scan_id : String
  query_key : String
  max_results : Int
  waiters : Array[PendingFileSearch]
  task : @async.Task[Unit]
}

///|
priv enum FileSearchRequest {
  Search(
    root~ : @pathx.Absolute,
    root_key~ : String,
    cache_key~ : String,
    query~ : String,
    max_results~ : Int,
    request_id~ : String,
    reply~ : @async.Queue[FileSearchResponse]
  )
  Cancel(request_id~ : String, reply~ : @async.Queue[Unit])
  Clear(cache_key~ : String, reply~ : @async.Queue[Unit])
  ScanFinished(
    cache_key~ : String,
    root_key~ : String,
    id~ : String,
    outcome~ : FileScanOutcome
  )
  RankFinished(
    cache_key~ : String,
    scan_id~ : String,
    id~ : String,
    outcome~ : FileRankOutcome
  )
}

///|
priv struct FileSearchService {
  requests : @async.Queue[FileSearchRequest]
  scan : async (@pathx.Absolute) -> FileIndexSnapshot
}

///|
fn FileSearchService::FileSearchService() -> FileSearchService {
  FileSearchService::new_with_scan(root => scan_workspace_files(root))
}

///|
fn FileSearchService::new_with_scan(
  scan : async (@pathx.Absolute) -> FileIndexSnapshot,
) -> FileSearchService {
  { requests: Queue(kind=Blocking(64)), scan, }
}

///|
async fn FileSearchService::search(
  self : FileSearchService,
  root : @pathx.Absolute,
  cache_key : String,
  query : String,
  max_results : Int,
  request_id : String,
) -> SearchFilesReply {
  let reply : @async.Queue[FileSearchResponse] = Queue(kind=Blocking(1))
  self.requests.put(
    Search(
      root~,
      root_key=root.to_string(),
      cache_key~,
      query~,
      max_results~,
      request_id~,
      reply~,
    ),
  )
  match reply.get() {
    SearchSucceeded(result) => result
    SearchCancelled =>
      { files: [], from_cache: true, limit_hit: false, cancelled: true, }
    SearchFailed(message) => raise HostError(message)
  }
}

///|
async fn FileSearchService::cancel(
  self : FileSearchService,
  request_id : String,
) -> Unit {
  let reply : @async.Queue[Unit] = Queue(kind=Blocking(1))
  self.requests.put(Cancel(request_id~, reply~))
  reply.get()
}

///|
async fn FileSearchService::clear_cache(
  self : FileSearchService,
  cache_key : String,
) -> Unit {
  let reply : @async.Queue[Unit] = Queue(kind=Blocking(1))
  self.requests.put(Clear(cache_key~, reply~))
  reply.get()
}

///|
fn file_search_reply(
  computed : FileSearchComputation,
  from_cache : Bool,
) -> SearchFilesReply {
  {
    files: computed.files,
    from_cache,
    limit_hit: computed.limit_hit,
    cancelled: false,
  }
}

///|
fn merge_ranked_chunk(
  query : @file_search_score.PathQuery,
  current : Array[String],
  chunk : Array[String],
  limit : Int,
) -> Array[String] {
  if chunk.is_empty() || limit <= 0 {
    current
  } else {
    query.rank_paths(current + query.rank_paths(chunk, limit), limit)
  }
}

///|
async fn compute_file_search(
  snapshot : FileIndexSnapshot,
  query_text : String,
  max_results : Int,
) -> FileSearchComputation {
  let query = @file_search_score.PathQuery(query_text)
  if query.is_empty() {
    return {
      files: snapshot.files[:snapshot.files.length().min(max_results)].to_owned(),
      limit_hit: snapshot.files.length() > max_results,
      inspected: 0,
    }
  }
  let mut chunk : Array[String] = []
  let mut best : Array[String] = []
  let mut inspected = 0
  let mut matched = 0
  // VS Code's Quick Open preloads the empty-pattern cache row and filters that
  // complete row for every query. Do the same here: retaining candidate arrays
  // for every keystroke multiplies memory by the number of typed prefixes.
  for path in snapshot.files {
    inspected += 1
    if query.matches(path) {
      matched += 1
      if max_results > 0 {
        chunk.push(path)
      }
    }
    if inspected % FileSearchRankingChunkSize == 0 {
      best = merge_ranked_chunk(query, best, chunk, max_results)
      chunk = []
      @async.pause()
    }
  }
  best = merge_ranked_chunk(query, best, chunk, max_results)
  { files: best, limit_hit: matched > max_results, inspected, }
}

///|
async fn FileSearchService::run(self : FileSearchService) -> Unit {
  @async.with_task_group(group => {
    // VS Code delegates discovery to one ripgrep process. Until OpenSeek
    // bundles that provider, serialize the fallback walker per connection so
    // a client cannot multiply directory IO by opening overlapping sessions.
    let scan_permit : @semaphore.Semaphore = Semaphore(1, initial_value=1)
    let caches : Map[String, FileSearchCache] = Map([])
    let running_scans : Map[String, RunningFileScan] = Map([])
    let running_ranks : Map[String, RunningFileRank] = Map([])
    // Cancellation is a second RPC and may overtake its search. Remember the
    // exact request UUID until that search arrives.
    let cancellations = CancelledRequests()

    // Settle the one waiter carrying `request_id` if it queued here, and
    // return the waiters that remain; `None` when it queued elsewhere.
    async fn cancel_waiter(
      waiters : Array[PendingFileSearch],
      request_id : String,
    ) -> Array[PendingFileSearch]? {
      guard waiters.iter().any(waiter => waiter.request_id == request_id) else {
        return None
      }
      let kept : Array[PendingFileSearch] = []
      for waiter in waiters {
        if waiter.request_id == request_id {
          waiter.reply.put(SearchCancelled)
        } else {
          kept.push(waiter)
        }
      }
      Some(kept)
    }

    async fn launch_rank(
      cache_key : String,
      waiter : PendingFileSearch,
    ) -> Unit {
      guard caches.get(cache_key) is Some(cache) &&
        cache.snapshot is Some(snapshot) else {
        waiter.reply.put(SearchFailed("file search cache is not ready"))
        return
      }
      let prepared = @file_search_score.PathQuery(waiter.query)
      if prepared.is_empty() {
        let computed : FileSearchComputation = {
          files: snapshot.files[:snapshot.files.length().min(waiter.max_results)].to_owned(),
          limit_hit: snapshot.files.length() > waiter.max_results,
          inspected: 0,
        }
        waiter.reply.put(
          SearchSucceeded(file_search_reply(computed, waiter.from_cache)),
        )
        return
      }
      let mut joined : String? = None
      for id, running in running_ranks {
        if running.cache_key == cache_key &&
          running.scan_id == cache.scan_id &&
          running.query_key == prepared.key() &&
          running.max_results == waiter.max_results {
          joined = Some(id)
          break
        }
      }
      if joined is Some(id) && running_ranks.get(id) is Some(running) {
        let waiters = running.waiters.copy()
        waiters.push(waiter)
        running_ranks[id] = { ..running, waiters, }
        return
      }
      let id = waiter.request_id
      let scan_id = cache.scan_id
      let task = group.spawn(no_wait=true, allow_failure=true, () => {
        let outcome = RankSucceeded(
          compute_file_search(snapshot, waiter.query, waiter.max_results),
        ) catch {
          _ if @async.is_being_cancelled() => return
          error => RankFailed("failed to rank workspace files: \{error}")
        }
        self.requests.put(RankFinished(cache_key~, scan_id~, id~, outcome~))
      })
      running_ranks[id] = {
        cache_key,
        scan_id,
        query_key: prepared.key(),
        max_results: waiter.max_results,
        waiters: [waiter],
        task,
      }
    }

    for ;; {
      match self.requests.get() {
        Search(
          root~,
          root_key~,
          cache_key~,
          query~,
          max_results~,
          request_id~,
          reply~
        ) => {
          if cache_key.is_empty() {
            reply.put(SearchFailed("file search cache key is empty"))
            continue
          }
          if cancellations.contains(request_id) {
            cancellations.remove(request_id)
            reply.put(SearchCancelled)
            continue
          }
          let max_results = max_results.max(0).min(MaxFileSearchResults)
          let existed = caches.contains(cache_key)
          let waiter : PendingFileSearch = {
            query,
            request_id,
            max_results,
            from_cache: existed,
            reply,
          }
          match caches.get(cache_key) {
            Some(cache) =>
              if cache.root_key != root_key {
                reply.put(
                  SearchFailed("file search cache belongs to another workspace"),
                )
              } else if cache.snapshot is Some(_) {
                launch_rank(cache_key, waiter)
              } else if running_scans.get(cache_key) is Some(running) {
                let waiters = running.waiters.copy()
                waiters.push(waiter)
                running_scans[cache_key] = { ..running, waiters, }
              } else {
                caches.remove(cache_key)
                reply.put(SearchFailed("file search cache lost its scan"))
              }
            None => {
              let id = request_id
              caches[cache_key] = { root_key, snapshot: None, scan_id: id }
              let task = group.spawn(no_wait=true, allow_failure=true, () => {
                let outcome = try {
                  scan_permit.acquire()
                  defer scan_permit.release()
                  ScanSucceeded((self.scan)(root))
                } catch {
                  _ if @async.is_being_cancelled() => return
                  error => ScanFailed("failed to index workspace: \{error}")
                }
                self.requests.put(
                  ScanFinished(cache_key~, root_key~, id~, outcome~),
                )
              })
              running_scans[cache_key] = {
                root_key,
                id,
                waiters: [waiter],
                task,
              }
            }
          }
        }
        Cancel(request_id~, reply~) => {
          // A request queues as exactly one waiter, on the scan populating its
          // cache or on one rank over that cache.
          let mut matched = false
          for entry in running_scans.to_array() {
            let (cache_key, running) = entry
            if cancel_waiter(running.waiters, request_id) is Some(kept) {
              matched = true
              // A cache-populating scan deliberately survives cancellation of
              // one query, matching VS Code's preventCancellation cache row.
              running_scans[cache_key] = { ..running, waiters: kept }
            }
          }
          for entry in running_ranks.to_array() {
            let (id, running) = entry
            if cancel_waiter(running.waiters, request_id) is Some(kept) {
              matched = true
              if kept.is_empty() {
                running.task.cancel()
                running_ranks.remove(id)
              } else {
                running_ranks[id] = { ..running, waiters: kept }
              }
            }
          }
          if !matched {
            cancellations.record(request_id)
          }
          reply.put(())
        }
        Clear(cache_key~, reply~) => {
          caches.remove(cache_key)
          if running_scans.get(cache_key) is Some(running) {
            running.task.cancel()
            for waiter in running.waiters {
              waiter.reply.put(SearchCancelled)
            }
            running_scans.remove(cache_key)
          }
          let affected : Array[String] = []
          for id, running in running_ranks {
            if running.cache_key == cache_key {
              affected.push(id)
            }
          }
          for id in affected {
            if running_ranks.get(id) is Some(running) {
              running.task.cancel()
              for waiter in running.waiters {
                waiter.reply.put(SearchCancelled)
              }
              running_ranks.remove(id)
            }
          }
          reply.put(())
        }
        ScanFinished(cache_key~, root_key~, id~, outcome~) => {
          guard running_scans.get(cache_key) is Some(running) &&
            running.root_key == root_key &&
            running.id == id else {
            continue
          }
          running_scans.remove(cache_key)
          let waiters = running.waiters
          guard caches.get(cache_key) is Some(cache) &&
            cache.root_key == root_key &&
            cache.scan_id == id else {
            for waiter in waiters {
              waiter.reply.put(SearchCancelled)
            }
            continue
          }
          match outcome {
            ScanSucceeded(snapshot) => {
              caches[cache_key] = { ..cache, snapshot: Some(snapshot), }
              for waiter in waiters {
                launch_rank(cache_key, waiter)
              }
            }
            ScanFailed(message) => {
              caches.remove(cache_key)
              for waiter in waiters {
                waiter.reply.put(SearchFailed(message))
              }
            }
          }
        }
        RankFinished(cache_key~, scan_id~, id~, outcome~) => {
          guard running_ranks.get(id) is Some(running) else { continue }
          running_ranks.remove(id)
          guard running.cache_key == cache_key &&
            running.scan_id == scan_id &&
            caches.get(cache_key) is Some(cache) &&
            cache.scan_id == scan_id &&
            cache.snapshot is Some(_) else {
            for waiter in running.waiters {
              waiter.reply.put(SearchCancelled)
            }
            continue
          }
          match outcome {
            RankSucceeded(computed) =>
              for waiter in running.waiters {
                waiter.reply.put(
                  SearchSucceeded(
                    file_search_reply(computed, waiter.from_cache),
                  ),
                )
              }
            RankFailed(message) =>
              for waiter in running.waiters {
                waiter.reply.put(SearchFailed(message))
              }
          }
        }
      }
    }
  })
}

///|
async fn search_files_op(
  service : FileSearchService,
  payload : SearchFilesPayload,
) -> SearchFilesReply {
  let root = WirePath::parse(payload.path).absolute
  service.search(
    root,
    payload.cache_key,
    payload.query,
    payload.max_results,
    payload.request_id,
  )
}

///|
async fn cancel_search_files_op(
  service : FileSearchService,
  payload : CancelSearchFilesPayload,
) -> @protocol.EmptyReply {
  service.cancel(payload.request_id)
  Acknowledged
}

///|
async fn clear_file_search_cache_op(
  service : FileSearchService,
  payload : ClearFileSearchCachePayload,
) -> @protocol.EmptyReply {
  service.clear_cache(payload.cache_key)
  Acknowledged
}

///|
fn test_scan_entry(name : String, is_dir : Bool) -> FileScanEntry {
  { name, is_dir, }
}

///|
async test "file scan keeps lexicographic DFS and skips ignored directories" {
  let root = @pathx.Path("/virtual-workspace").resolve()
  let src = root.join(Relative("src")).to_string()
  let snapshot = scan_directory_tree(root, dir => {
    match dir.to_string() {
      path if path == root.to_string() =>
        [
          test_scan_entry(".claude", true),
          test_scan_entry(".git", true),
          test_scan_entry("linked-dir", false),
          test_scan_entry("src", true),
          test_scan_entry("z.mbt", false),
        ]
      path if path == src =>
        [
          test_scan_entry("a.mbt", false),
          test_scan_entry("node_modules", true),
          test_scan_entry("z.mbt", false),
        ]
      _ => fail("unexpected directory read")
    }
  })
  assert_eq(snapshot.files, ["linked-dir", "src/a.mbt", "src/z.mbt", "z.mbt"])
}

///|
async test "file scan uses one ordered coordinator" {
  let root = @pathx.Path("/virtual-sequential").resolve()
  let active = Ref(0)
  let maximum = Ref(0)
  let snapshot = scan_directory_tree(root, async fn(dir) {
    active.val += 1
    maximum.val = maximum.val.max(active.val)
    @async.pause()
    active.val -= 1
    if dir.to_string() == root.to_string() {
      [test_scan_entry("a", true), test_scan_entry("b", true)]
    } else {
      [test_scan_entry("one.mbt", false)]
    }
  })
  assert_eq(maximum.val, 1)
  assert_eq(snapshot.files, ["a/one.mbt", "b/one.mbt"])
}

///|
async test "file scan skips a directory that cannot be opened" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="openseek-file-search-unreadable-")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    @fs.mkdir("\{root}/b-readable")
    @fs.write_file(
      "\{root}/b-readable/kept.mbt",
      "",
      create_mode=CreateOrTruncate,
    )
    let absolute = @pathx.Path(root).resolve()
    let snapshot = scan_directory_tree(absolute, dir => {
      if dir == absolute {
        [
          test_scan_entry("a-vanished", true),
          test_scan_entry("b-readable", true),
        ]
      } else {
        read_sorted_directory(dir)
      }
    })
    assert_eq(snapshot.files, ["b-readable/kept.mbt"])
  }
}

///|
async test "native file scan uses the same ignore and DFS semantics" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="openseek-file-search-")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    @fs.mkdir("\{root}/a", recursive=true)
    @fs.mkdir("\{root}/.claude/session", recursive=true)
    @fs.mkdir("\{root}/node_modules/pkg", recursive=true)
    @fs.write_file("\{root}/a/2.mbt", "", create_mode=CreateOrTruncate)
    @fs.write_file("\{root}/a/1.mbt", "", create_mode=CreateOrTruncate)
    @fs.write_file("\{root}/a.txt", "", create_mode=CreateOrTruncate)
    @fs.write_file(
      "\{root}/.claude/session/state.json",
      "",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{root}/node_modules/pkg/hidden.mbt",
      "",
      create_mode=CreateOrTruncate,
    )
    let snapshot = scan_workspace_files(@pathx.Path(root).resolve())
    assert_eq(snapshot.files, ["a/1.mbt", "a/2.mbt", "a.txt"])
  }
}

///|
async test "Host ranking searches the complete snapshot" {
  let files = Array::makei(20000, index => "noise/file-\{index}.txt")
  files.push("late/needle.mbt")
  let computed = compute_file_search({ files, }, "needle", 200)
  assert_eq(computed.inspected, 20001)
  assert_eq(computed.files, ["late/needle.mbt"])
}

///|
async test "successive queries retain complete-snapshot recall" {
  let files = Array::makei(2000, index => "noise/file-\{index}.txt")
  files.push("src/app.mbt")
  files.push("src/application.mbt")
  let snapshot : FileIndexSnapshot = { files, }
  let first = compute_file_search(snapshot, "app", 200)
  assert_eq(first.inspected, 2002)
  assert_eq(first.files, ["src/app.mbt", "src/application.mbt"])
  let narrowed = compute_file_search(snapshot, "appli", 200)
  assert_eq(narrowed.inspected, 2002)
  assert_eq(narrowed.files, ["src/application.mbt"])
  assert_eq(
    narrowed.files,
    @file_search_score.rank_paths("appli", snapshot.files, 200),
  )
}

///|
async test "cancel-before-search rejects only the exact request UUID" {
  @async.with_task_group(group => {
    let service = FileSearchService::new_with_scan(fn(_) {
      { files: ["target.mbt"] }
    })
    group.spawn_bg(() => service.run())
    let root = @pathx.Path("/workspace-cancel-before").resolve()
    service.cancel("cancelled-request")
    let cancelled = service.search(
      root, "cache-a", "target", 200, "cancelled-request",
    )
    assert_true(cancelled.cancelled)
    let accepted = service.search(
      root, "cache-a", "target", 200, "accepted-request",
    )
    assert_false(accepted.cancelled)
    assert_eq(accepted.files, ["target.mbt"])
    group.return_immediately(())
  })
}

///|
async test "query cancellation keeps the cache-populating scan alive" {
  @async.with_task_group(group => {
    let starts : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let release : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let service = FileSearchService::new_with_scan(async fn(_) {
      starts.put(())
      release.get()
      { files: ["target.mbt"], }
    })
    group.spawn_bg(() => service.run())
    let root = @pathx.Path("/workspace-cancel").resolve()
    let first = group.spawn(() => {
      service.search(root, "cache-a", "", 0, "request-1")
    })
    @async.with_timeout(1000, () => starts.get())
    service.cancel("request-1")
    let cancelled = @async.with_timeout(1000, () => first.wait())
    assert_true(cancelled.cancelled)
    release.put(())
    @async.pause()
    let cached = service.search(root, "cache-a", "target", 200, "request-2")
    assert_true(cached.from_cache)
    assert_eq(cached.files, ["target.mbt"])
    group.return_immediately(())
  })
}

///|
async test "cache keys coalesce scans and clearCache retires one session" {
  @async.with_task_group(group => {
    let starts : @async.Queue[Unit] = Queue(kind=Blocking(2))
    let outcomes : @async.Queue[FileIndexSnapshot] = Queue(kind=Blocking(2))
    let service = FileSearchService::new_with_scan(async fn(_) {
      starts.put(())
      outcomes.get()
    })
    group.spawn_bg(() => service.run())
    let root = @pathx.Path("/workspace-cache").resolve()
    let warm = group.spawn(() => {
      service.search(root, "cache-a", "", 0, "request-1")
    })
    @async.with_timeout(1000, () => starts.get())
    let joined = group.spawn(() => {
      service.search(root, "cache-a", "old", 200, "request-2")
    })
    @async.pause()
    assert_true(starts.try_get() is None)
    outcomes.put({ files: ["old.mbt", "other.mbt"], })
    ignore(@async.with_timeout(1000, () => warm.wait()))
    let joined_reply = @async.with_timeout(1000, () => joined.wait())
    assert_true(joined_reply.from_cache)
    assert_eq(joined_reply.files, ["old.mbt"])
    let narrowed = service.search(root, "cache-a", "old.m", 200, "request-3")
    assert_true(narrowed.from_cache)
    assert_eq(narrowed.files, ["old.mbt"])
    service.clear_cache("cache-a")
    let fresh = group.spawn(() => {
      service.search(root, "cache-a", "new", 200, "request-4")
    })
    @async.with_timeout(1000, () => starts.get())
    outcomes.put({ files: ["new.mbt"], })
    let fresh_reply = @async.with_timeout(1000, () => fresh.wait())
    assert_false(fresh_reply.from_cache)
    assert_eq(fresh_reply.files, ["new.mbt"])
    group.return_immediately(())
  })
}

///|
async test "one connection serializes discovery across cache sessions" {
  @async.with_task_group(group => {
    let starts : @async.Queue[String] = Queue(kind=Blocking(2))
    let releases : @async.Queue[Unit] = Queue(kind=Blocking(2))
    let service = FileSearchService::new_with_scan(async fn(root) {
      starts.put(root.to_string())
      releases.get()
      { files: ["file.mbt"], }
    })
    group.spawn_bg(() => service.run())
    let first_root = @pathx.Path("/workspace-one").resolve()
    let second_root = @pathx.Path("/workspace-two").resolve()
    let first = group.spawn(() => {
      service.search(first_root, "cache-one", "", 0, "request-1")
    })
    assert_eq(
      @async.with_timeout(1000, () => starts.get()),
      first_root.to_string(),
    )
    let second = group.spawn(() => {
      service.search(second_root, "cache-two", "", 0, "request-2")
    })
    @async.pause()
    assert_true(starts.try_get() is None)
    releases.put(())
    ignore(@async.with_timeout(1000, () => first.wait()))
    assert_eq(
      @async.with_timeout(1000, () => starts.get()),
      second_root.to_string(),
    )
    releases.put(())
    ignore(@async.with_timeout(1000, () => second.wait()))
    group.return_immediately(())
  })
}

///|
async test "a failed cache population is not installed and can retry" {
  @async.with_task_group(group => {
    let attempts = Ref(0)
    let service = FileSearchService::new_with_scan(_ => {
      attempts.val += 1
      if attempts.val == 1 {
        raise HostError("injected discovery failure")
      }
      { files: ["recovered.mbt"], }
    })
    group.spawn_bg(() => service.run())
    let root = @pathx.Path("/workspace-retry").resolve()
    let mut failed = false
    ignore(service.search(root, "cache-a", "", 0, "request-1")) catch {
      HostError(_) => failed = true
      error => raise error
    }
    assert_true(failed)
    let recovered = service.search(root, "cache-a", "recover", 512, "request-2")
    assert_false(recovered.from_cache)
    assert_eq(recovered.files, ["recovered.mbt"])
    assert_eq(attempts.val, 2)
    group.return_immediately(())
  })
}

///|
async test "a cache key cannot cross workspace roots" {
  @async.with_task_group(group => {
    let service = FileSearchService::new_with_scan(fn(_) {
      { files: ["one.mbt"], }
    })
    group.spawn_bg(() => service.run())
    let first = @pathx.Path("/workspace-one").resolve()
    let second = @pathx.Path("/workspace-two").resolve()
    ignore(service.search(first, "cache-a", "", 0, "request-1"))
    let mut failed = false
    ignore(service.search(second, "cache-a", "", 0, "request-2")) catch {
      HostError(_) => failed = true
      error => raise error
    }
    assert_true(failed)
    group.return_immediately(())
  })
}
