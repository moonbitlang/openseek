///|
fn speedup_chart(model : Model) -> @mathplotlib.Drawing raise {
  let figure = @mathplotlib.figure(width=760, height=400)
  figure.set_title("Parallel speedup")
  figure.set_x_label("Workers")
  let axes = figure.axes()
  axes.grid(axis="y")
  let workers = [ for n in 1..<65 => n.to_double() ]
  let values = workers.map(count => {
    speedup({ ..model, workers: count.to_int(), })
  })
  axes.plot(workers, values, color="#2563eb", label="Speedup")
  figure.to_drawing()
}

///|
fn main {
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state_with_init(
      init=_ => {
        let model = initial_model()
        (model, publish_state(model))
      },
      update=(model, message, _) => {
        let next = update(model, message)
        let effect = match message {
          Chart(Hover(_)) => @cmd.none
          _ => publish_state(next)
        }
        (next, effect)
      },
    )
    model.view(model => {
      let serial = model.serial_percent
      let parallel = 100 - serial
      let chart = speedup_chart(model) catch {
        _ => return @html.p("Chart could not be rendered")
      }
      let mut selected = None
      for point in chart.points() {
        if point.data_x == model.workers.to_double() {
          selected = Some(point)
          break
        }
      }
      @html.section(class="answer", [
        @html.h2("How much faster can more workers make this task?"),
        @html.div(class="controls", [
          @html.div([
            @html.label(
              for_="serial",
              "Work that must run in sequence: \{serial}%",
            ),
            @html.input(
              id="serial",
              input_type=Range,
              min=0,
              max=100,
              step=1,
              value=serial.to_string(),
              on_input=value => emit(Serial(value)),
            ),
          ]),
          @html.div([
            @html.label(for_="workers", "Workers: \{model.workers}"),
            @html.input(
              id="workers",
              input_type=Range,
              min=1,
              max=64,
              step=1,
              value=model.workers.to_string(),
              on_input=value => emit(Workers(value)),
            ),
          ]),
        ]),
        @html.output(
          id="result",
          for_="serial workers",
          attrs=@html.Attrs::build().aria_live("polite"),
          "\{hundredths(speedup(model))}× faster",
        ),
        @plot_dom.view(
          chart,
          id="speedup-chart",
          on_event=event => emit(Chart(event)),
          hovered?=model.hovered,
          selected?,
          hit_mode=XNearest,
        ) catch {
          _ => @html.p("Chart could not be rendered")
        },
        @html.div(class="composition", [
          @html.span(
            class="serial",
            style=["width: \{serial}%"],
            attrs=@html.Attrs::build().aria_hidden("true"),
            "",
          ),
          @html.span(
            class="parallel",
            style=["width: \{parallel}%"],
            attrs=@html.Attrs::build().aria_hidden("true"),
            "",
          ),
        ]),
        @html.p(
          class="legend",
          "\{serial}% sequential · \{parallel}% parallelizable",
        ),
        @html.button(type_="button", on_click=emit(Reset), "Reset"),
        if has_followup() {
          @html.button(
            type_="button",
            on_click=explain_speedup(model),
            "Explain this speedup",
          )
        } else {
          @html.nothing
        },
      ])
    })
  }).mount("app")
}
