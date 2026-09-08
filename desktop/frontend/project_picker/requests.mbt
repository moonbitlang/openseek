// The picker's data source: ask the host to list one location's
// subdirectories. Unlike the file panel's `read_directory` this is not
// scoped to a conversation's workspace — its whole purpose is choosing a
// new workspace anywhere on the host, and the gateway's token already gates
// full host access. The frontend renders the picker itself, so desktop and
// browser share one flow and the directories shown are always the host
// machine's.

///|
/// Ask the host to list one location. `path` "" starts at the host's home
/// directory; "/" is a Windows host's drive list. `generation` rides along
/// on the reply with `channel`, so the state machine can drop answers to
/// superseded navigations and to a picker that was reopened for another
/// device.
fn browse(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  path : String,
  generation~ : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(channel, @commands.fs_browse, {
        path: match path.trim() {
          "" => None
          value => Some(value.to_owned())
        },
      }) catch {
        error => {
          scheduler.add(emit(browse_failure(channel, error, generation~)))
          return
        }
      }
      scheduler.add(
        emit(reply_message(channel, reply, generation~, drives=true)),
      )
    })
  })
}

///|
/// Ask the host to create one child of the current directory. A successful
/// reply is the new directory's listing, so creation and navigation share the
/// state machine's existing channel/generation fence.
fn create_folder(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  parent : String,
  name : String,
  generation~ : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        channel,
        @commands.fs_create_directory,
        { parent, name, },
      ) catch {
        error if @interop.bridge_failure(error) is Unknown => {
          // The host may have created the folder before the reply was lost.
          // Re-listing the intended target makes that outcome converge while
          // an explicit "already exists" reply remains a normal refusal.
          let message = @interop.bridge_error_text(error)
          @interop.bridge_request(channel, @commands.fs_browse, {
            path: Some(parent.picker_child_path(name)),
          }) catch {
            _ => {
              scheduler.add(emit(Failed(channel~, message~, generation~)))
              return
            }
          }
        }
        error => {
          scheduler.add(emit(browse_failure(channel, error, generation~)))
          return
        }
      }
      scheduler.add(
        emit(reply_message(channel, reply, generation~, drives=false)),
      )
    })
  })
}

///|
/// The state machine's failure result for one host error, carrying the
/// channel and generation the request was fenced with.
fn browse_failure(
  channel : @interop.ChannelId,
  error : Error,
  generation~ : Int,
) -> Msg {
  Failed(channel~, message=@interop.bridge_error_text(error), generation~)
}

///|
/// Turn either browse-shaped host reply into the one state-machine result
/// path. Only an ordinary browse may return the Windows drive list.
fn reply_message(
  channel : @interop.ChannelId,
  reply : @protocol.BrowseDirectoryReply,
  generation~ : Int,
  drives~ : Bool,
) -> Msg {
  match reply {
    Listing(path~, entries~, ..) =>
      Loaded(
        channel~,
        location=Directory(path),
        entries=entries.filter(name => !name.is_empty()),
        generation~,
      )
    Drives(entries~) if drives =>
      Loaded(
        channel~,
        location=DriveList,
        entries=entries.filter(name => !name.is_empty()),
        generation~,
      )
    Drives(_) =>
      Failed(
        channel~,
        message="created directory returned a drive list",
        generation~,
      )
    BrowseError(message) => Failed(channel~, message~, generation~)
  }
}

///|
/// The protocol path for one child of a directory the picker already
/// loaded. Resource URI paths always use `/`, including Windows drive
/// resources such as `/C:/code`.
fn String::picker_child_path(self : String, name : String) -> String {
  if self.has_suffix("/") {
    self + name
  } else {
    self + "/" + name
  }
}
