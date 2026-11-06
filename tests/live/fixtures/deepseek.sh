#!/usr/bin/env bash
# Independent scenarios for deepseek.md. Each runs in a fresh temporary directory.
case "$1" in
a-real-round-trip-that-finishes)
printf '%s\n' '{"command":"prompt","content":"Call the finish tool immediately with the answer DONE. Use no other tool."}' | openseek.exe serve --model deepseek-flash --max-steps 3 2>/dev/null \
  | moon run --target native -e '---
import {
  "moonbitlang/jsonl@0.2.0",
  "moonbitlang/async",
}
---

async fn main {
  let mut tokens_ok = false
  let mut finished = false
  for value in @jsonl.read_stdin() {
    if value is { "prompt_tokens": Number(n, ..), .. } && n > 0.0 { tokens_ok = true }
    if value is { "answer": String(answer), .. } && answer =~ re"DONE" { finished = true }
  }
  println("real_api_round_trip=\{tokens_ok}")
  println("finished_with_DONE=\{finished}")
}' 2>/dev/null \
  | grep '='
;;
the-expected-lifecycle-events-appear)
printf '%s\n' '{"command":"prompt","content":"Call the finish tool immediately with the answer DONE. Use no other tool."}' | openseek.exe serve --model deepseek-flash --max-steps 3 2>/dev/null \
  | moon run --target native -e '---
import {
  "moonbitlang/jsonl@0.2.0",
  "moonbitlang/async",
}
---

async fn main {
  let lifecycle = ["agent_step", "usage", "agent_finished"]
  let events = Set([])
  for value in @jsonl.read_stdin() {
    if value is { "event": String(event), .. } && lifecycle.contains(event) {
      events.add(event)
    }
  }
  println("events={" + events.iter().join(", ") + "}")
}' 2>/dev/null \
  | grep '='
;;
pulling-a-value-out-of-a-record)
printf '%s\n' '{"command":"prompt","content":"Call the finish tool immediately with the answer DONE. Use no other tool."}' | openseek.exe serve --model deepseek-flash --max-steps 3 2>/dev/null \
  | moon run --target native -e '---
import {
  "moonbitlang/jsonl@0.2.0",
  "moonbitlang/async",
}
---

async fn main {
  for value in @jsonl.read_stdin() {
    if value is { "event": String("agent_finished"), "answer": String(answer), .. } {
      println("final_answer=\{answer}")
    }
  }
}' 2>/dev/null \
  | grep '='
;;
watching-the-agent-use-a-tool)
printf '%s\n' '{"command":"prompt","content":"Use the mbtx tool to run a snippet that prints exactly: openseek-cram. Then call finish with the word done."}' | openseek.exe serve --model deepseek-flash --max-steps 6 2>/dev/null \
  | moon run --target native -e '---
import {
  "moonbitlang/jsonl@0.2.0",
  "moonbitlang/async",
}
---

async fn main {
  let mut used_mbtx = false
  let mut mbtx_output_seen = false
  for value in @jsonl.read_stdin() {
    if value is { "event": String("tool_result"), "tool_name": String("mbtx"), "content": String(out), .. } {
      used_mbtx = true
      if out =~ re"openseek-cram" { mbtx_output_seen = true }
    }
  }
  println("used_mbtx=\{used_mbtx}")
  println("mbtx_output_seen=\{mbtx_output_seen}")
}' 2>/dev/null \
  | grep '='
;;
*) echo "Unknown scenario: $1" >&2; exit 2 ;;
esac
