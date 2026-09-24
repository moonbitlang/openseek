// Lazy, bounded local-image projection for transcript Markdown. The durable
// transcript keeps the model-authored path; this component cache contains only
// display data for the conversation currently mounted in the page.

///|
fn transcript_image_observer(
  on_image : (String) -> Unit,
) -> @dom.IntersectionObserver {
  @dom.IntersectionObserver::new((entries, observer) => {
    for entry in entries {
      if !image_entry_intersects(entry) {
        continue
      }
      let target = image_entry_target(entry)
      observer.unobserve(target)
      if target.get_attribute("data-transcript-image") is Some(path) &&
        path != "" {
        on_image(path)
      }
    }
  })
}

///|
/// Observe every image placeholder currently rendered under `transcript`.
fn observe_transcript_images(
  observer : @dom.IntersectionObserver,
  transcript : @dom.Element,
) -> Unit {
  for image in transcript.query_selector_all("img[data-transcript-image]") {
    observer.observe(image)
  }
}

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
  { channel: self.focused, session: self.active_session, root: self.root, }
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
          ImageReady(source) => settle_transcript_image(path, Some(source))
          ImageUnavailable => settle_transcript_image(path, None)
          ImageLoading => ()
        }
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Remove the pending marker after either a successful read or a failure so
/// the viewport observer does not keep retrying an unavailable image.
fn settle_transcript_image(path : String, source : String?) -> Unit {
  for image in @dom.document().query_selector_all("img[data-transcript-image]") {
    if image.get_attribute("data-transcript-image") != Some(path) {
      continue
    }
    image.remove_attribute("data-transcript-image")
    image_class_toggle(image, "pending", false)
    match source {
      Some(source) => image.set_attribute("src", source)
      None => image_class_toggle(image, "unavailable", true)
    }
  }
}

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
    Some({ path: "../image.png", root: Some("/work/project"), }),
  )
  assert_eq(
    owner.read_target("/Users/me/image.png"),
    Some({ path: "/Users/me/image.png", root: None, }),
  )
  let unresolved : ImageOwner = { ..owner, root: None, }
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
    return Some({ path: target.path, root: None, })
  }
  guard self.root is Some(root) &&
    @resource.path_for(root, self.channel) is Some(root_path) else {
    return None
  }
  Some({ path, root: Some(root_path), })
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
    @js.Promise::from_async(() => {
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
    |> ignore
  })
}
