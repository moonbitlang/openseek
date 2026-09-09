///|
/// Group contiguous work without crossing prompts, checkpoints or notices.
/// The preceding boundary owns the group key: replacing the first live thought
/// with a durable response must not reset the reader's disclosure choice.
/// Final-answer evidence joins the work; final and live prose remain outside.
fn group_work_blocks(blocks : Array[Block]) -> Array[Block] {
  let output : Array[Block] = []
  let mut work : Array[Block] = []
  let mut boundary = TranscriptRenderKey::empty()
  for block in blocks {
    let (evidence, remainder) = match block.content {
      Item(
        item~,
        anchor~,
        step_label~,
        assistant_name~,
        subrun_parent~,
        wait_labels~
      ) =>
        match item.kind {
          Assistant(replay=false, finished=false, ..) => (Some(block), None)
          Assistant(replay=false, finished=true, reasoning~, prose~, calls~) if (
              reasoning is Some(text) && !text.is_blank()
            ) ||
            !calls.is_empty() => {
            let evidence = {
              ..block,
              content: Item(
                item={
                  ..item,
                  kind: Assistant(
                    reasoning~,
                    prose=None,
                    calls~,
                    replay=false,
                    finished=false,
                  ),
                },
                anchor~,
                step_label~,
                assistant_name~,
                subrun_parent~,
                wait_labels~,
              ),
            }
            let answer = {
              ..block,
              content: Item(
                item={
                  ..item,
                  kind: Assistant(
                    reasoning=None,
                    prose~,
                    calls=[],
                    replay=false,
                    finished=true,
                  ),
                },
                anchor~,
                step_label~,
                assistant_name~,
                subrun_parent~,
                wait_labels~,
              ),
            }
            (Some(evidence), Some(answer))
          }
          _ => (None, Some(block))
        }
      Live(
        prose~,
        reasoning~,
        reasoning_complete~,
        step_label~,
        assistant_name~
      ) => {
        let evidence = match reasoning {
          Some(text) if !text.is_blank() =>
            Some({
              ..block,
              content: Live(
                prose=None,
                reasoning=Some(text),
                reasoning_complete~,
                step_label~,
                assistant_name~,
              ),
            })
          _ => None
        }
        let answer = prose.map(text => {
          ..block,
          content: Live(
            prose=Some(text),
            reasoning=None,
            reasoning_complete~,
            step_label~,
            assistant_name~,
          ),
        })
        (evidence, answer)
      }
      _ => (None, Some(block))
    }
    if evidence is Some(part) {
      work.push(part)
    }
    if remainder is Some(part) {
      if work.get(0) is Some(first) {
        output.push({
          ..first,
          key: { value: "work\u{0}" + boundary.wire(), },
          content: Work(work),
        })
        work = []
      }
      output.push(part)
      boundary = part.key
    }
  }
  if work.get(0) is Some(first) {
    output.push({
      ..first,
      key: { value: "work\u{0}" + boundary.wire(), },
      content: Work(work),
    })
  }
  output
}

///|
/// A factual, bounded navigation label. Only OpenSeek response ordinals count
/// as steps; Codex may split one response across several transcript items.
fn work_view(blocks : Array[Block], actions : Actions) -> @html.Html {
  let children : Map[String, @html.Html] = Map([])
  let mut steps = 0
  let mut tools = 0
  let mut failed = false
  let mut pending = false
  let mut thinking = false
  for block in blocks {
    children[block.branch_key()] = block.render(actions)
    match block.content {
      Item(item~, step_label~, ..) => {
        if step_label is Some(_) {
          steps += 1
        }
        if item.kind is Assistant(calls~, ..) {
          tools += calls.length()
          failed = failed ||
            calls.any(call => call.outcome is Done(is_error=true, ..))
          pending = pending || calls.any(call => call.outcome is Pending(..))
        }
      }
      Live(reasoning_complete~, ..) => thinking = !reasoning_complete
      _ => ()
    }
  }
  let mut label = "Work"
  if steps > 0 {
    label += " · \{steps} " + (if steps == 1 { "step" } else { "steps" })
  }
  if tools > 0 {
    label += " · \{tools} " +
      (if tools == 1 { "tool call" } else { "tool calls" })
  }
  if failed {
    label += " · Tool failed"
  }
  if pending {
    label += " · Awaiting result"
  }
  if thinking {
    label += " · Thinking"
  }
  @html.details(class="work-group", attrs=@html.Attrs::build().open(true), [
    @html.summary(class="work-toggle work-summary", [
      @html.span(class="work-chevron", @icons.icon_chevron_down()),
      @html.text(label),
    ]),
    @html.div(class="work-body", children),
  ])
}
