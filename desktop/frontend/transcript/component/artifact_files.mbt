///|
#derive(Eq)
priv struct ArtifactOwner {
  channel : @interop.ChannelId?
  session : String
  workspace : @common.Uri?
  checkout : @common.Uri?
  archived : Bool
  followup_enabled : Bool
}

///|
/// An action requested from the preview of a particular artifact.
pub(all) enum ArtifactInteraction {
  AttachState(@mention_context.ArtifactSnapshot)
  RequestFollowup(
    prompt~ : String,
    title~ : String,
    snapshot~ : @mention_context.ArtifactSnapshot?
  )
}

///|
fn Input::artifact_owner(self : Input) -> ArtifactOwner {
  {
    channel: self.focused,
    session: self.active_session,
    workspace: self.current_project,
    checkout: self.root,
    archived: self.archived,
    followup_enabled: self.source is OpenSeek && !self.archived,
  }
}

///|
fn ArtifactOwner::key(self : ArtifactOwner) -> String {
  Json([
    self.channel.map(channel => channel.uri_authority()).unwrap_or(""),
    self.workspace.map(workspace => workspace.to_string()).unwrap_or(""),
    self.checkout.map(root => root.to_string()).unwrap_or(""),
    self.session,
    self.archived.to_string(),
    self.followup_enabled.to_string(),
  ]).stringify()
}

///|
#derive(Eq)
priv enum ArtifactFileState {
  LoadingArtifact
  ReadyArtifact(String)
  FailedArtifact(String)
}

///|
#derive(Eq)
priv struct ArtifactFileCache(Map[String, ArtifactFileState])

///|
fn ArtifactFileCache::empty() -> ArtifactFileCache {
  ArtifactFileCache(Map([]))
}

///|
fn artifact_file_view(
  file : @workspace_file_ref.WorkspaceFileRef,
  locale : @i18n.Locale,
  open : @cmd.Emit[String],
  owner : ArtifactOwner,
) -> @html.Html {
  let card = @markdown.workspace_file_card(
    locale,
    file,
    Some(path => open(path)),
  )
  if !(file.extension is Some("html" | "htm" | "svg")) {
    return card
  }
  @html.div(
    class="chat-artifact-file",
    attrs=@html.Attrs::build()
      .data_set("transcript-artifact", file.path)
      .data_set("artifact-owner", owner.key()),
    [
      @html.div(
        attrs=@html.Attrs::build().data_set("artifact-fallback", ""),
        card,
      ),
      @html.iframe(
        class="chat-artifact-frame",
        title=file.name,
        sandbox="allow-scripts",
        style=["display:none", "width:100%", "height:420px", "border:0"],
        attrs=@html.Attrs::build().referrerpolicy("no-referrer"),
      ),
      @html.button(
        type_="button",
        class="chat-artifact-context",
        style=["display:none"],
        disabled=owner.archived,
        match locale {
          SimplifiedChinese => "携带当前状态提问"
          TraditionalChinese => "帶著目前設定提問"
          Japanese => "現在の設定で質問する"
          Spanish => "Preguntar con estos ajustes"
          _ => "Ask with current settings"
        },
      ),
    ],
  )
}

///|
fn discover_artifact_files(
  surface : @interop.ChatSurface,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      guard transcript_root(surface) is Some(transcript) else { return }
      for element in transcript.query_selector_all("[data-transcript-artifact]") {
        if element.get_attribute("data-transcript-artifact") is Some(reference) {
          scheduler.add(emit(ArtifactRequested(reference)))
        }
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn ArtifactFileCache::begin_read(
  self : ArtifactFileCache,
  owner : ArtifactOwner,
  reference : String,
  emit : @cmd.Emit[Msg],
) -> (ArtifactFileCache, @cmd.Cmd) {
  if self.0.contains(reference) {
    return (self, @cmd.none)
  }
  let files = self.0.copy()
  guard owner.channel is Some(channel) &&
    @transcript.file_target(
      owner.workspace,
      owner.checkout,
      owner.session,
      owner.archived,
      reference,
    )
    is Some((root, path)) &&
    @resource.path_for(root, channel) is Some(root) else {
    files[reference] = FailedArtifact("Artifact unavailable")
    return (ArtifactFileCache(files), @cmd.none)
  }
  files[reference] = LoadingArtifact
  let command = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result = Ok(
        @interop.bridge_request(channel, @commands.fs_read_file, {
          path,
          root: Some(root),
          max_bytes: Some(8 * 1024 * 1024),
        }),
      ) catch {
        error => Err(error.to_string())
      }
      scheduler.add(emit(ArtifactResolved(owner, reference, result)))
    })
    |> ignore
  })
  (ArtifactFileCache(files), command)
}

///|
fn ArtifactFileCache::settle(
  self : ArtifactFileCache,
  reference : String,
  result : Result[@protocol.ReadFileReply, String],
) -> ArtifactFileCache {
  guard self.0.get(reference) is Some(LoadingArtifact) else { return self }
  let files = self.0.copy()
  files[reference] = match result {
    Ok(@protocol.Content(content~, ..)) => ReadyArtifact(content)
    Ok(@protocol.Oversized) =>
      FailedArtifact("File exceeds the 8 MiB preview limit")
    Ok(_) => FailedArtifact("Artifact preview unavailable")
    Err(error) => FailedArtifact(error)
  }
  ArtifactFileCache(files)
}

///|
fn ArtifactFileCache::apply_after_render(
  self : ArtifactFileCache,
  owner : ArtifactOwner,
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      let key = owner.key()
      for reference, state in self.0 {
        settle_artifact_frames(
          reference,
          state,
          key,
          followup_enabled=owner.followup_enabled,
        )
      }
    },
    kind=@cmd.after_render,
  )
}
