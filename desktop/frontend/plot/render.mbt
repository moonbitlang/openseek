///|
let colors : Array[String] = [
  "#2563eb", "#ea580c", "#16a34a", "#9333ea", "#dc2626", "#0891b2",
]

///|
fn Series::color(self : Series, index : Int32) -> String {
  if self.color.is_empty() {
    colors[index % colors.length()]
  } else {
    self.color
  }
}

///|
fn Series::display_name(self : Series, index : Int32) -> String {
  if self.label.is_empty() {
    self.kind + " " + (index + 1).to_string()
  } else {
    self.label
  }
}

///|
fn Spec::drawing(
  self : Spec,
  hidden : Array[Int32],
) -> @mathplotlib.Drawing raise {
  let fig = @mathplotlib.figure(width=self.width, height=self.height)
  fig.set_title(self.title)
  fig.set_x_label(self.x_label)
  let axes = fig.axes()
  axes.legend([])
  if self.grid {
    axes.grid(axis="y")
  }
  for index, series in self.series {
    if hidden.contains(index) {
      continue
    }
    let color = series.color(index)
    let points = Array::makei(series.y.length(), i => {
      @mathplotlib.point(series.x[i], series.y[i])
    })
    match series.kind {
      "line" => axes.plot(series.x, series.y, color~, label=series.label)
      "scatter" => axes.scatter(points, color~, label=series.label)
      "bar" => axes.bar(points, color~, label=series.label)
      "barh" => axes.barh(series.x, series.y, color~, label=series.label)
      "hist" =>
        ignore(
          axes.hist(series.y, bins=series.bins, color~, label=series.label),
        )
      "pie" => ignore(axes.pie(series.y, labels=series.labels))
      "area" =>
        axes.fill_between(
          series.x,
          series.y,
          Array::make(series.y.length(), 0.0),
          color~,
          label=series.label,
        )
      _ => () // The decoder admits only the supported kinds.
    }
    if !series.labels.is_empty() && series.kind != "pie" {
      if series.kind == "barh" {
        axes.set_y_ticks(series.x)
        axes.set_y_tick_labels(series.labels)
      } else {
        axes.set_x_ticks(series.x)
        axes.set_x_tick_labels(series.labels)
      }
    }
  }
  fig.to_drawing()
}

///|
priv struct Selection {
  hovered : @mathplotlib.HitPoint?
  selected : @mathplotlib.HitPoint?
  hidden : Array[Int32]
} derive(Eq)

///|
fn Selection::empty() -> Selection {
  { hovered: None, selected: None, hidden: [], }
}

///|
fn Selection::update(
  self : Selection,
  event : @plot_dom.Interaction,
) -> Selection {
  match event {
    Hover(point) => { ..self, hovered: point, }
    Click(point) => { ..self, selected: point, }
    ToggleSeries(key) => {
      let index = @string.parse_int(key) catch { _ => return self }
      let hidden = if self.hidden.contains(index) {
        self.hidden.filter(value => value != index)
      } else {
        self.hidden + [index]
      }
      { hovered: None, selected: None, hidden, }
    }
  }
}

///|
/// One message branch owns its chart state and prepared drawings. Hover updates
/// reuse the drawing; toggling a series produces a new snapshot and clears picks.
pub fn renderer() -> @rabbita.Val[Renderer] {
  let (state, emit) = @rabbita.create_pure_state(
    (Map([]) : Map[String, Selection]),
    update=(state, message : (String, @plot_dom.Interaction)) => {
      let copy = state.copy()
      copy[message.0] = state
        .get(message.0)
        .unwrap_or_else(Selection::empty)
        .update(message.1)
      copy
    },
  )
  let cache : Map[String, (String, Spec, Array[Int32], @mathplotlib.Drawing)] = Map([],
  )
  let owner = next_id()
  let revision = Ref(0)
  state.map(state => {
    revision.val += 1
    Renderer::{
      owner,
      revision: revision.val,
      build: (catalog, locale) => {
        let ordinal = Ref(0)
        (artifact_id, alt) => {
          let key = ordinal.val.to_string()
          ordinal.val += 1
          guard catalog.source(artifact_id) is Some(source) else {
            return unavailable_chart(locale, alt)
          }
          let selected = state
            .get(artifact_id + "\u{0}" + key)
            .unwrap_or_else(Selection::empty)
          try {
            if source.length() > 39000 {
              fail("Chart is too large; aggregate the data explicitly")
            }
            let (spec, drawing) = match cache.get(key) {
              Some((previous, spec, hidden, drawing)) if previous == source &&
                hidden == selected.hidden => (spec, drawing)
              _ => {
                let spec : Spec = @json.from_json(@json.parse(source))
                let drawing = spec.drawing(selected.hidden)
                cache[key] = (source, spec, selected.hidden, drawing)
                (spec, drawing)
              }
            }
            spec.view(
              drawing,
              selected,
              id="seekmoon-plot-\{owner}-\{key}",
              locale~,
              on_event=event => emit((artifact_id + "\u{0}" + key, event)),
            )
          } catch {
            error =>
              @html.div(class="chat-plot-error", [
                @html.p(error.to_string()),
                @html.details([
                  @html.summary(labels(locale).chart_data),
                  @html.pre(source),
                ]),
              ])
          }
        }
      },
    }
  })
}

///|
let chart_id : Ref[Int32] = Ref(0)

///|
fn next_id() -> Int32 {
  chart_id.val += 1
  chart_id.val
}

///|
pub struct Renderer {
  priv owner : Int32
  priv revision : Int32
  priv build : (Catalog, @i18n.Locale) -> (String, String) -> @html.Html
}

///|
pub impl Eq for Renderer with fn equal(a, b) {
  a.owner == b.owner && a.revision == b.revision
}

///|
pub fn Renderer::begin(
  self : Renderer,
  catalog : Catalog,
  locale~ : @i18n.Locale = English,
) -> (String, String) -> @html.Html {
  (self.build)(catalog, locale)
}

///|
pub extend Renderer with Eq::{equal, not_equal}
