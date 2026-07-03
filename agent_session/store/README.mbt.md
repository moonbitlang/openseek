# OpenSeek Agent Session Store

`bobzhang/openseek/agent_session/store` is the native filesystem persistence
layer for typed OpenSeek sessions. It wraps `agent_session.Session` with the
filesystem rules needed to save, resume, list, and compact durable
conversations.

The package is native-only because it uses `moonbitlang/async/fs` for files,
directory mtimes, and advisory locks.

## Layout

Each session lives under:

```text
<root>/sessions/<session-id>/
  openseek_session-<session-id>.jsonl
  session.lock
```

`openseek_session-<session-id>.jsonl` is the whole durable session: its first
line is a header record (`{"version":1,"id":...,"system_prompt":...}`) and
every following line is one typed `SessionEvent`. Events are append-only.
Loading replays the event lines into an immutable `agent_session.Session`.
The file name carries the session id so files collected out of their
directories — for cross-session visualization or comparison — stay
self-naming.

`session.lock` is an implementation detail used to serialize writers and keep a
reader from seeing a half-updated session. It carries no id suffix: it already
lives inside the per-id directory and is never collected alongside the jsonl.

## API Shape

The root API is small:

```mbt nocheck
let store = @store.SessionStore(".openseek")

store.create(session) // create or replace a complete session
let session = store.load(@agent_session.SessionId("demo"))
let session = store.append(session, User(UserMessage("hello")))
let session = store.compact(
  session,
  content="summary text",
  from_sequence=1,
  to_sequence=20,
)
```

Use `create` when writing a complete session snapshot. Use `append` for normal
agent progress. `append` is the safe save path: it checks that the caller's
in-memory session still matches disk, then appends exactly one timestamped
event line — except when a crash left the file's tail unterminated, in which
case it rewrites the file atomically, repairing the tail as it persists the
new event.

`load` takes a `SessionId` because `SessionStore(root)` is a directory-backed
collection, not a handle to one current session. The id selects
`<root>/sessions/<id>/openseek_session-<id>.jsonl`; the store intentionally
does not keep a hidden "current" session. When the caller needs to discover a session
first, use `list`, `listings`, or `latest`, then pass the chosen id to `load`.

## Create And Load

`create` writes a complete session atomically (temp file, then rename). It is
useful for new sessions, test fixtures, or deliberate rewrites. `load` reads
the single session file, replays the event lines for the requested id,
validates sequence numbers, and rebuilds the immutable `Session`.

More pedantically, `load(id)`:

- validates `id` before using it in a path;
- takes a shared session lock when the session directory exists;
- reads `openseek_session-<id>.jsonl` and checks that the first line is a
  header record whose id equals the requested id;
- parses every following JSON line as a typed `SessionEvent`;
- checks that event sequence numbers are contiguous;
- returns a rebuilt immutable `Session`;
- does not create a missing session, choose a latest session, or mutate disk.

Use `exists(id)` when absence is expected. Use `latest()` when implementing a
default "resume" action. Use `list()` or `listings()` when a human or caller
must choose the id before loading.

```mbt check
///|
async test "create and load a complete session" {
  @vfs.with_tmpdir(prefix="openseek-store-readme-create-", root => {
    let store = @store.SessionStore(root)
    let session = @agent_session.Session(
        SessionId("demo"),
        system_prompt="system",
      )
      .append(User(UserMessage("hello")))
      .append(Terminal(Finished("done")))

    store.create(session)
    let loaded = store.load(SessionId("demo"))
    debug_inspect(
      loaded,
      content=(
        #|{
        #|  id: { value: "demo" },
        #|  system_prompt: "system",
        #|  events: <Vector:
        #|    [
        #|      { sequence: 1, ts: 0, item: User({ content: "hello" }) },
        #|      { sequence: 2, ts: 0, item: Terminal(Finished("done")) },
        #|    ]>,
        #|  last_sequence: 2,
        #|}
      ),
    )
  })
}
```

## Append

`append` is what the CLI, TUI, and serve mode use while an agent turn is
running. It returns the new in-memory session value, so callers should keep using
the returned session for the next append.

The store stamps appended events with the current wall clock. For documentation,
the example snapshots the model projection rather than raw events, keeping the
example stable while still showing the resumed conversation shape.

```mbt check
///|
async test "append saves progress and load resumes it" {
  @vfs.with_tmpdir(prefix="openseek-store-readme-append-", root => {
    let store = @store.SessionStore(root)
    let session = @agent_session.Session(
      SessionId("demo"),
      system_prompt="system",
    )

    store.create(session)
    let session = store.append(session, User(UserMessage("inspect README")))
    ignore(store.append(session, Terminal(Finished("done"))))

    let loaded = store.load(SessionId("demo"))
    debug_inspect(
      loaded.chat_messages(),
      content=(
        #|[
        #|  {
        #|    role: System,
        #|    content: "system",
        #|    tool_calls: [],
        #|    reasoning_content: None,
        #|  },
        #|  {
        #|    role: User,
        #|    content: "inspect README",
        #|    tool_calls: [],
        #|    reasoning_content: None,
        #|  },
        #|  {
        #|    role: Assistant,
        #|    content: "done",
        #|    tool_calls: [],
        #|    reasoning_content: None,
        #|  },
        #|]
      ),
    )
  })
}
```

If another writer has already appended to the same session, appending from an
old in-memory value fails with a stale-snapshot error instead of silently
forking the log:

```mbt check
///|
async test "append rejects a stale in-memory session" {
  @vfs.with_tmpdir(prefix="openseek-store-readme-stale-", root => {
    let store = @store.SessionStore(root)
    let session = @agent_session.Session(
      SessionId("demo"),
      system_prompt="system",
    )

    store.create(session)
    ignore(store.append(session, User(UserMessage("first"))))
    let result = try store.append(session, User(UserMessage("stale"))) catch {
      error => "error: \{error}".contains("stale session snapshot")
    } noraise {
      _ => false
    }
    debug_inspect(
      result,
      content=(
        #|true
      ),
    )
  })
}
```

## Compact

`compact` appends a validated `Summary` event. It does not rewrite earlier
lines of the session file; the raw covered events remain durable. The compaction effect is
visible when `Session::chat_messages` projects model context: covered earlier
events are skipped and the later summary message is used instead.

```mbt check
///|
async test "compact appends a durable summary" {
  @vfs.with_tmpdir(prefix="openseek-store-readme-compact-", root => {
    let store = @store.SessionStore(root)
    let session = @agent_session.Session(
        SessionId("demo"),
        system_prompt="system",
      )
      .append(User(UserMessage("old user")))
      .append(Assistant(AssistantMessage("old assistant")))

    store.create(session)
    ignore(
      store.compact(
        session,
        content="old user and assistant discussed README",
        from_sequence=1,
        to_sequence=2,
      ),
    )

    let loaded = store.load(SessionId("demo"))
    debug_inspect(
      loaded.chat_messages(),
      content=(
        #|[
        #|  {
        #|    role: System,
        #|    content: "system",
        #|    tool_calls: [],
        #|    reasoning_content: None,
        #|  },
        #|  {
        #|    role: User,
        #|    content: "[conversation summary]\nsource_events=1..2\nold user and assistant discussed README",
        #|    tool_calls: [],
        #|    reasoning_content: None,
        #|  },
        #|]
      ),
    )
  })
}
```

## Listing And Resume

Use `list` when all you need is sorted ids. Use `listings` when building a human
picker: each row has an id, last-activity timestamp, and first user prompt.
`latest` is stricter than `listings`: it probes candidates with `load` and
returns the newest loadable session id, skipping torn sessions.

```mbt check
///|
async test "list sessions by id" {
  @vfs.with_tmpdir(prefix="openseek-store-readme-list-", root => {
    let store = @store.SessionStore(root)

    store.create(Session(SessionId("b"), system_prompt="system"))
    store.create(Session(SessionId("a"), system_prompt="system"))
    debug_inspect(
      [
        for id in store.list() => id.value()
      ],
      content=(
        #|["a", "b"]
      ),
    )
  })
}
```

`listings` keeps damaged session directories visible so users can find and clean
them up. `latest` uses loadability as the resume gate.

## File Path Helpers

`session_file` exposes the absolute path of a session's file for read-only
tooling such as the visualizer server. It still validates the session id before
constructing the path.

```mbt nocheck
///|
let path = store.session_file(@agent_session.SessionId("demo"))
```

## Failure Model

The whole session is one file, so there is no cross-file consistency to
maintain:

- `append` is a single `O_APPEND` write of one event line. The first durable
  write for a session (no file yet) writes the header line and the first event
  atomically, so a session file can never exist without its header.
- `create` rewrites the file atomically (temp file, then rename); an
  interrupted rewrite leaves the previous file intact.
- Durability policy: event appends and temp-file writes are flushed with
  `fdatasync` before they return, and every file-creating write (create,
  first append, tail repair) syncs the directory chain — session directory,
  `sessions/`, root — itself, rather than trusting whichever process created
  those directories. On POSIX-style local filesystems this makes a session
  that `create` or `append` just reported durable survive a power loss, not
  only a process crash. The directory syncs are best-effort: on platforms
  where a directory cannot be opened or synced (notably Windows), power-loss
  durability degrades to the filesystem's own guarantees, while
  process-crash safety is unaffected. Two scope limits: the store root's own
  directory entry lives in its parent, outside the store's ownership — when
  the root is created lazily by the store, making the root itself durable is
  the caller's setup concern; and an append to an existing file assumes that
  file's creation was already durably completed by its creator.
- Every load checks the header record and contiguous sequence numbers.
- A crash can tear the final append mid-line. `load` tolerates exactly that —
  an unterminated final record is dropped (or kept when only its newline is
  missing) so the session stays resumable — while `load` itself never writes.
  The next `append` or `compact` repairs the file by rewriting it atomically,
  discarding the uncommitted tail. Corruption anywhere else still fails the
  load.
- Every append or compact checks that the caller's session still matches disk.
  When the snapshot is physically the value this store instance last synced
  and the file's size+mtime+ctime fingerprint is unchanged, that check is
  O(1); any other snapshot — or any on-disk change — falls back to a full
  read-and-compare, so the guarantee is the same either way.

These rules keep persistence concerns out of `agent_session.Session` while
giving CLI, TUI, serve mode, and visualization code one shared durable boundary.
