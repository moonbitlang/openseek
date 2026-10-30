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
        (next, publish_state(next))
      },
    )
    model.view(model => {
      let serial = model.serial_percent
      let parallel = 100 - serial
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
      ])
    })
  }).mount("app")
}
