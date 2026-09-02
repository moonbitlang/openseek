///|
/// Journal → HTML: render any workflow journal as a self-contained
/// report — the attempt ledger (status, steps, token costs) plus a
/// DERIVED dataflow graph: an edge exists where one agent's recorded
/// output appears verbatim inside a later agent's input. Dynamic
/// workflows declare no graph, so none is stored; content recovers it.
///
///   moon run workflow/viz -- <journal.jsonl> [out.html] [--watch]
///   moonx bobzhang/workflow/viz <journal.jsonl> [out.html] [--watch]
///
/// `--watch` re-renders every 2 seconds and the page auto-refreshes —
/// a live view of a RUNNING workflow's completions.
async fn main {
  run() catch {
    error => println("viz failed: \{error}")
  }
}

///|
async fn run() -> Unit {
  let args = @env.args()
  let positional : Array[String] = []
  let mut watch = false
  for index, arg in args {
    if index == 0 {
      continue
    }
    if arg == "--watch" {
      watch = true
    } else {
      positional.push(arg)
    }
  }
  guard positional.length() >= 1 else {
    println("usage: viz <journal.jsonl> [out.html] [--watch]")
    return
  }
  let path = positional[0]
  let out = if positional.length() >= 2 {
    positional[1]
  } else {
    "\{path}.html"
  }
  for ;; {
    render(path, out, watch) catch {
      error =>
        if watch {
          println("(\{error} — retrying)")
        } else {
          raise error
        }
    }
    guard watch else { break }
    @async.sleep(2_000)
  }
}

///|
/// READ-ONLY journal parse. Deliberately not `Journal::load`: load
/// REPAIRS torn tails on disk, and a watcher must never rewrite a file
/// a running workflow is appending to. Unparsable lines (the live
/// writer's torn tail) are simply skipped for this tick.
async fn read_entries(path : String) -> Array[@workflow.JournalEntry] {
  let entries : Array[@workflow.JournalEntry] = []
  guard @fs.exists(path) else { return entries }
  let text = @fs.read_file(path).text() catch { _ => return entries }
  for line in text.split("\n") {
    let line = line.trim()
    if line.is_empty() {
      continue
    }
    let parsed : @workflow.JournalEntry? = try {
      match @json.parse(line.to_owned()) {
        { "v": Number(1, ..), "e": entry, .. } => Some(@json.from_json(entry))
        _ => None
      }
    } catch {
      _ => None
    }
    if parsed is Some(entry) {
      entries.push(entry)
    }
  }
  entries
}

///|
async fn render(path : String, out : String, watch : Bool) -> Unit {
  let entries = read_entries(path)
  guard entries.length() > 0 else {
    println("journal \{path} holds no entries yet")
    return
  }

  // Derive dataflow: output-of(i) embedded in input-of(j), i < j. The
  // probe is JSON-escaped through the encoder itself, so it matches how
  // the text actually appears inside a stringified input.
  let values : Array[String] = entries.map(entry => answer_of(entry.outcome))
  let inputs : Array[String] = entries.map(entry => entry.call.input.stringify())
  let edges : Array[(Int, Int)] = []
  for j, input in inputs {
    for i in 0..<j {
      let value = values[i]
      if value.length() > 60 {
        let quoted = Json::string(clip(value, 50)).stringify()
        let probe = quoted[1:quoted.length() - 1]
        if input.contains(probe.to_owned()) {
          edges.push((i, j))
        }
      }
    }
  }

  // ---- the ledger rows and graph geometry ----
  let mut max_tokens = 1
  for entry in entries {
    max_tokens = max_tokens.max(tokens_of(entry.outcome))
  }
  let rows = StringBuilder()
  for index, entry in entries {
    let finished = entry.outcome is Finished(..)
    let pill = if finished {
      "<span class=\"pill ok\">Finished</span>"
    } else {
      "<span class=\"pill bad\">DidNotFinish</span>"
    }
    let tokens = tokens_of(entry.outcome)
    let width = 100 * tokens / max_tokens
    let detail = escape(
      match entry.outcome {
        Finished(value~, ..) => clip(answer_of_value(value), 180)
        DidNotFinish(failure~, ..) => "\{failure}"
      },
    )
    rows.write_string(
      "<tr title=\"\{detail}\"><td class=\"num\">\{index + 1}</td><td class=\"lbl\">\{escape(entry.call.label)}</td><td>\{pill}</td><td class=\"num\">\{steps_of(entry.outcome)}</td><td class=\"barcell\"><div class=\"bar\"><div class=\"track\"><div class=\"fill\" style=\"width:\{width.max(if tokens > 0 { 2 } else { 0 })}%\"></div></div><span class=\"val\">\{tokens}</span></div></td></tr>",
    )
  }
  let graph = StringBuilder()
  let row_h = 40
  let height = entries.length() * row_h + 16
  graph.write_string(
    "<svg viewBox=\"0 0 460 \{height}\" role=\"img\" aria-label=\"Derived dataflow: an edge means a later agent's input embeds an earlier agent's output\"><defs><marker id=\"af\" viewBox=\"0 0 8 8\" refX=\"7\" refY=\"4\" markerWidth=\"6.5\" markerHeight=\"6.5\" orient=\"auto\"><path d=\"M0,0 L8,4 L0,8 z\" fill=\"var(--accent)\"/></marker></defs>",
  )
  for edge in edges {
    let (a, b) = edge
    let y1 = 22 + a * row_h
    let y2 = 22 + b * row_h
    let spread = 40 + (b - a) * 26
    graph.write_string(
      "<path d=\"M 212 \{y1} C \{212 + spread} \{y1}, \{212 + spread} \{y2}, 218 \{y2}\" fill=\"none\" stroke=\"var(--accent)\" stroke-width=\"1.4\" opacity=\"0.75\" marker-end=\"url(#af)\"/>",
    )
  }
  for index, entry in entries {
    let y = 22 + index * row_h
    let color = if entry.outcome is Finished(..) {
      "var(--replay)"
    } else {
      "var(--fail)"
    }
    graph.write_string(
      "<circle cx=\"200\" cy=\"\{y}\" r=\"7\" fill=\"\{color}\" fill-opacity=\"0.18\" stroke=\"\{color}\" stroke-width=\"1.6\"/><text x=\"188\" y=\"\{y + 4}\" text-anchor=\"end\" font-size=\"12\" font-family=\"ui-monospace,Menlo,monospace\" fill=\"var(--ink)\">\{escape(entry.call.label)}</text>",
    )
  }
  graph.write_string("</svg>")
  let refresh = if watch {
    "<meta http-equiv=\"refresh\" content=\"2\">"
  } else {
    ""
  }
  let outputs = StringBuilder()
  for index, entry in entries {
    let finished = entry.outcome is Finished(..)
    let body = escape(
      match entry.outcome {
        Finished(value~, ..) => answer_of_value(value)
        DidNotFinish(failure~, ..) => "\{failure}"
      },
    )
    let mark = if finished { "ok" } else { "bad" }
    outputs.write_string(
      "<details\{if index == entries.length() - 1 { " open" } else { "" }}><summary><span class=\"num\">\{index + 1}</span> <span class=\"lbl\">\{escape(entry.call.label)}</span> <span class=\"pill \{mark}\">\{if finished { "Finished" } else { "DidNotFinish" }}</span></summary><div class=\"out\">\{body}</div></details>",
    )
  }
  let page = "<!doctype html><meta charset=\"utf-8\">" +
    refresh +
    "<title>journal: \{escape(path)}</title>" +
    style +
    "<div class=\"wrap\"><h1>\{escape(path)}</h1><p class=\"dek\">\{entries.length()} recorded attempt(s) · \{edges.length()} dataflow edge(s) derived from content. A journal records LIVE outcomes only — repeated labels are re-attempts or cascade generations; replays are served, never re-appended.</p><div class=\"grid\"><div class=\"panel\"><h2>Ledger</h2><div style=\"overflow-x:auto\"><table><tr><th>#</th><th>agent</th><th>outcome</th><th style=\"text-align:right\">steps</th><th>tokens</th></tr>" +
    rows.to_string() +
    "</table></div></div><div class=\"panel\"><h2>Derived dataflow</h2><div style=\"overflow-x:auto\">" +
    graph.to_string() +
    "</div></div></div><div class=\"panel\" style=\"margin-top:1.3rem\"><h2>Outputs</h2>" +
    outputs.to_string() +
    "</div></div>"
  @fs.write_file(out, page)
  println(
    "wrote \{out}: \{entries.length()} entries, \{edges.length()} derived edge(s)",
  )
}

///|
fn tokens_of(outcome : @workflow.AgentOutcome) -> Int {
  let attempt = match outcome {
    Finished(attempt~, ..) => Some(attempt)
    DidNotFinish(attempt~, ..) => attempt
  }
  match attempt {
    Some(attempt) => attempt.prompt_tokens + attempt.completion_tokens
    None => 0
  }
}

///|
fn steps_of(outcome : @workflow.AgentOutcome) -> Int {
  match outcome {
    Finished(attempt~, ..) => attempt.steps_used
    DidNotFinish(attempt=Some(attempt), ..) => attempt.steps_used
    DidNotFinish(attempt=None, ..) => 0
  }
}

///|
fn answer_of(outcome : @workflow.AgentOutcome) -> String {
  match outcome {
    Finished(value~, ..) => answer_of_value(value)
    DidNotFinish(..) => ""
  }
}

///|
fn answer_of_value(value : Json) -> String {
  match value {
    { "answer": String(text), .. } => text
    other => other.stringify()
  }
}

///|
fn clip(text : String, limit : Int) -> String {
  let out = StringBuilder()
  let mut count = 0
  for ch in text {
    if count >= limit {
      break
    }
    out.write_char(ch)
    count += 1
  }
  out.to_string()
}

///|
fn escape(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    match ch {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
let style : String =
  #|<style>
  #|:root{--paper:#FAFAF7;--ink:#23272E;--soft:#5A6069;--line:#DDDCD4;--card:#F1F0EA;--replay:#1C8A5B;--spend:#A96F24;--fail:#B04A3E;--accent:#2F5FA8}
  #|@media (prefers-color-scheme: dark){:root{--paper:#14161A;--ink:#D8DCE2;--soft:#99A1AC;--line:#2C3038;--card:#1B1E24;--replay:#3FBF8A;--spend:#D9A05B;--fail:#D97D6F;--accent:#7CA5DE}}
  #|body{margin:0;color:var(--ink);background:var(--paper);font:15px/1.55 "Avenir Next",Seravek,"Segoe UI",system-ui,sans-serif}
  #|.wrap{max-width:62rem;margin:0 auto;padding:2.2rem 1.25rem 3rem}
  #|h1{font-size:1.3rem;font-weight:700;margin:0 0 .3rem;font-family:ui-monospace,Menlo,monospace}
  #|.dek{color:var(--soft);margin:0 0 1.3rem;max-width:75ch}
  #|.grid{display:grid;grid-template-columns:minmax(0,1fr);gap:1.3rem}
  #|@media(min-width:880px){.grid{grid-template-columns:minmax(0,3fr) minmax(0,2fr)}}
  #|.panel{border:1px solid var(--line);border-radius:10px;background:var(--card);padding:1rem 1.1rem;min-width:0}
  #|.panel h2{font-size:.78rem;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--soft);margin:0 0 .8rem}
  #|table{border-collapse:collapse;width:100%;font-size:13px}
  #|th{text-align:left;color:var(--soft);font-weight:600;padding:4px 10px 6px 0;border-bottom:1px solid var(--line)}
  #|td{padding:7px 10px 7px 0;border-bottom:1px solid var(--line);vertical-align:middle}
  #|tr:last-child td{border-bottom:none}
  #|.num{font-variant-numeric:tabular-nums;text-align:right;padding-right:0;color:var(--soft)}
  #|.lbl{font-family:ui-monospace,Menlo,monospace;font-size:12px;white-space:nowrap}
  #|.pill{display:inline-block;font-weight:600;font-size:10.5px;letter-spacing:.04em;padding:3px 8px;border-radius:999px;border:1px solid;white-space:nowrap}
  #|.pill.ok{color:var(--replay);border-color:var(--replay)}
  #|.pill.bad{color:var(--fail);border-color:var(--fail)}
  #|.barcell{width:34%;min-width:120px}
  #|.bar{display:flex;align-items:center;gap:8px}
  #|.bar .track{flex:1;height:10px;position:relative}
  #|.bar .fill{position:absolute;inset:0 auto 0 0;border-radius:0 4px 4px 0;background:var(--spend);min-width:2px}
  #|.bar .val{font-variant-numeric:tabular-nums;font-size:12px;color:var(--soft);white-space:nowrap}
  #|svg{max-width:100%;height:auto;display:block}
  #|details{border-bottom:1px solid var(--line);padding:6px 0}
  #|details:last-child{border-bottom:none}
  #|summary{cursor:pointer;display:flex;gap:10px;align-items:center}
  #|summary::marker{color:var(--soft)}
  #|.out{white-space:pre-wrap;font-size:13.5px;line-height:1.6;color:var(--ink);padding:10px 4px 8px 22px;max-width:75ch}
  #|</style>
