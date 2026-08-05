// The editor side-panel's filesystem calls: list a directory and read a file
// under the active conversation's workspace, through the host's
// `read_directory` / `read_file` ops. The host resolves every path against
// the session's workspace and rejects escapes, so the panel only ever sees
// that one conversation's tree. Each reply carries the full conversation
// owner and path it answers so a reply that lost a device/session switch can
// be discarded.

///|
/// List `path` (relative to the conversation workspace; "" is the root) and
/// fold the entries back as `DirLoaded`.
fn read_directory(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  path : @pathx.Relative,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.fs_read_directory,
        {
          session: owner.session,
          path: path.0,
          workspace: workspace.map(value => value.0),
        },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              DirFailed(
                owner~,
                path~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      let entries : Array[FileEntry] = []
      for entry in reply.entries {
        if FileEntry::from_reply(entry, path) is Some(entry) {
          entries.push(entry)
        }
      }
      scheduler.add(dispatch(DirLoaded(owner~, path~, entries~)))
    })
  })
}

///|
/// Ask the host for the workspace's full file list (the fuzzy filter's
/// index) and fold it back as `FilesIndexed`. Failures fold as
/// `FileIndexFailed`, dropping the index so a later keystroke retries.
fn list_files(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.fs_list_files,
        { session: owner.session, workspace: workspace.map(value => value.0) },
      ) catch {
        _ => {
          scheduler.add(dispatch(FileIndexFailed(owner~)))
          return
        }
      }
      let files = reply.files.filter_map(path => {
        if path.is_empty() {
          None
        } else {
          Some(@pathx.Relative(path))
        }
      })
      scheduler.add(
        dispatch(FilesIndexed(owner~, files~, truncated=reply.truncated)),
      )
    })
  })
}

///|
/// Read `path` and fold its contents back as `FileLoaded`. `name` is the
/// entry's display name, forwarded for the viewer's title and language guess.
/// `range`, when present (a symbol jump's target), is forwarded for the
/// viewer to reveal and select once loaded; `annotation` (an annotation
/// chip's comment) rides along the same way, re-shown as an editor bubble
/// over that range.
pub fn read_file(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  path : @pathx.Relative,
  name : String,
  range~ : @common.Range?,
  annotation? : String,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.fs_read_file,
        {
          session: owner.session,
          path: path.0,
          workspace: workspace.map(value => value.0),
        },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              FileFailed(owner~, message=@interop.bridge_error_text(error)),
            ),
          )
          return
        }
      }
      match FileContent::from_reply(reply) {
        Some(file) =>
          scheduler.add(
            dispatch(
              FileLoaded(owner~, path~, name~, file~, range~, annotation~),
            ),
          )
        None =>
          scheduler.add(
            dispatch(FileFailed(owner~, message="could not read file")),
          )
      }
    })
  })
}

///|
/// A workspace-relative path's final `/`-segment, for a mention chip's jump
/// target — it carries only the path, not a display name.
pub fn basename(path : @pathx.Relative) -> String {
  match [..path.0.split("/")] {
    [] => path.0
    [.., last] => last.to_owned()
  }
}

///|
/// An entry's workspace-relative path: the parent directory's path joined with
/// the entry name ("" parent = workspace root, so the child path is `name`).
fn child_path(parent : @pathx.Relative, name : String) -> @pathx.Relative {
  if parent.is_root() {
    Relative(name)
  } else {
    Relative("\{parent.0}/\{name}")
  }
}

///|
/// Convert one typed directory row into the panel's path-aware entry.
fn FileEntry::from_reply(
  entry : @protocol.DirEntry,
  parent : @pathx.Relative,
) -> FileEntry? {
  guard !entry.name.is_empty() else { return None }
  Some({
    name: entry.name,
    path: child_path(parent, entry.name),
    is_dir: entry.is_dir,
  })
}

///|
fn FileContent::from_reply(reply : @protocol.ReadFileReply) -> FileContent? {
  match reply {
    @protocol.Binary => Some(Binary)
    @protocol.Oversized => Some(Oversized)
    @protocol.Content(content~, absolute~, sig~) => {
      guard !absolute.is_empty() else { return None }
      Some(Content(content~, absolute=Absolute(absolute), sig~))
    }
  }
}

///|
/// Read one file for a cross-resource Peek preview without entering the tab
/// state machine. This deliberately reuses the same `fs.read_file` wire op
/// and decoder as ordinary file opening, so binary/oversized policy and
/// workspace containment stay identical. Failures are unavailable previews,
/// not panel errors, and therefore return `None` to the resolver.
async fn read_file_snapshot(
  owner : @interop.ConversationKey,
  path : @pathx.Relative,
  workspace~ : @pathx.Absolute?,
) -> FileContent? {
  let reply = @interop.bridge_request(owner.channel, @commands.fs_read_file, {
    session: owner.session,
    path: path.0,
    workspace: workspace.map(value => value.0),
  }) catch {
    _ => return None
  }
  FileContent::from_reply(reply)
}

///|
/// Stat the open tabs' files and fold the signatures back as `StatsLoaded`.
/// Best-effort: a failed call is dropped — the next change push retries.
fn stat_files(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  paths : Array[@pathx.Relative],
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.fs_stat_files,
        {
          session: owner.session,
          paths: paths.map(path => path.0),
          workspace: workspace.map(value => value.0),
        },
      ) catch {
        _ => return
      }
      let stats : Array[FileStat] = []
      for stat in reply.stats {
        if !stat.path.is_empty() {
          stats.push({
            path: Relative(stat.path),
            sig: if stat.sig.is_empty() {
              None
            } else {
              Some(stat.sig)
            },
          })
        }
      }
      scheduler.add(dispatch(StatsLoaded(owner~, stats~)))
    })
  })
}

///|
/// Point the host's workspace watcher at `session`'s workspace, or park it
/// (`fs.unwatch`) when the panel no longer needs one. Parking is best-effort,
/// but a rejected watch is surfaced because it means live updates are off.
fn watch_workspace(
  dispatch : @cmd.Emit[Msg],
  channel~ : @interop.ChannelId,
  watched : WatchedPaths?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      if watched is None {
        ignore(
          @interop.bridge_request_in_order(
            channel,
            @commands.fs_unwatch,
            @protocol.EmptyPayload::NoPayload,
          ) catch {
            _ => return
          },
        )
      } else if watched is Some(watched) {
        ignore(
          @interop.bridge_request_in_order(channel, @commands.fs_watch, {
            session: watched.owner.session,
            workspace: watched.workspace.map(value => value.0),
            files: Some(watched.files.map(path => path.0)),
            directories: Some(watched.directories.map(path => path.0)),
          }) catch {
            error => {
              scheduler.add(
                dispatch(
                  FileWatchFailed(
                    owner=watched.owner,
                    message="File watching failed: \{@interop.bridge_error_text(error)}",
                  ),
                ),
              )
              return
            }
          },
        )
      }
    })
  })
}

///|
test "child_path joins entry names onto their parent directory" {
  assert_eq(child_path(@pathx.Relative::root(), "src").0, "src")
  assert_eq(child_path(@pathx.Relative::root(), "moon.mod").0, "moon.mod")
  assert_eq(child_path(Relative("src"), "main.mbt").0, "src/main.mbt")
  assert_eq(child_path(Relative("src/lib"), "util.mbt").0, "src/lib/util.mbt")
}

///|
test "language_id maps known extensions and falls back to plain text" {
  assert_eq(language_id("main.mbt"), "moonbit")
  assert_eq(language_id("pkg.generated.mbti"), "moonbit")
  assert_eq(language_id("README.mbt.md"), "moonbit")
  assert_eq(language_id("bundle.js"), "javascript")
  assert_eq(language_id("config.mjs"), "javascript")
  assert_eq(language_id("moon.mod.json"), "json")
  assert_eq(language_id("notes.txt"), "plaintext")
  assert_eq(language_id("LICENSE"), "plaintext")
}

///|
test "typed directory rows build full relative paths" {
  guard FileEntry::from_reply(
      { name: "src", is_dir: true },
      @pathx.Relative::root(),
    )
    is Some(entry) else {
    fail("valid directory row was rejected")
  }
  assert_eq(entry.name, "src")
  assert_eq(entry.path.0, "src")
  assert_true(entry.is_dir)
  assert_true(
    FileEntry::from_reply({ name: "", is_dir: false }, @pathx.Relative::root())
    is None,
  )
}

///|
test "typed file replies map to viewer content" {
  assert_true(
    FileContent::from_reply(
      @protocol.Content(content="hello", absolute="/ws/a.mbt", sig="12:34"),
    )
    is Some(
      Content(content="hello", absolute=Absolute("/ws/a.mbt"), sig="12:34")
    ),
  )
  assert_true(FileContent::from_reply(@protocol.Binary) is Some(Binary))
  assert_true(FileContent::from_reply(@protocol.Oversized) is Some(Oversized))
  assert_true(
    FileContent::from_reply(
      @protocol.Content(content="x", absolute="", sig="1:2"),
    )
    is None,
  )
}
