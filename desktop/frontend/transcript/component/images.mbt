// Lazy, bounded local-image projection for transcript Markdown. The durable
// transcript keeps the model-authored path; this component cache contains only
// display data for the conversation currently mounted in the page.

///|
#external
priv type TranscriptImageObserver

///|
/// Observe only transcript-local image placeholders. Once a placeholder enters
/// the viewport it is unobserved before its path is sent back to MoonBit, so a
/// slow host read cannot produce repeated requests.
extern "js" fn TranscriptImageObserver::install(
  on_image : (String) -> Unit,
) -> Self =
  #| (onImage) => new IntersectionObserver((entries, observer) => {
  #|   for (const entry of entries) {
  #|     if (!entry.isIntersecting) continue;
  #|     observer.unobserve(entry.target);
  #|     const path = entry.target.dataset.transcriptImage;
  #|     if (path) onImage(path);
  #|   }
  #| })

///|
extern "js" fn TranscriptImageObserver::scan(
  self : Self,
  transcript : @dom.Element,
) -> Unit =
  #| (self, transcript) => {
  #|   for (const image of transcript.querySelectorAll("img[data-transcript-image]")) {
  #|     self.observe(image);
  #|   }
  #| }

///|
extern "js" fn TranscriptImageObserver::disconnect(self : Self) -> Unit =
  #| (self) => self.disconnect()

///|
priv enum LocalImageState {
  ImageLoading
  ImageReady(String)
  ImageUnavailable
} derive(Eq)

///|
priv struct ImageOwner {
  channel : @interop.ChannelId
  // Session remains frontend identity only: it fences late replies after a
  // conversation switch and is never sent to the filesystem operation.
  session : String
  root : @common.Uri?
} derive(Eq)

///|
priv struct ImageCache(Map[String, LocalImageState]) derive(Eq)

///|
priv enum ImageReadResult {
  ImageReadReady(String)
  ImageReadUnavailable
}

///|
fn Input::image_owner(self : Input) -> ImageOwner {
  { channel: self.focused, session: self.active_session, root: self.root }
}

///|
fn ImageCache::empty() -> ImageCache {
  ImageCache(Map([]))
}

///|
/// Start at most one in-flight read for a path in this conversation. A
/// root-relative path waits without entering the cache while the root is
/// unresolved, so a later root update can rescan and request it.
fn ImageCache::begin_read(
  self : ImageCache,
  owner : ImageOwner,
  path : String,
  emit : @cmd.Emit[Msg],
) -> (ImageCache, @cmd.Cmd) {
  guard owner.read_target(path) is Some(target) else {
    return (self, @cmd.none)
  }
  if self.0.get(path) is Some(ImageLoading) {
    return (self, @cmd.none)
  }
  let entries = self.0.copy()
  entries[path] = ImageLoading
  (ImageCache(entries), owner.read_image(target, path, emit))
}

///|
/// Apply cached results after Rabbita has reconciled transcript Markdown. The
/// renderer intentionally keeps local image paths out of `src`; this command
/// fills a recognized data URL or settles the node as alt text. Reapplying is
/// cheap and repairs nodes replaced by a later streaming render.
fn ImageCache::apply_after_render(self : ImageCache) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      for path, state in self.0 {
        match state {
          ImageReady(source) => settle_transcript_image(path, source)
          ImageUnavailable => settle_transcript_image(path, "")
          ImageLoading => ()
        }
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Settle every rendered occurrence of one path. An empty source means the
/// bounded host read failed or the bytes were not a supported raster image;
/// removing the marker prevents the viewport observer from retrying forever.
extern "js" fn settle_transcript_image(path : String, source : String) -> Unit =
  #| (path, source) => {
  #|   for (const image of document.querySelectorAll("img[data-transcript-image]")) {
  #|     if (image.dataset.transcriptImage !== path) continue;
  #|     image.removeAttribute("data-transcript-image");
  #|     image.classList.remove("pending");
  #|     if (source) image.src = source;
  #|     else image.classList.add("unavailable");
  #|   }
  #| }

///|
test "image cache starts one read and settles only the pending entry" {
  let owner : ImageOwner = {
    channel: @interop.Local,
    session: "chat",
    root: @resource.of_path(@interop.Local, "/work"),
  }
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (loading, _) = ImageCache::empty().begin_read(owner, "image.png", emit)
  assert_true(loading.0.get("image.png") is Some(ImageLoading))
  let (duplicate, _) = loading.begin_read(owner, "image.png", emit)
  assert_eq(duplicate.0.length(), 1)
  let ready = duplicate.settle(
    "image.png",
    ImageReadReady("data:image/png;base64,iVBORw0KGgo="),
  )
  assert_true(
    ready.0.get("image.png")
    is Some(ImageReady("data:image/png;base64,iVBORw0KGgo=")),
  )
  // A late duplicate result cannot replace the already-settled display data.
  let unchanged = ready.settle("image.png", ImageReadUnavailable)
  assert_true(unchanged == ready)
  // A marker emitted after settlement represents a new or recreated image
  // node, so it must start a fresh read instead of projecting stale bytes.
  let (refreshed, _) = ready.begin_read(owner, "image.png", emit)
  assert_true(refreshed.0.get("image.png") is Some(ImageLoading))
}

///|
test "image read targets preserve absolute or rooted-relative paths" {
  guard @resource.of_path(@interop.Local, "/work/project") is Some(root) else {
    fail("expected an absolute resource root")
  }
  let owner : ImageOwner = {
    channel: @interop.Local,
    session: "chat",
    root: Some(root),
  }
  assert_eq(
    owner.read_target("../image.png"),
    Some({ path: "../image.png", root: Some("/work/project") }),
  )
  assert_eq(
    owner.read_target("/Users/me/image.png"),
    Some({ path: "/Users/me/image.png", root: None }),
  )
  let unresolved : ImageOwner = { ..owner, root: None }
  assert_eq(unresolved.read_target("../image.png"), None)
}

///|
fn ImageCache::settle(
  self : ImageCache,
  path : String,
  result : ImageReadResult,
) -> ImageCache {
  guard self.0.get(path) is Some(ImageLoading) else { return self }
  let entries = self.0.copy()
  entries[path] = match result {
    ImageReadReady(source) => ImageReady(source)
    ImageReadUnavailable => ImageUnavailable
  }
  ImageCache(entries)
}

///|
/// Preserve an absolute Markdown path as-is, or pair a relative path with the
/// explicit absolute root owned by this channel. The frontend never joins the
/// two strings; the owning host validates and resolves the pair.
fn ImageOwner::read_target(
  self : ImageOwner,
  path : String,
) -> @protocol.ReadFilePayload? {
  if @resource.of_path(self.channel, path) is Some(target) {
    return Some({ path: target.path, root: None })
  }
  guard self.root is Some(root) &&
    @resource.path_for(root, self.channel) is Some(root_path) else {
    return None
  }
  Some({ path, root: Some(root_path) })
}

///|
/// Read through the ordinary filesystem command. The request carries either an
/// absolute path or a relative path with its explicit root; the host resolves
/// that address, enforces the shared limit, and recognizes raster signatures.
fn ImageOwner::read_image(
  self : ImageOwner,
  target : @protocol.ReadFilePayload,
  path : String,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        self.channel,
        @commands.fs_read_file,
        target,
      ) catch {
        _ => {
          scheduler.add(emit(ImageResolved(self, path, ImageReadUnavailable)))
          return
        }
      }
      let result = match reply {
        @protocol.BinaryContent(data_base64~, media_type~) =>
          ImageReadReady("data:\{media_type};base64,\{data_base64}")
        @protocol.Binary | @protocol.Oversized | @protocol.Content(..) =>
          ImageReadUnavailable
      }
      scheduler.add(emit(ImageResolved(self, path, result)))
    })
  })
}
