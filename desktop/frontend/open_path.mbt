///|
/// Navigation data stays in the frontend while the host classifies the file.
/// A composer action may target a parked conversation; return_to records the
/// conversation that must remain on screen when that reply arrives.
priv struct FileOpenContext {
  owner : @interop.ConversationKey
  generation : Int
  range : @common.Range?
  annotation : String?
  return_to : @interop.ConversationKey?
}

///|
fn FileOpenContext::new(
  owner : @interop.ConversationKey,
  generation : Int,
  range? : @common.Range,
  annotation? : String,
  return_to? : @interop.ConversationKey,
) -> FileOpenContext {
  { owner, generation, range, annotation, return_to, }
}

///|
fn request_open_path(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  path : String,
  range : @common.Range?,
  annotation? : String,
  return_to? : @interop.ConversationKey,
) -> (@cmd.Cmd, Model) {
  guard model.active_checkout() is Some(active) &&
    active.placement is Some(placement) &&
    placement.is_ready() &&
    placement.checkout_root() is Some(cwd) else {
    return (@cmd.none, model)
  }
  let model = if return_to is Some(owner) && owner != active.owner {
    model
  } else {
    let dock = @dock.sync(model.dock, active.owner)
    {
      ..model,
      dock,
      file_panel: model.file_panel.prepare_owner(
        active.owner,
        @dock.file_paths(dock),
      ),
    }
  }
  let model = model.begin_editor_navigation()
  let context = FileOpenContext::new(
    active.owner,
    model.file_panel.file_link_generation,
    range?,
    annotation?,
    return_to?,
  )
  (
    open_file(dispatch, context, cwd, path, preview_browser=model.is_desktop),
    model,
  )
}

///|
fn finish_open_path(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  context : FileOpenContext,
  reply : @protocol.OpenPathReply,
) -> (@cmd.Cmd, Model) {
  guard context.generation == model.file_panel.file_link_generation &&
    model.active_checkout() is Some(active) &&
    (context.owner == active.owner || context.return_to == Some(active.owner)) else {
    return (@cmd.none, model)
  }
  let selected = if context.owner == active.owner {
    model
  } else {
    // A background composer action can only select an existing conversation.
    guard model.screen is Chat &&
      model.find_conversation(context.owner.channel, context.owner.session)
      is Some(_) else {
      return (@cmd.none, model)
    }
    {
      ..model,
      focused: context.owner.channel,
      active_session: context.owner.session,
    }
  }
  guard selected.active_checkout() is Some(target) &&
    target.owner == context.owner &&
    target.placement is Some(placement) &&
    placement.is_ready() else {
    return (@cmd.none, model)
  }
  let (cmd, opened) = match reply {
    Editor(target) => {
      let range = if context.range is Some(_) {
        context.range
      } else if target.line is Some(line) {
        let column = target.column.unwrap_or(1)
        Some(@common.Range(line, column, line, column))
      } else {
        None
      }
      show_editor_at(
        dispatch,
        selected,
        target.path,
        range,
        file_link_generation=context.generation,
        annotation?=context.annotation,
      )
    }
    Browser(path) => show_browser_path(dispatch, selected, path)
    Directory(target) =>
      reveal_local_directory(dispatch, selected, Relative(target.path))
    Refused(message) => selected.notify_error(dispatch, message)
    Opened => (@cmd.none, selected)
  }
  (
    cmd,
    { ..opened, focused: model.focused, active_session: model.active_session, },
  )
}

///|
/// Open (or refocus) the editor side-panel on `path`, revealing `range` when
/// given — the shared tail of a composer chip's and a transcript chip's jump.
/// Absolute links already name their document; relative chips are resolved
/// against the current checkout before entering the dock and document table.
fn show_editor_at(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  path : String,
  range : @common.Range?,
  file_link_generation~ : Int,
  annotation? : String,
) -> (@cmd.Cmd, Model) {
  let ctx = file_ctx(model)
  // Chip/transcript jumps call the file-editor package directly rather than
  // passing through its guarded message dispatcher. Keep them parked too: the
  // dock must not grow a loading tab, nor may a host read start, while checkout
  // placement is unresolved or missing.
  guard ctx.placement is Some(placement) && placement.is_ready() else {
    return (@cmd.none, model)
  }
  let owner = ctx.owner
  let femit = dispatch.map(msg => FileEditor(msg))
  // Park/restore the strip for a conversation switch up front, and re-root
  // the file subsystem when its cached tree belongs to another conversation;
  // otherwise `sync_file_panel`'s post-dispatch pass would see a session
  // mismatch and wipe the freshly opened tab below. A re-rooted document
  // table is seeded from the restored strip (identities only), exactly like
  // `@fileeditor.sync`'s own re-root.
  let dock = @dock.sync(model.dock, owner)
  let panel = model.file_panel.prepare_owner(owner, @dock.file_paths(dock))
  let resource = match @resource.of_path(ctx.owner.channel, path) {
    Some(resource) => Some(resource)
    None =>
      model
      .active_relative_path(path)
      .bind(relative => model.workspace_resource(relative))
  }
  guard resource is Some(resource) else { return (@cmd.none, model) }
  let had_active = @dock.active_file(dock) is Some(_)
  // An explicit open while the picker is the active tab fulfills it, the
  // same as a pick from its tree.
  let dock = if dock.active is Some(FilePicker) {
    @dock.resolve_pick(dock, File(path=resource))
  } else {
    @dock.open_file(dock, resource)
  }
  let model = {
    ..model,
    dock,
    file_panel: panel,
    right_panel_open: true,
    right_panel_menu_open: false,
  }
  // Owner preparation can advance the request epoch; read with the new one.
  let ctx = file_ctx(model)
  let (cmd, panel) = @fileeditor.open_file(
    femit,
    panel,
    ctx,
    resource,
    file_link_generation~,
    range~,
    annotation?,
    had_active~,
  )
  (cmd, { ..model, file_panel: panel, })
}

///|
fn show_browser_path(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  path : String,
) -> (@cmd.Cmd, Model) {
  guard model.is_desktop &&
    model.active_checkout() is Some(active) &&
    active.owner.channel is Local else {
    return (@cmd.none, model)
  }
  let dock = @dock.sync(model.dock, active.owner)
  let url = @uri.file_url(path)
  let reuse = for tab in dock.tabs {
    if tab is Browser(id~) &&
      @preview.page(model.preview, id) is Some(page) &&
      page.url == Some(url) {
      break Some(id)
    }
  } nobreak {
    None
  }
  let (preview, id) = match reuse {
    Some(id) => (@preview.navigate(model.preview, id, url), id)
    None => @preview.open_page(model.preview, url~)
  }
  let dock = if dock.active is Some(FilePicker) {
    @dock.resolve_pick(dock, Browser(id~))
  } else {
    @dock.open_browser(dock, id)
  }
  (
    browser_open(dispatch, id, url, model.theme.is_dark(model.system_dark)),
    {
      ..model,
      preview,
      dock,
      browser_pane: { shown: None, rect: None, geo: None, },
      right_panel_open: true,
      right_panel_menu_open: false,
    },
  )
}
