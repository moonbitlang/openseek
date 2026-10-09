///|
// Height reads share a write/read/restore transaction. Each frame handles at
// most 32 comments and prioritizes visible zones; offscreen geometry remains
// accurate without one forced document layout per comment or one long frame.
priv struct MarkdownHeightRequest {
  outer : @rdom.Element
  content : @rdom.Element
  allow_hidden : () -> Bool
  priority : Ref[Bool]
  deliver : (Int) -> Unit
  active : Ref[Bool]
  mut selected : Bool
}

///|
priv struct MarkdownHeightRead {
  request : MarkdownHeightRequest
  mut height : Int
  saved : Array[MarkdownCommentSavedStyle]
}

///|
let markdown_height_queue : Ref[Array[MarkdownHeightRequest]] = Ref([])

///|
let markdown_height_frame : Ref[@base_common.Disposable?] = Ref(None)

///|
let markdown_height_scheduled : Ref[Bool] = Ref(false)

///|
fn schedule_markdown_height_batch() -> Unit {
  if markdown_height_scheduled.val {
    return
  }
  markdown_height_scheduled.val = true
  let registration = @base_browser.schedule_at_next_animation_frame(
    run_markdown_height_batch,
  )
  if markdown_height_scheduled.val {
    markdown_height_frame.val = Some(registration)
  } else {
    registration.dispose()
  }
}

///|
fn queue_markdown_height(
  outer : @rdom.Element,
  content : @rdom.Element,
  allow_hidden : () -> Bool,
  priority : Ref[Bool],
  deliver : (Int) -> Unit,
) -> @base_common.Disposable {
  let request : MarkdownHeightRequest = {
    outer,
    content,
    allow_hidden,
    priority,
    deliver,
    active: Ref(true),
    selected: false,
  }
  markdown_height_queue.val.push(request)
  schedule_markdown_height_batch()
  @base_common.Disposable::from(() => {
    request.active.val = false
    if markdown_height_queue.val.all(request => !request.active.val) {
      markdown_height_queue.val = []
      if markdown_height_frame.val is Some(frame) {
        frame.dispose()
      }
      markdown_height_frame.val = None
      markdown_height_scheduled.val = false
    }
  })
}

///|
fn run_markdown_height_batch() -> Unit {
  markdown_height_scheduled.val = false
  markdown_height_frame.val = None
  let pending = markdown_height_queue.val
  let selected : Array[MarkdownHeightRequest] = []
  let remaining : Array[MarkdownHeightRequest] = []
  for request in pending {
    if request.active.val && request.priority.val && selected.length() < 32 {
      request.selected = true
      selected.push(request)
    }
  }
  for request in pending {
    if !request.active.val || request.selected {
      continue
    }
    if selected.length() < 32 {
      request.selected = true
      selected.push(request)
    } else {
      remaining.push(request)
    }
  }
  markdown_height_queue.val = remaining
  // Read all currently visible heights before any temporary style writes.
  let reads = selected.map(request => {
    let connected = @base_browser.element_is_connected(request.content)
    let height = if connected {
      markdown_comment_measured_height(request.outer, request.content, false)
    } else {
      0
    }
    let saved = if connected && height <= 0 && (request.allow_hidden)() {
      ["display", "visibility", "pointer-events", "height", "top"].map(name => {
        save_markdown_comment_style(request.outer, name)
      })
    } else {
      []
    }
    MarkdownHeightRead::{ request, height, saved, }
  })
  // Write every hidden node, then read them together. The first read forces
  // layout once; subsequent reads do not interleave geometry mutations.
  for read in reads {
    if !read.saved.is_empty() {
      let outer = read.request.outer
      for
        (name, value) in [
          ("display", "block"),
          ("visibility", "hidden"),
          ("pointer-events", "none"),
          ("height", "auto"),
          ("top", "0px"),
        ] {
        @base_browser.set_style_property_with_priority(
          outer, name, value, "important",
        )
      }
    }
  }
  for read in reads {
    if !read.saved.is_empty() &&
      read.request.outer.get_bounding_client_rect().get_width() > 0.0 {
      read.height = @base_browser.element_offset_height(read.request.content).to_int()
    }
  }
  // Restore all styles before external callbacks can reenter layout/disposal.
  for read in reads {
    for saved in read.saved {
      restore_markdown_comment_style(read.request.outer, saved)
    }
  }
  for read in reads {
    if read.request.active.val {
      read.request.active.val = false
      read.request.priority.val = false
      (read.request.deliver)(read.height)
    }
  }
  if markdown_height_queue.val.any(request => request.active.val) {
    schedule_markdown_height_batch()
  }
}
