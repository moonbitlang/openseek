///|
priv enum Msg {
  ToggleTheme
  ToggleWidth
}

///|
fn main {
  // Prepare snapshots once, independently of theme and width controls. This
  // example imports only the public static renderer and language tokenizers.
  let moonbit = @preview.diff_preview(
    [
      Context("fn main {", old_line=Some(1528), new_line=Some(1528)),
      Removed("  let message = \"before\"", line=Some(1529)),
      Added(
        "  let message = \"" + "long source ".repeat(24) + "\"",
        line=Some(1529),
      ),
      Added("\tprintln(message)", line=Some(1530)),
      Context("}", old_line=Some(1530), new_line=Some(1531)),
      Gap,
      Removed("let count = 1", line=Some(99999)),
      Added("let count = 2", line=Some(100000)),
    ],
    label="src/main.mbtx: recorded changes",
    tokenizer=@lang_moonbit.MoonBitTokenizer(),
  )
  let javascript = @preview.diff_preview(
    [
      Removed("/* old comment", line=Some(20)),
      Added("const answer = 42;", line=Some(20)),
      Removed("still a comment */", line=Some(21)),
      Added("/* new comment", line=Some(21)),
      Added("continues here */", line=Some(22)),
      Added("/* omitted continuation", line=Some(23)),
      Gap,
      Added("const html = '<img src=x onerror=alert(1)>';", line=Some(40)),
    ],
    label="src/comments.js: recorded changes",
    tokenizer=@lang_javascript.JavascriptTokenizer(),
  )
  let plain = @preview.diff_preview(label="Plain text: unknown coordinates", [
    Removed("<before> & \"quoted\"", line=None),
    Added("<after> & \"quoted\"", line=None),
    Added("", line=None),
    Context("unknown coordinates stay blank", old_line=None, new_line=None),
  ])
  let cards = @html.div(class="preview-cards", [
    @html.div(class="preview-card", [
      @html.div(class="preview-title", "src/main.mbtx"),
      moonbit,
    ]),
    @html.div(class="preview-card", [
      @html.div(class="preview-title", "src/comments.js"),
      javascript,
    ]),
    @html.div(class="preview-card", [
      @html.div(class="preview-title", "Plain text · missing coordinates"),
      plain,
    ]),
  ])
  let app = @rabbita.new(() => {
    let (state, emit) = @rabbita.create_state((false, true), update=(
      state,
      msg,
      _emit,
    ) => {
      let (dark, narrow) = state
      let next = match msg {
        ToggleTheme => (!dark, narrow)
        ToggleWidth => (dark, !narrow)
      }
      (next, @cmd.none)
    })
    state.view(state => {
      let (dark, narrow) = state
      @html.div(
        class="editor-shell diff-preview-demo",
        attrs=@html.Attrs::build().data_set(
          "theme",
          if dark {
            "dark"
          } else {
            "light"
          },
        ),
        [
          @html.div(class="preview-toolbar", [
            @html.h1("Diff preview"),
            @html.p(
              "Scroll the code horizontally. Line numbers and change markers stay pinned.",
            ),
            @html.button(
              type_="button",
              on_click=emit(ToggleTheme),
              if dark {
                "Light theme"
              } else {
                "Dark theme"
              },
            ),
            @html.button(
              type_="button",
              on_click=emit(ToggleWidth),
              if narrow {
                "Wide layout"
              } else {
                "Narrow layout"
              },
            ),
          ]),
          @html.div(
            class=if narrow { "preview-stage narrow" } else { "preview-stage" },
            [cards],
          ),
        ],
      )
    })
  })
  app.mount("app")
}
