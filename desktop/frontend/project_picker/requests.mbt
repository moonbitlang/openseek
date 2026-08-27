// The picker's data source: ask the host to list one location's
// subdirectories. Unlike the file panel's `read_directory` this is not
// scoped to a conversation's workspace — its whole purpose is choosing a
// new workspace anywhere on the host, and the gateway's token already gates
// full host access. The frontend renders the picker itself, so desktop and
// browser share one flow and the directories shown are always the host
// machine's.

///|
/// Ask the host to list one location. `path` "" starts at the host's home
/// directory; "/" is a Windows host's drive list. The request UUID rides on
/// the reply, so the state machine can drop answers to superseded navigations
/// and to a picker that has been reopened.
fn browse(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  path : String,
  request_id~ : String,
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
          scheduler.add(
            emit(Failed(message=@interop.bridge_error_text(error), request_id~)),
          )
          return
        }
      }
      scheduler.add(emit(reply_message(reply, request_id~, drives=true)))
    })
  })
}

///|
/// Ask the host to create one child of the current directory. A successful
/// reply is the new directory's listing, so creation and navigation share the
/// state machine's existing request UUID fence.
fn create_folder(
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  parent : String,
  name : String,
  request_id~ : String,
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
              scheduler.add(emit(Failed(message~, request_id~)))
              return
            }
          }
        }
        error => {
          scheduler.add(
            emit(Failed(message=@interop.bridge_error_text(error), request_id~)),
          )
          return
        }
      }
      scheduler.add(emit(reply_message(reply, request_id~, drives=false)))
    })
  })
}

///|
/// Turn either browse-shaped host reply into the one state-machine result
/// path. Only an ordinary browse may return the Windows drive list.
fn reply_message(
  reply : @protocol.BrowseDirectoryReply,
  request_id~ : String,
  drives~ : Bool,
) -> Msg {
  match reply {
    Listing(path~, entries~, ..) =>
      Loaded(
        location=Directory(path),
        entries=entries.filter(name => !name.is_empty()),
        request_id~,
      )
    Drives(entries~) if drives =>
      Loaded(
        location=DriveList,
        entries=entries.filter(name => !name.is_empty()),
        request_id~,
      )
    Drives(_) =>
      Failed(message="created directory returned a drive list", request_id~)
    BrowseError(message) => Failed(message~, request_id~)
  }
}

///|
/// The protocol path for one child of a directory the picker already
/// loaded. Host paths use `/` in this protocol, including Windows drive
/// paths such as `/C:/code`.
fn String::picker_child_path(self : String, name : String) -> String {
  if self.has_suffix("/") {
    self + name
  } else {
    self + "/" + name
  }
}
