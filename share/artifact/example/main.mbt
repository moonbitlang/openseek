///|
struct Selection {
  hovered : @mathplotlib.HitPoint?
  selected : @mathplotlib.HitPoint?
  line : Bool
  bars : Bool
} derive(Eq)

///|
fn drawing(line : Bool, bars : Bool) -> @mathplotlib.Drawing raise {
  let figure = @mathplotlib.figure(width=760, height=400)
  figure.set_title("Weekly revenue")
  figure.set_x_label("Week")
  let axes = figure.axes()
  axes.legend([])
  axes.grid(axis="y")
  let x = [1.0, 2.0, 3.0, 4.0, 5.0]
  if bars {
    axes.bar(
      [
        @mathplotlib.point(1.0, 10.0),
        @mathplotlib.point(2.0, 15.0),
        @mathplotlib.point(3.0, 20.0),
        @mathplotlib.point(4.0, 25.0),
        @mathplotlib.point(5.0, 30.0),
      ],
      color="#94a3b8",
      label="Forecast",
    )
  }
  if line {
    axes.plot(
      x,
      [12.0, 19.0, 16.0, 25.0, 31.0],
      color="#2563eb",
      label="Actual",
    )
  }
  figure.to_drawing()
}

///|
fn main raise {
  let initial = drawing(true, true)
  let app = @rabbita.new(() => {
    let prepared = Ref(initial)
    let (selection, emit) = @rabbita.create_pure_state(
      Selection::{ hovered: None, selected: None, line: true, bars: true, },
      update=(state, event : @plot_dom.Interaction) => {
        match event {
          Hover(point) => { ..state, hovered: point, }
          Click(point) => { ..state, selected: point, }
          ToggleSeries(key) => {
            let line = if key == "actual" { !state.line } else { state.line }
            let bars = if key == "forecast" { !state.bars } else { state.bars }
            prepared.val = drawing(line, bars) catch { _ => return state }
            { hovered: None, selected: None, line, bars, }
          }
        }
      },
    )
    selection.view(state => {
      @plot_dom.view(
        prepared.val,
        id="revenue",
        on_event=event => emit(event),
        hovered?=state.hovered,
        selected?=state.selected,
        hit_mode=XNearest,
        legend=[
          @plot_dom.legend_item("actual", "Actual", "#2563eb", state.line),
          @plot_dom.legend_item("forecast", "Forecast", "#94a3b8", state.bars),
        ],
      ) catch {
        _ => @html.p("Chart could not be rendered")
      }
    })
  })
  app.mount("chart")
}
