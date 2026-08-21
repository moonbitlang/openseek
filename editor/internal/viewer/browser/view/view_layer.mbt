// Ported from `vscode/src/vs/editor/browser/view/viewLayer.ts`
// `VisibleLinesCollection.renderLines`, `IRendererContext`, and the complete
// `ViewLayerRenderer` class in the checked-in source.

///|
/// The mutable renderer context copied at the beginning of every render and
/// returned with the reconciled retained-line collection.
priv struct RendererContext[T] {
  mut rend_line_number_start : Int
  mut lines : Array[T]
  mut lines_length : Int
}

///|
/// Typed callbacks adapt a concrete retained-row type to Monaco's
/// `IVisibleLine` contract while leaving row state on its owning type.
priv struct ViewLayerRenderer[T] {
  dom_node : @rdom.Element
  create_line : () -> T
  get_dom_node : (T) -> @rdom.Element?
  set_dom_node : (T, @rdom.Element) -> Unit
  layout_line : (T, Int, Double, Int) -> Unit
  render_line : (T, Int, Double, Int, @view_layout.ViewportData, StringBuilder) -> Bool
  viewport_data : @view_layout.ViewportData
  line_height_for_line_number : (Int) -> Int
}

///|
fn[T] ViewLayerRenderer::ViewLayerRenderer(
  dom_node : @rdom.Element,
  create_line : () -> T,
  get_dom_node : (T) -> @rdom.Element?,
  set_dom_node : (T, @rdom.Element) -> Unit,
  layout_line : (T, Int, Double, Int) -> Unit,
  render_line : (T, Int, Double, Int, @view_layout.ViewportData, StringBuilder) -> Bool,
  viewport_data : @view_layout.ViewportData,
  line_height_for_line_number : (Int) -> Int,
) -> ViewLayerRenderer[T] {
  {
    dom_node,
    create_line,
    get_dom_node,
    set_dom_node,
    layout_line,
    render_line,
    viewport_data,
    line_height_for_line_number,
  }
}

///|
/// `ViewLayerRenderer.render` (`viewLayer.ts:394-467`). Branch and mutation
/// order intentionally match the source.
fn[T] ViewLayerRenderer::render(
  self : ViewLayerRenderer[T],
  in_context : RendererContext[T],
  start_line_number : Int,
  stop_line_number : Int,
  delta_top : Array[Double],
) -> RendererContext[T] {
  let ctx : RendererContext[T] = {
    rend_line_number_start: in_context.rend_line_number_start,
    lines: in_context.lines.copy(),
    lines_length: in_context.lines_length,
  }
  if ctx.rend_line_number_start + ctx.lines_length - 1 < start_line_number ||
    stop_line_number < ctx.rend_line_number_start {
    ctx.rend_line_number_start = start_line_number
    ctx.lines_length = stop_line_number - start_line_number + 1
    ctx.lines = []
    for _line_number in start_line_number..<=stop_line_number {
      ctx.lines.push((self.create_line)())
    }
    self.finish_rendering(ctx, true, delta_top)
    return ctx
  }
  self.render_untouched_lines(
    ctx,
    (start_line_number - ctx.rend_line_number_start).max(0),
    (stop_line_number - ctx.rend_line_number_start).min(ctx.lines_length - 1),
    delta_top,
    start_line_number,
  )
  if ctx.rend_line_number_start > start_line_number {
    let from_line_number = start_line_number
    let to_line_number = stop_line_number.min(ctx.rend_line_number_start - 1)
    if from_line_number <= to_line_number {
      self.insert_lines_before(ctx, from_line_number, to_line_number)
      ctx.lines_length += to_line_number - from_line_number + 1
    }
  } else if ctx.rend_line_number_start < start_line_number {
    let remove_count = ctx.lines_length.min(
      start_line_number - ctx.rend_line_number_start,
    )
    if remove_count > 0 {
      self.remove_lines_before(ctx, remove_count)
      ctx.lines_length -= remove_count
    }
  }
  ctx.rend_line_number_start = start_line_number
  if ctx.rend_line_number_start + ctx.lines_length - 1 < stop_line_number {
    let from_line_number = ctx.rend_line_number_start + ctx.lines_length
    let to_line_number = stop_line_number
    if from_line_number <= to_line_number {
      self.insert_lines_after(ctx, from_line_number, to_line_number)
      ctx.lines_length += to_line_number - from_line_number + 1
    }
  } else if ctx.rend_line_number_start + ctx.lines_length - 1 > stop_line_number {
    let from_line_number = (stop_line_number - ctx.rend_line_number_start + 1).max(
      0,
    )
    let to_line_number = ctx.lines_length - 1
    let remove_count = to_line_number - from_line_number + 1
    if remove_count > 0 {
      self.remove_lines_after(ctx, remove_count)
      ctx.lines_length -= remove_count
    }
  }
  self.finish_rendering(ctx, false, delta_top)
  ctx
}

///|
fn[T] ViewLayerRenderer::render_untouched_lines(
  self : ViewLayerRenderer[T],
  ctx : RendererContext[T],
  start_index : Int,
  end_index : Int,
  delta_top : Array[Double],
  delta_line_number : Int,
) -> Unit {
  for index in start_index..<=end_index {
    let line_number = ctx.rend_line_number_start + index
    (self.layout_line)(
      ctx.lines[index],
      line_number,
      delta_top[line_number - delta_line_number],
      (self.line_height_for_line_number)(line_number),
    )
  }
}

///|
fn[T] ViewLayerRenderer::insert_lines_before(
  self : ViewLayerRenderer[T],
  ctx : RendererContext[T],
  from_line_number : Int,
  to_line_number : Int,
) -> Unit {
  let lines : Array[T] = []
  for _line_number in from_line_number..<=to_line_number {
    lines.push((self.create_line)())
  }
  for line in ctx.lines {
    lines.push(line)
  }
  ctx.lines = lines
}

///|
fn[T] ViewLayerRenderer::remove_lines_before(
  self : ViewLayerRenderer[T],
  ctx : RendererContext[T],
  remove_count : Int,
) -> Unit {
  for index in 0..<remove_count {
    match (self.get_dom_node)(ctx.lines[index]) {
      Some(node) => {
        self.dom_node.remove_child(node.as_node())
        record_view_layer_mutation("remove")
      }
      None => ()
    }
  }
  for _ in 0..<remove_count {
    ctx.lines.remove(0) |> ignore
  }
}

///|
fn[T] ViewLayerRenderer::insert_lines_after(
  self : ViewLayerRenderer[T],
  ctx : RendererContext[T],
  from_line_number : Int,
  to_line_number : Int,
) -> Unit {
  for _line_number in from_line_number..<=to_line_number {
    ctx.lines.push((self.create_line)())
  }
}

///|
fn[T] ViewLayerRenderer::remove_lines_after(
  self : ViewLayerRenderer[T],
  ctx : RendererContext[T],
  remove_count : Int,
) -> Unit {
  let remove_index = ctx.lines_length - remove_count
  for index in 0..<remove_count {
    match (self.get_dom_node)(ctx.lines[remove_index + index]) {
      Some(node) => {
        self.dom_node.remove_child(node.as_node())
        record_view_layer_mutation("remove")
      }
      None => ()
    }
  }
  for _ in 0..<remove_count {
    ctx.lines.remove(remove_index) |> ignore
  }
}

///|
fn[T] ViewLayerRenderer::finish_rendering_new_lines(
  self : ViewLayerRenderer[T],
  ctx : RendererContext[T],
  dom_node_is_empty : Bool,
  new_lines_html : String,
  was_new : Array[Bool],
) -> Unit {
  let parsed_nodes = if dom_node_is_empty ||
    self.dom_node.get_child_count() == 0 {
    self.dom_node.set_inner_html(new_lines_html)
    snapshot_element_children(self.dom_node)
  } else {
    let staging = @rdom.document().create_element("div")
    staging.set_inner_html(new_lines_html)
    let nodes = snapshot_element_children(staging)
    for node in nodes {
      self.dom_node.append_child(node.as_node())
    }
    nodes
  }
  record_view_layer_mutation("new-batch")
  for index in ctx.lines_length>..0; child_index = parsed_nodes.length() - 1 {
    if was_new[index] {
      (self.set_dom_node)(ctx.lines[index], parsed_nodes[child_index])
      continue child_index - 1
    }
  }
}

///|
fn[T] ViewLayerRenderer::finish_rendering_invalid_lines(
  self : ViewLayerRenderer[T],
  ctx : RendererContext[T],
  invalid_lines_html : String,
  was_invalid : Array[Bool],
) -> Unit {
  let staging = @rdom.document().create_element("div")
  staging.set_inner_html(invalid_lines_html)
  let nodes = snapshot_element_children(staging)
  record_view_layer_mutation("invalid-batch")
  let mut child_index = 0
  for index in 0..<ctx.lines_length {
    if was_invalid[index] {
      let source = nodes[child_index]
      let line_dom_node = (self.get_dom_node)(ctx.lines[index]).unwrap()
      self.dom_node.replace_child(source.as_node(), line_dom_node.as_node())
      (self.set_dom_node)(ctx.lines[index], source)
      child_index += 1
    }
  }
}

///|
/// `_finishRendering` (`viewLayer.ts:557-625`): new pass first, then invalid
/// pass, with the source's skip order and one shared 100000-character builder.
fn[T] ViewLayerRenderer::finish_rendering(
  self : ViewLayerRenderer[T],
  ctx : RendererContext[T],
  dom_node_is_empty : Bool,
  delta_top : Array[Double],
) -> Unit {
  let builder = view_layer_string_builder
  let was_new = Array::make(ctx.lines_length, false)
  builder.reset()
  let mut had_new_line = false
  for index in 0..<ctx.lines_length {
    let line = ctx.lines[index]
    if (self.get_dom_node)(line) is Some(_) {
      continue
    }
    let line_number = index + ctx.rend_line_number_start
    if !(self.render_line)(
        line,
        line_number,
        delta_top[index],
        (self.line_height_for_line_number)(line_number),
        self.viewport_data,
        builder,
      ) {
      continue
    }
    was_new[index] = true
    had_new_line = true
  }
  if had_new_line {
    self.finish_rendering_new_lines(
      ctx,
      dom_node_is_empty,
      builder.to_string(),
      was_new,
    )
  }
  builder.reset()
  let was_invalid = Array::make(ctx.lines_length, false)
  let mut had_invalid_line = false
  for index in 0..<ctx.lines_length {
    if was_new[index] {
      continue
    }
    let line_number = index + ctx.rend_line_number_start
    if !(self.render_line)(
        ctx.lines[index],
        line_number,
        delta_top[index],
        (self.line_height_for_line_number)(line_number),
        self.viewport_data,
        builder,
      ) {
      continue
    }
    was_invalid[index] = true
    had_invalid_line = true
  }
  if had_invalid_line {
    self.finish_rendering_invalid_lines(ctx, builder.to_string(), was_invalid)
  }
}

///|
let view_layer_string_builder : StringBuilder = StringBuilder(size_hint=100000)

///|
extern "js" fn record_view_layer_mutation(kind : String) -> Unit =
  #| (kind) => {
  #|   const metrics = globalThis.__moonbitViewerScrollMetrics;
  #|   if (!metrics) return;
  #|   metrics.viewLayer ||= {};
  #|   metrics.viewLayer[kind] = (metrics.viewLayer[kind] || 0) + 1;
  #| }

///|
/// Rabbita's `get_children` exposes the live `HTMLCollection`; renderer
/// binding moves those nodes, so take the same stable snapshot that an
/// ordinary `HTMLElement[]` supplies in Monaco's loops.
extern "js" fn snapshot_element_children(
  element : @rdom.Element,
) -> FixedArray[@rdom.Element] =
  #| (element) => Array.from(element.children)
