///|
/// The card the live preview writes into. Rabbita owns everything here except
/// the descendants of the innermost text element, which has no virtual-DOM
/// children: the preview appends browser text nodes there and the diff never
/// visits them. CSS hides the card while that element is empty.
pub fn host_view(step_label? : String) -> @html.Html {
  let summary : Array[@html.Html] = []
  match step_label {
    Some(label) => {
      summary.push(@html.span(class="activity-step", label))
      summary.push(@html.text(" · Thinking…"))
    }
    None => summary.push(@html.text("Thinking…"))
  }
  @html.div(id="live-reasoning-host", class="live-reasoning-host", [
    @html.div(class="activity-row", [
      @html.details(class="activity", open=true, [
        @html.summary(class="activity-summary", [
          @html.span(class="activity-text", summary),
        ]),
        @html.div(class="activity-body", [
          @html.div(
            id=TEXT_HOST_ID,
            class="msg-content activity-thinking activity-thinking-live",
            ([] : Array[@html.Html]),
          ),
        ]),
      ]),
    ]),
  ])
}

///|
const TEXT_HOST_ID = "live-reasoning-text"
