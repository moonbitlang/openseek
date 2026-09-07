///|
/// Only the external events are fixtures. Production boot owns navigation,
/// pending approvals, activity state, and every component below the controller.
extern "js" fn deliver(event : String) -> Bool =
  #| event => document.getElementById("application")?.contentWindow?.__desktopReplay?.deliver(JSON.parse(event)) ?? false

///|
extern "js" fn reset() -> Unit =
  #| () => location.reload()

///|
extern "js" fn is_application_frame() -> Bool =
  #| () => window.parent !== window

///|
extern "js" fn is_openseek() -> Bool =
  #| () => new URLSearchParams(location.search).get("provider") === "openseek"

///|
enum Msg {
  Start
  Ask
  Finish
  Fail
  Reset
}

///|
struct Playback {
  running : Bool
  requested : Bool
  events : Array[String]
  note : String
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
          requested: false,
          events: [],
          note: "Open A in the real sidebar, then start it here.",
        } : Playback),
      update=(state, msg, _emit) => {
        let event : Json = if is_openseek() {
          match msg {
            Reset => {
              reset()
              return (state, @cmd.none)
            }
            Start =>
              {
                "method": "agent.started",
                "params": {
                  "run_id": "run-a",
                  "session": "replay-a",
                  "session_root": "/workspace/.openseek",
                  "model": "deepseek-v4-pro",
                  "max_steps": 1000,
                },
              }
            Ask =>
              {
                "method": "agent.event",
                "params": {
                  "run_id": "run-a",
                  "session": "replay-a",
                  "event": {
                    "event": "approval_requested",
                    "id": "approval-a",
                    "tool_name": "mbtx",
                    "detail": "Task A needs your permission to run project checks.",
                    "body": "moon check",
                  },
                },
              }
            Finish | Fail =>
              {
                "method": "agent.finished",
                "params": {
                  "run_id": "run-a",
                  "status": if msg is Finish {
                    "finished"
                  } else {
                    "failed"
                  },
                  "answer": if msg is Finish {
                    "Task A completed."
                  } else {
                    "Task A failed: replay command failed."
                  },
                },
              }
          }
        } else {
          match msg {
            Reset => {
              reset()
              return (state, @cmd.none)
            }
            Start =>
              {
                "method": "turn/started",
                "params": {
                  "threadId": "replay-a",
                  "turn": {
                    "id": "turn-a",
                    "status": "inProgress",
                    "items": [],
                  },
                },
              }
            Finish | Fail =>
              {
                "method": "turn/completed",
                "params": {
                  "threadId": "replay-a",
                  "turn": {
                    "id": "turn-a",
                    "status": if msg is Finish {
                      "completed"
                    } else {
                      "failed"
                    },
                    "items": [
                      {
                        "type": "agentMessage",
                        "id": "answer-a",
                        "text": if msg is Finish {
                          "Task A completed."
                        } else {
                          "Task A failed: replay command failed."
                        },
                      },
                    ],
                    "error": if msg is Fail {
                      { "message": "Replay command failed" }
                    } else {
                      Json::null()
                    },
                  },
                },
              }
            Ask =>
              {
                "request_id": 42,
                "method": "item/commandExecution/requestApproval",
                "params": {
                  "threadId": "replay-a",
                  "turnId": "turn-a",
                  "itemId": "check-a",
                  "command": "moon check",
                  "cwd": "/workspace",
                  "reason": "Task A needs your permission to run project checks.",
                  "availableDecisions": ["accept", "decline", "cancel"],
                },
              }
          }
        }
        let encoded = event.stringify()
        if deliver(encoded) {
          (
            {
              running: !(msg is Finish || msg is Fail),
              requested: msg is Ask,
              events: [..state.events, encoded],
              note: if msg is Finish || msg is Fail {
                "A has ended. With the panel still expanded, select A: does its unread cue survive until the transcript is visible?"
              } else if msg is Start {
                "Open Task B, show the file panel and expand it, then finish or fail A."
              } else {
                "A is waiting for a decision. Inspect the background UI, then open A to find and answer the actual approval card. Reset and stay on A to compare."
              },
            },
            @cmd.none,
          )
        } else {
          (
            { ..state, note: "Wait for the fixture connection, then retry.", },
            @cmd.none,
          )
        }
      },
    )
    state.view(state => {
      @html.div([
        @html.strong(
          if is_openseek() {
            "OpenSeek · selecting a covered task"
          } else {
            "Codex · selecting a covered task"
          },
        ),
        @html.p(
          "Open A → Start A → open B → show and expand panel → Finish A → select A. Should selecting a hidden transcript count as reading it?",
        ),
        @html.div([
          @html.button(disabled=state.running, on_click=emit(Start), "Start A"),
          @html.button(
            disabled=!state.running || state.requested,
            on_click=emit(Ask),
            "Request approval for A",
          ),
          @html.button(
            disabled=!state.running,
            on_click=emit(Finish),
            "Finish A",
          ),
          @html.button(disabled=!state.running, on_click=emit(Fail), "Fail A"),
          @html.button(on_click=emit(Reset), "Reset replay"),
        ]),
        @html.p(state.note),
        @html.details([
          @html.summary("Synthetic events and limits"),
          @html.p(
            "Application state, navigation, cards and CSS are production code. Only the host is simulated. Codex also sends status changes and request resolutions; OpenSeek commits a transcript event before finishing. Responses use actual RPC handlers. No real command executes. This is not a captured trace and does not cover native notifications, reconnects or stale-response races.",
          ),
          @html.pre(state.events.join("\n\n")),
        ]),
      ])
    })
  })
  controls.mount("replay")
}
