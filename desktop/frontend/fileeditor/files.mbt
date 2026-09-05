// The editor side-panel's filesystem calls: list a directory and read a file
// under the active conversation's concrete root, through the host's
// `read_directory` / `read_file` ops. Each request sends the fully composed
// absolute target. Each reply carries the full conversation
// owner and path it answers so a reply that lost a device/session switch can
// be discarded.

///|
/// List `path` (relative to `root`; "" is the root) and
/// fold the entries back as `DirLoaded`.
fn read_directory(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  epoch : Int,
  path : @pathx.Relative,
  root~ : @common.Uri?,
) -> @cmd.Cmd {
  guard root is Some(root) && @resource.belongs_to(root, owner.channel) else {
    return @cmd.none
  }
  let target = @resource.join_relative(root, path)
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.fs_read_directory,
        { path: target.path, },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              DirFailed(
                owner~,
                epoch~,
                path~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      let entries = reply.entries.filter_map(entry => {
        FileEntry::from_reply(entry, path)
      })
      scheduler.add(dispatch(DirLoaded(owner~, epoch~, path~, entries~)))
    })
  })
}

///|
/// Load the bounded workspace snapshot used by file-completion consumers.
/// The request carries this panel incarnation's owner and epoch so the update
/// loop can reject a reply that outlived a conversation or worktree switch.
fn list_files(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  epoch : Int,
  root~ : @common.Uri?,
) -> @cmd.Cmd {
  @files.Request(owner.channel, owner.session, root).run(
    (files, truncated) => {
      dispatch(FilesIndexed(owner~, epoch~, files~, truncated~))
    },
    () => dispatch(FileIndexFailed(owner~, epoch~)),
  )
}

///|
/// Read `path` and fold its contents back as `FileLoaded`. `name` is the
/// entry's display name, forwarded for the viewer's title and language guess.
/// `range`, when present (a symbol jump's target), is forwarded for the
/// viewer to reveal and select once loaded. A transcript link also carries
/// its click generation so a late reply cannot move the viewer after a newer
/// navigation. Its content may still settle a loading background tab so the
/// tab is not stranded. `annotation` (an annotation chip's comment) rides
/// along the same way, re-shown as an editor bubble over that range.
fn read_file(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  epoch : Int,
  path : @pathx.Relative,
  name : String,
  file_link_generation? : Int,
  review_generation? : Int,
  range~ : @common.Range?,
  annotation? : String,
  root~ : @common.Uri?,
) -> @cmd.Cmd {
  guard root is Some(root) && @resource.belongs_to(root, owner.channel) else {
    // Settle the request through the same typed failure path as an async
    // bridge rejection. Review-loading tabs deliberately do not start an
    // untagged duplicate read on activation, so a silent no-op here would
    // otherwise strand the paired working side during a host migration.
    return dispatch(
      FileFailed(
        owner~,
        epoch~,
        path~,
        file_link_generation~,
        review_generation~,
        message="file root moved to another host before file read",
      ),
    )
  }
  let target = @resource.join_relative(root, path)
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.fs_read_file,
        { path: target.path, root: None, },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              FileFailed(
                owner~,
                epoch~,
                path~,
                file_link_generation~,
                review_generation~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      match FileContent::from_reply(reply, owner.channel) {
        Some(file) =>
          scheduler.add(
            dispatch(
              FileLoaded(
                owner~,
                epoch~,
                path~,
                name~,
                file~,
                file_link_generation~,
                review_generation~,
                range~,
                annotation~,
              ),
            ),
          )
        None =>
          scheduler.add(
            dispatch(
              FileFailed(
                owner~,
                epoch~,
                path~,
                file_link_generation~,
                review_generation~,
                message="could not read file",
              ),
            ),
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
fn FileContent::from_reply(
  reply : @protocol.ReadFileReply,
  channel : @interop.ChannelId,
) -> FileContent? {
  match reply {
    @protocol.Binary => Some(Binary)
    @protocol.Oversized => Some(Oversized)
    // Supported raster files carry display bytes for transcript rendering.
    // The text editor still presents them through its ordinary binary notice.
    @protocol.BinaryContent(..) => Some(Binary)
    @protocol.Content(content~, absolute~, sig~) => {
      // Bind the backend resource path to the device that produced the reply.
      guard @resource.of_path(channel, absolute) is Some(absolute) else {
        return None
      }
      Some(Content(content~, absolute~, sig~))
    }
  }
}

///|
/// Read one file for a cross-resource Peek preview without entering the tab
/// state machine. This deliberately reuses the same `fs.read_file` wire op
/// and decoder as ordinary file opening, so binary/oversized policy and
/// absolute-path addressing stay identical. Failures are unavailable previews,
/// not panel errors, and therefore return `None` to the resolver.
async fn read_file_snapshot(
  owner : @interop.ConversationKey,
  path : @pathx.Relative,
  root~ : @common.Uri?,
) -> FileContent? {
  guard root is Some(root) && @resource.belongs_to(root, owner.channel) else {
    return None
  }
  let target = @resource.join_relative(root, path)
  let reply = @interop.bridge_request(owner.channel, @commands.fs_read_file, {
    path: target.path,
    root: None,
  }) catch {
    _ => return None
  }
  FileContent::from_reply(reply, owner.channel)
}

///|
/// Stat the open tabs' files and fold the signatures back as `StatsLoaded`.
/// Best-effort: a failed call is dropped — the next change push retries.
fn stat_files(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  epoch : Int,
  paths : Array[@pathx.Relative],
  root~ : @common.Uri?,
) -> @cmd.Cmd {
  guard root is Some(root) && @resource.belongs_to(root, owner.channel) else {
    return @cmd.none
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // Stat snapshots mutate cached document/review state. Keep their host
      // observations in issue order, while `epoch` fences a placement or
      // conversation boundary that an already-issued request outlives.
      let reply = @interop.bridge_request_in_order(
        owner.channel,
        @commands.fs_stat_files,
        { paths: paths.map(path => @resource.join_relative(root, path).path), },
      ) catch {
        _ => return
      }
      let stats : Array[FileStat] = []
      for stat in reply.stats {
        guard @resource.of_path(owner.channel, stat.path) is Some(absolute) &&
          @resource.relative_to(absolute, root) is Some(path) else {
          continue
        }
        stats.push({ path, signature: stat.signature, })
      }
      scheduler.add(dispatch(StatsLoaded(owner~, epoch~, stats~)))
    })
  })
}

///|
/// Point the host's watcher at the selected absolute root, or park it
/// (`fs.unwatch`) when the panel no longer needs one. Parking is best-effort,
/// but a rejected watch is surfaced because it means live updates are off.
fn watch_workspace(
  dispatch : @cmd.Emit[Msg],
  channel~ : @interop.ChannelId,
  generation~ : String,
  watched : WatchedPaths?,
) -> @cmd.Cmd {
  if watched is Some(watched) && !@resource.belongs_to(watched.root, channel) {
    return @cmd.none
  }
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
            path: watched.root.path,
            files: watched.files.map(path => path.0),
            directories: watched.directories.map(path => path.0),
            recursive: Some(watched.recursive),
            generation,
          }) catch {
            error => {
              scheduler.add(
                dispatch(
                  FileWatchFailed(
                    channel=watched.owner.channel,
                    root=watched.root,
                    generation~,
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
test "a cross-host file read settles through its generation-fenced failure" {
  let seen : Ref[Msg?] = Ref(None)
  let dispatch = @cmd.Emit(message => {
    seen.val = Some(message)
    @cmd.none
  })
  guard @resource.of_path(@interop.ChannelId::Local, "/work") is Some(workspace) else {
    fail("test workspace resource was not absolute")
  }
  ignore(
    read_file(
      dispatch,
      { channel: @interop.ChannelId::Remote("other"), session: "remote-test", },
      0,
      @pathx.Relative("src/main.mbt"),
      "main.mbt",
      review_generation=7,
      range=None,
      root=Some(workspace),
    ),
  )
  assert_true(
    seen.val
    is Some(
      FileFailed(
        owner={ channel: @interop.ChannelId::Remote("other"), .. },
        epoch=0,
        path=@pathx.Relative("src/main.mbt"),
        file_link_generation=None,
        review_generation=Some(7),
        message="file root moved to another host before file read"
      )
    ),
  )
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
  assert_eq(language_id("moon.pkg"), "moonbit-config")
  assert_eq(language_id("moon.mod"), "moonbit-config")
  assert_eq(language_id("main.mbt"), "moonbit")
  assert_eq(language_id("pkg.generated.mbti"), "moonbit")
  assert_eq(language_id("README.mbt.md"), "moonbit")
  assert_eq(language_id("run.mbtx"), "mbtx")
  assert_eq(language_id("bundle.js"), "javascript")
  assert_eq(language_id("config.mjs"), "javascript")
  assert_eq(language_id("moon.mod.json"), "json")
  assert_eq(language_id("notmoon.pkg"), "plaintext")
  assert_eq(language_id("notes.txt"), "plaintext")
  assert_eq(language_id("LICENSE"), "plaintext")
}

///|
test "typed directory rows build full relative paths" {
  guard FileEntry::from_reply(
      { name: "src", is_dir: true, },
      @pathx.Relative::root(),
    )
    is Some(entry) else {
    fail("valid directory row was rejected")
  }
  assert_eq(entry.name, "src")
  assert_eq(entry.path.0, "src")
  assert_true(entry.is_dir)
  assert_true(
    FileEntry::from_reply({ name: "", is_dir: false, }, @pathx.Relative::root())
    is None,
  )
}

///|
test "typed file replies map to viewer content" {
  guard FileContent::from_reply(
      @protocol.Content(content="hello", absolute="/ws/a.mbt", sig="12:34"),
      @interop.ChannelId::Local,
    )
    is Some(Content(content~, absolute~, sig~)) else {
    fail("valid text reply was rejected")
  }
  assert_eq(content, "hello")
  assert_eq(absolute.path, "/ws/a.mbt")
  assert_eq(@resource.channel(absolute), Some(@interop.ChannelId::Local))
  assert_eq(sig, "12:34")
  assert_true(
    FileContent::from_reply(@protocol.Binary, @interop.ChannelId::Local)
    is Some(Binary),
  )
  assert_true(
    FileContent::from_reply(@protocol.Oversized, @interop.ChannelId::Local)
    is Some(Oversized),
  )
  assert_true(
    FileContent::from_reply(
      @protocol.Content(content="x", absolute="", sig="1:2"),
      @interop.ChannelId::Local,
    )
    is None,
  )
  assert_true(
    FileContent::from_reply(
      @protocol.Content(content="x", absolute="relative.mbt", sig="1:2"),
      @interop.ChannelId::Local,
    )
    is None,
  )
}
