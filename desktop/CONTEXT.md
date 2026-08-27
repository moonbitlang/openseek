# Desktop Vocabulary

Words that mean one exact thing in `desktop/`. Several of them are ordinary
English that the codebase has already spent on something specific, so a loose
second use silently merges two concepts. Prefer these; when a term below says
"never", it is because that use once existed and cost a bug.

## Two axes, never one

Every conversation answers two independent directory questions. They coincide
for a plain project conversation, which is why they get conflated.

| Conversation | Record lives in (store) | Agent works in (checkout) |
|---|---|---|
| Project `/p` | `/p/.openseek` | `/p` |
| Worktree `wt-1` of `/p` | `/p/.openseek` | `/p/.worktrees/wt-1` |

The worktree row shows the two are siblings, neither containing the other.
Nothing may derive one from the other — each follows from its own input.

## Durable identity

- **session id** — a conversation's name. **Unique only within one store.**
  Generators differ in collision resistance: desktop mints
  `desktop-YYYYMMDD-HHMMSS-mmm-sssssssss` with a random salt
  (`frontend/session.mbt`), the TUI's `tui-...` form has no salt
  (`SessionId::generated`'s `salt?` defaults to empty), and the CLI takes
  `--session <name>` verbatim. Never treat an id alone as an identity.
- **record** — one conversation's durable directory, `<root>/sessions/<id>/`:
  transcript, title, standing goal, review base. Deleting it is what "delete a
  conversation" means; project files are never touched.
- **store** (session store) — the root a record lives under: one per
  registered workspace (`@workspaces.store_root(w)` = `<w>/.openseek`),
  enumerated by `@session_store.known_roots()`. A store *has* a root; the two
  words are not interchangeable.
- **root** — the path of a store, and the value passed as `--session-root`.
  Only ever say "root" unqualified about a store. Other roots exist
  (`workspace_root()`, `checkout_root`) and are checkouts, not stores — always
  qualify those.
- **family** — a record plus every `-sr-N` descendant sub-run record beside it.
  Records are flat sibling directories even though the sidebar draws a tree, so
  a family is discovered by id structure (`is_descendant_session`), never by a
  textual prefix. Archive, unarchive, and delete move a whole family or none of
  it.
- **archived twin** — `<root>/archived/sessions/<id>`, the same layout one
  level down, so listing archived conversations is one more `sessions list`.
  `<root>/archived/deleting/` holds condemned records; a rename into it is
  permanent deletion's commit point.

## Directories

- **workspace** — a *registered project directory*. The host registry, never a
  request, decides which directories qualify. Every conversation belongs to
  one, and its store is that project's.
- **worktree** — `<workspace>/.worktrees/<name>`, a checkout owned by exactly
  one conversation. Its records still live in the **project's** store.
- **checkout** / **cwd** — the directory the agent, terminals, and file
  operations work in. Derived from (workspace, id) through the worktree
  registry, never searched for.
- **placement** — already means two things, both about checkouts, and must
  never be stretched to cover a store: (1) the retained worktree registry row
  that survives archiving so an unarchive reads as `MissingTree` and can offer
  a rebuild; (2) `CheckoutPlacement` (`frontend/interop/channel.mbt`), the
  client's four-case view of a conversation's checkout.

## Runtime

- **serve engine** — one `openseek serve` child process. The host runs **at
  most one per session id**; slots are keyed by id alone, so any operation
  naming a store must ask whether a live engine actually writes that store
  before treating it as its own.
- **slot** — a session id's entry in the manager's map: its engine, its pending
  claim, its follower generation.
- **follower** — the actor tailing one record's durable tail.
- **run** — one turn: a prompt through its terminal event. A conversation
  outlives its runs; a run never outlives its conversation.

## Wire versus host

The protocol has no word for a store. Every op addressing a record spells one
as `workspace`: the registered project's resource path the host itself
reported. The host validates it against the registry rather than trusting the
spelling, and selects that store exactly instead of searching.

That one field answers both directory questions — which store holds the
record, and which project the run works in — because a project owns both. Say
which one you mean when the difference matters, as it does for a worktree
conversation, whose checkout is not its project's directory.
