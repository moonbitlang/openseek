///|
priv struct ArtifactOwner {
  channel : @interop.ChannelId?
  session : String
  workspace : @common.Uri?
  archived : Bool
} derive(Eq)

///|
fn Input::artifact_owner(self : Input) -> ArtifactOwner {
  {
    channel: self.focused,
    session: self.active_session,
    workspace: self.current_project,
    archived: self.archived,
  }
}

///|
fn ArtifactOwner::key(self : ArtifactOwner) -> String {
  Json([
    self.channel.map(channel => channel.uri_authority()).unwrap_or(""),
    self.workspace.map(workspace => workspace.to_string()).unwrap_or(""),
    self.session,
    self.archived.to_string(),
  ]).stringify()
}

///|
priv enum ArtifactFileState {
  LoadingArtifact
  ReadyArtifact(String)
  FailedArtifact(String)
} derive(Eq)

///|
priv struct ArtifactFileCache(Map[String, ArtifactFileState]) derive(Eq)

///|
fn ArtifactFileCache::empty() -> ArtifactFileCache {
  ArtifactFileCache(Map([]))
}

///|
fn artifact_file_view(
  reference : String,
  _title : String,
  locale : @i18n.Locale,
  open : @cmd.Emit[String],
  owner : ArtifactOwner,
) -> @html.Html {
  let reference = if reference.has_prefix("artifact://") {
    reference
  } else {
    "artifact://" + reference
  }
  guard @workspace_file_ref.parse(
      @workspace_file_ref.FenceLanguage,
      reference,
      closed=true,
    )
    is Some(file) else {
    return @html.nothing
  }
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
      .data_set("transcript-artifact", reference)
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
fn discover_artifact_files(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      for
        element in @dom.document().query_selector_all(
          "[data-transcript-artifact]",
        ) {
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
  guard !self.0.contains(reference) &&
    @workspace_file_ref.artifact_path(reference) is Some(_) else {
    return (self, @cmd.none)
  }
  let files = self.0.copy()
  guard owner.channel is Some(channel) &&
    owner.workspace is Some(workspace) &&
    @resource.path_for(workspace, channel) is Some(workspace) else {
    files[reference] = FailedArtifact("Artifact unavailable")
    return (ArtifactFileCache(files), @cmd.none)
  }
  files[reference] = LoadingArtifact
  let command = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result = Ok(
        @interop.bridge_request(channel, @commands.session_artifact_file, {
          session: owner.session,
          workspace,
          archived: owner.archived,
          reference,
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
  result : Result[@protocol.ArtifactFileReply, String],
) -> ArtifactFileCache {
  guard self.0.get(reference) is Some(LoadingArtifact) else { return self }
  let files = self.0.copy()
  files[reference] = match result {
    Ok({ content: Some(content), .. }) => ReadyArtifact(content)
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
      for reference, state in self.0 {
        match state {
          ReadyArtifact(content) =>
            settle_artifact_frame(reference, content, "", owner.key(), true)
          FailedArtifact(error) =>
            settle_artifact_frame(reference, "", error, owner.key(), false)
          LoadingArtifact =>
            settle_artifact_frame(reference, "", "", owner.key(), false)
        }
      }
    },
    kind=@cmd.after_render,
  )
}

///|
extern "js" fn settle_artifact_frame(
  reference : String,
  content : String,
  error : String,
  owner : String,
  ready : Bool,
) =
  #|(reference, content, error, owner, ready) => {
  #|  for (const node of document.querySelectorAll('[data-transcript-artifact]')) {
  #|    if (node.dataset.transcriptArtifact !== reference || node.dataset.artifactOwner !== owner) continue;
  #|    const frame = node.querySelector('iframe');
  #|    if (!frame || (frame.dataset.artifactLoaded === owner && frame.dataset.artifactReference === reference)) continue;
  #|    const button = node.querySelector('.chat-artifact-context');
  #|    if (frame.dataset.artifactLoaded) { frame.removeAttribute('srcdoc'); delete frame.dataset.artifactLoaded; delete frame.dataset.artifactReference; delete frame.dataset.artifactToken; delete frame.__artifactSnapshot; frame.style.display = 'none'; if (button) button.style.display = 'none'; }
  #|    const fallback = node.querySelector('[data-artifact-fallback]');
  #|    if (error && node.title !== error) node.title = error;
  #|    if (!ready) { if (fallback && fallback.style.display === 'none') fallback.style.display = ''; continue; }
  #|    const policy = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'";
  #|    const token = Array.from(crypto.getRandomValues(new Uint8Array(16)), byte => byte.toString(16).padStart(2, '0')).join('');
  #|    frame.dataset.artifactToken = token;
  #|    delete frame.__artifactSnapshot;
  #|    if (button) button.style.display = 'none';
  #|    const bridge = '<script>(()=>{const token=' + JSON.stringify(token) + ';Object.defineProperty(window,"openseekArtifact",{value:Object.freeze({setState:(title,state)=>{const packet={type:"openseek-artifact-state",version:1,token,title,state};try{parent.postMessage(packet,"*")}catch{parent.postMessage({...packet,title:"",state:null},"*")}}})})})();<\/script>';
  #|    const resize = '<script>(()=>{const send=()=>parent.postMessage({type:"openseek-artifact-height",height:Math.ceil(document.body?.scrollHeight||420)},"*");addEventListener("load",()=>{new ResizeObserver(send).observe(document.body);send()})})();<\/script>';
  #|    frame.srcdoc = '<meta http-equiv="Content-Security-Policy" content="' + policy + '"><meta name="referrer" content="no-referrer">' + bridge + content + resize;
  #|    frame.dataset.artifactLoaded = owner;
  #|    frame.dataset.artifactReference = reference;
  #|    frame.style.display = 'block';
  #|    if (fallback) fallback.style.display = 'none';
  #|  }
  #|}

///|
extern "js" fn artifact_frame_listener(
  changed : () -> Unit,
  selected : (String, String, String) -> Unit,
) -> () -> Unit =
  #|(changed, selected) => {
  #|  const boundedJSON = value => {
  #|    let nodes = 0, units = 0;
  #|    const valid = (value, depth) => {
  #|      if (++nodes > 2048 || depth > 20) return false;
  #|      if (value === null || typeof value === 'boolean') return true;
  #|      if (typeof value === 'number') return Number.isFinite(value);
  #|      if (typeof value === 'string') { units += value.length; return units <= 8192; }
  #|      if (typeof value !== 'object') return false;
  #|      for (const key of Object.keys(value)) {
  #|        units += key.length;
  #|        if (units > 8192 || !valid(value[key], depth + 1)) return false;
  #|      }
  #|      return true;
  #|    };
  #|    return valid(value, 0);
  #|  };
  #|  const listener = event => {
  #|    const data = event.data;
  #|    if (!data) return;
  #|    for (const frame of document.querySelectorAll('#transcript .chat-artifact-frame')) {
  #|      if (frame.contentWindow !== event.source) continue;
  #|      if (data.type === 'openseek-artifact-height' && Number.isFinite(data.height)) {
  #|        const height = Math.max(64, Math.min(2000, Math.ceil(data.height)));
  #|        if (frame.style.height !== height + 'px') { frame.style.height = height + 'px'; changed(); }
  #|      } else if (data.type === 'openseek-artifact-state' && data.version === 1 && typeof data.token === 'string' && data.token === frame.dataset.artifactToken) {
  #|        const node = frame.closest('[data-transcript-artifact]');
  #|        if (!node || frame.dataset.artifactLoaded !== node.dataset.artifactOwner || frame.dataset.artifactReference !== node.dataset.transcriptArtifact) return;
  #|        const button = frame.closest('[data-transcript-artifact]')?.querySelector('.chat-artifact-context');
  #|        const clear = () => { delete frame.__artifactSnapshot; if (button && button.style.display !== 'none') button.style.display = 'none'; };
  #|        if (typeof data.title !== 'string' || !data.title.trim() || data.title.length > 160 || !boundedJSON(data.state)) { clear(); return; }
  #|        let payload;
  #|        try { payload = JSON.stringify({title:data.title,state:data.state}); } catch { clear(); return; }
  #|        if (new TextEncoder().encode(payload).length > 12288) { clear(); return; }
  #|        frame.__artifactSnapshot = payload;
  #|        if (button && !button.disabled && button.style.display === 'none') button.style.display = '';
  #|      }
  #|      break;
  #|    }
  #|  };
  #|  const click = event => {
  #|    if (!event.isTrusted || !(event.target instanceof Element)) return;
  #|    const button = event.target.closest('#transcript .chat-artifact-context');
  #|    if (!button || button.disabled) return;
  #|    const node = button.closest('[data-transcript-artifact]');
  #|    const frame = node?.querySelector('iframe');
  #|    if (!frame?.__artifactSnapshot || frame.dataset.artifactLoaded !== node.dataset.artifactOwner || frame.dataset.artifactReference !== node.dataset.transcriptArtifact) return;
  #|    selected(node.dataset.artifactOwner, node.dataset.transcriptArtifact, frame.__artifactSnapshot);
  #|  };
  #|  addEventListener('message', listener);
  #|  document.addEventListener('click', click);
  #|  return () => { removeEventListener('message', listener); document.removeEventListener('click', click); };
  #|}
