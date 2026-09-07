///|
extern "js" fn act(action : String) -> String =
  #| action => document.getElementById("application")?.contentWindow?.__desktopReplay?.act(action) ?? "Wait for the application to load."

///|
extern "js" fn reset() -> Unit =
  #| () => location.reload()

///|
extern "js" fn narrow(value : Bool) -> Unit =
  #| value => document.getElementById("application").style.width = value ? "390px" : "100%"

///|
extern "js" fn is_application_frame() -> Bool =
  #| () => window.parent !== window

///|
enum Msg {
  Start
  Tool
  Stream
  Finish
  Fail
  Width
  Reset
}

///|
struct Playback {
  running : Bool
  tool_shown : Bool
  streamed : Bool
  narrow : Bool
  events : String
} derive(Eq)

///|
fn main {
  if is_application_frame() {
    @frontend.boot()
    return
  }
  let controls = @rabbita.new(() => {
    let (state, emit) = @rabbita.create_state(
      (
        {
          running: false,
          tool_shown: false,
          streamed: false,
          narrow: false,
          events: "",
        } : Playback),
      update=(state, msg, _emit) => {
        match msg {
          Reset => {
            reset()
            (state, @cmd.none)
          }
          Width => {
            narrow(!state.narrow)
            ({ ..state, narrow: !state.narrow, }, @cmd.none)
          }
          _ => {
            let action = match msg {
              Start => "start"
              Tool => "tool"
              Stream => "stream"
              Finish => "finish"
              Fail => "fail"
              Width => "width"
              Reset => "reset"
            }
            let events = act(action)
            (
              {
                ..state,
                running: !(msg is Finish || msg is Fail),
                tool_shown: if msg is Start {
                  false
                } else {
                  state.tool_shown || msg is Tool
                },
                streamed: if msg is Start {
                  false
                } else {
                  state.streamed || msg is Stream
                },
                events,
              },
              @cmd.none,
            )
          }
        }
      },
    )
    state.view(state => {
      @html.div([
        @html.strong("Quiet transcript · real-component replay"),
        @html.p(
          "1. Open Transcript review in the sidebar. 2. Read the two exchanges. 3. Start next exchange → Show tool activity → Stream next chunk → Finish or Fail. Repeat for the other outcome.",
        ),
        @html.div([
          @html.button(
            disabled=state.running,
            on_click=emit(Start),
            "Start next exchange",
          ),
          @html.button(
            disabled=!state.running || state.tool_shown || state.streamed,
            on_click=emit(Tool),
            "Show tool activity",
          ),
          @html.button(
            disabled=!state.running,
            on_click=emit(Stream),
            "Stream next chunk",
          ),
          @html.button(disabled=!state.running, on_click=emit(Finish), "Finish"),
          @html.button(disabled=!state.running, on_click=emit(Fail), "Fail"),
          @html.button(
            on_click=emit(Width),
            if state.narrow {
              "Wide viewport"
            } else {
              "Narrow viewport · 390px"
            },
          ),
          @html.button(on_click=emit(Reset), "Reset"),
        ]),
        @html.p(
          if state.running {
            "Running: inspect the provisional response before ending it. Stream next chunk advances manually."
          } else {
            "Idle: final answers have the existing copy action and a thin line. Failure keeps its own error presentation."
          },
        ),
        @html.details([
          @html.summary("Synthetic events and scope"),
          @html.p(
            "OpenSeek host events and history are fixtures; no command runs. The real MoonBit app renders messages, tools, streaming and errors. Only transcript spacing and end-line CSS are experimental. Narrow viewport resizes the actual app iframe; use Hide sidebar if needed. Codex, reconnects and native notifications are outside this replay.",
          ),
          @html.pre(state.events),
        ]),
      ])
    })
  })
  controls.mount("replay")
}
