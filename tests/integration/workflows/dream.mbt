///|
/// Scripted child for `dream.mbtx`: validates the consolidation prompt and
/// returns structured JSON plans covering normal apply, dry-run, pruning,
/// `--no-skills`, invalid slugs, over-budget index, and malformed JSON.
fn dream_child(mode : String, arguments : Json) -> Result[Json, String] raise {
  guard arguments
    is {
      "kind": "explore",
      "label": "dream:consolidate",
      "max_steps": 30,
      "input": { "query": String(query), .. },
      ..
    } else {
    fail("unexpected dream start: \{arguments.stringify()}")
  }
  assert_true(query.contains("## Extracted Session Signals"), msg=query)
  if mode == "focus" {
    assert_true(query.contains("User focus"), msg=query)
    assert_true(query.contains("testing conventions"), msg=query)
  }
  if mode == "no-skills" {
    assert_true(query.contains("Skills generation is DISABLED"), msg=query)
  }
  match mode {
    "no-report" => Err("failed: step limit")
    "bad-json" => Ok({ "answer": "not valid json at all", "citations": [] })
    "bad-slug" =>
      Ok({
        "answer": (
          #|{"summary":"escape","memory_index":null,"topics":[{"slug":"../escape","content":"nope"}],"prune_topics":[],"skills":[]}
        ),
        "citations": [],
      })
    "over-budget" => {
      let huge = [ for i in 1..<=160 => "- memory line \{i}" ].join("\n")
      let plan : Json = {
        "summary": "too big",
        "memory_index": huge,
        "topics": [],
        "prune_topics": [],
        "skills": [],
      }
      Ok({ "answer": plan.stringify(), "citations": [] })
    }
    _ => {
      let plan : Json = {
        "summary": "Consolidated test-target preference, pruned stale topic, and distilled release check skill.",
        "memory_index": "# Project Memory\n- Prefer native target for fast package tests (topics/testing.md)\n- Fast native check and test loop (skills/fast-native-check/SKILL.md)",
        "topics": [
          {
            "slug": "testing",
            "content": "# Testing Notes\n\n- Run `moon test --target native` first for fast feedback.",
          },
        ],
        "prune_topics": ["obsolete"],
        "skills": [
          {
            "slug": "fast-native-check",
            "name": "fast-native-check",
            "description": "Run fast native check and test loop before formatting",
            "body": "# Fast Native Check\n\n1. Run `moon check --target native`.\n2. Run `moon test --target native`.",
          },
        ],
      }
      Ok({ "answer": "```json\n\{plan.stringify()}\n```", "citations": [] })
    }
  }
}

///|
/// Exercise `share/workflow/dream.mbtx` compiled to Wasm against the fake PTC
/// host: apply + watermark skip on second run, dry-run, pruning, `--no-skills`,
/// focus forwarding, `--no-llm`, missing host, refused start, bad JSON, invalid
/// slug rejection, and MEMORY.md line-budget enforcement.
async fn verify_dream(root : String, temp : String) -> Unit {
  let artifact = compile(root, temp, "dream")
  for
    mode in [
      "apply", "dry-run", "no-skills", "focus", "no-llm", "missing", "busy", "no-report",
      "bad-json", "bad-slug", "over-budget",
    ] {
    let ws = temp + "/dream-ws-" + mode
    let sess_dir = ws + "/.openseek/sessions/sess-1"
    let topics_dir = ws + "/.openseek/memory/topics"
    @fs.mkdir(sess_dir, recursive=true)
    @fs.mkdir(topics_dir, recursive=true)
    write(topics_dir + "/obsolete.md", "# Old\n")
    write(
      sess_dir + "/openseek_session-sess-1.jsonl",
      (
        #|{"version":1,"id":"sess-1","system_prompt":"test"}
        #|{"sequence":1,"ts":1758700001000,"item":{"kind":"user","payload":{"content":"run tests"}}}
        #|{"sequence":2,"ts":1758700002000,"item":{"kind":"tool_result","payload":{"tool_call_id":"c1","tool_name":"mbtx","content":"js test failed","is_error":true}}}
        #|{"sequence":3,"ts":1758700003000,"item":{"kind":"user","payload":{"content":"always run native tests first"}}}
        #|{"sequence":4,"ts":1758700004000,"item":{"kind":"tool_result","payload":{"tool_call_id":"c2","tool_name":"mbtx","content":"passed","is_error":false}}}
        #|{"sequence":5,"ts":1758700005000,"item":{"kind":"tool_result","payload":{"tool_call_id":"c3","tool_name":"edit","content":"ok","is_error":false}}}
        #|{"sequence":6,"ts":1758700006000,"item":{"kind":"terminal","payload":{"kind":"finished","message":"done"}}}
        #|
      ),
    )
    let host = fake_host("dream", mode)
    let args : Array[String] = match mode {
      "dry-run" => ["--dry-run"]
      "no-skills" => ["--no-skills"]
      "focus" => ["--", "testing", "conventions"]
      "no-llm" => ["--no-llm"]
      _ => []
    }
    let use_host = match mode {
      "no-llm" | "missing" => None
      _ => Some(host)
    }
    let (code, output) = run_against(use_host, artifact, args, cwd=ws)
    let succeeds = mode
      is ("apply" | "dry-run" | "no-skills" | "focus" | "no-llm")
    assert_eq(code == 0, succeeds, msg="mode=\{mode} output=\{output}")
    match mode {
      "apply" => {
        assert_eq(host.starts.length(), 1)
        assert_true(
          output.contains("memory=1 topics=1 pruned=1 skills=1"),
          msg=output,
        )
        let index = @fs.read_text(ws + "/.openseek/memory/MEMORY.md")
        assert_true(index.contains("topics/testing.md"), msg=index)
        assert_true(@fs.exists(ws + "/.openseek/memory/topics/testing.md"))
        assert_false(@fs.exists(ws + "/.openseek/memory/topics/obsolete.md"))
        let skill = @fs.read_text(
          ws + "/.openseek/memory/skills/fast-native-check/SKILL.md",
        )
        assert_true(
          skill.has_prefix("---\nname: \"fast-native-check\""),
          msg=skill,
        )
        assert_false(@fs.exists(ws + "/.openseek/skills"))
        assert_true(@fs.exists(ws + "/.openseek/dream-state.json"))
        // Second run with no new sessions is an instant up-to-date no-op (0 subagents).
        let second_host = fake_host("dream", "apply")
        let (code2, out2) = run_against(Some(second_host), artifact, [], cwd=ws)
        assert_eq(code2, 0, msg=out2)
        assert_eq(second_host.starts.length(), 0)
        assert_true(out2.contains("Up to date"), msg=out2)
      }
      "dry-run" => {
        assert_eq(host.starts.length(), 1)
        assert_true(output.contains("dry-run"), msg=output)
        assert_false(@fs.exists(ws + "/.openseek/memory/MEMORY.md"))
        assert_true(@fs.exists(ws + "/.openseek/memory/topics/obsolete.md"))
        assert_false(@fs.exists(ws + "/.openseek/dream-state.json"))
      }
      "no-skills" => {
        assert_true(output.contains("skills=0"), msg=output)
        assert_true(@fs.exists(ws + "/.openseek/memory/MEMORY.md"))
        assert_false(
          @fs.exists(ws + "/.openseek/memory/skills/fast-native-check/SKILL.md"),
        )
      }
      "focus" => assert_eq(host.starts.length(), 1)
      "no-llm" => {
        assert_eq(host.starts.length(), 0)
        assert_true(output.contains("tokens=0"), msg=output)
      }
      "missing" => assert_true(output.contains("TransportError"), msg=output)
      "busy" => assert_true(output.contains("--no-llm"), msg=output)
      "no-report" =>
        assert_true(output.contains("did not submit a plan"), msg=output)
      "bad-json" => {
        assert_true(output.contains("invalid JSON"), msg=output)
        assert_false(@fs.exists(ws + "/.openseek/dream-state.json"))
      }
      "bad-slug" => {
        assert_true(output.contains("invalid topic slug"), msg=output)
        assert_false(@fs.exists(ws + "/.openseek/dream-state.json"))
      }
      "over-budget" => {
        assert_true(output.contains("exceeds 150 lines"), msg=output)
        assert_false(@fs.exists(ws + "/.openseek/memory/MEMORY.md"))
      }
      _ => ()
    }
    println("dream: \{mode} passed")
  }
}
