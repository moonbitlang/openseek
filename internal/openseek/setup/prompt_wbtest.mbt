///|
/// Test helper: split a composed system prompt at the environment block so
/// the assertions below can target that block — or the cache-shared prefix
/// before it — without re-implementing its text.
fn split_composed_prompt(prompt : String) -> (String, String) raise {
  // `split_once` yields the text after the heading, so the heading is put
  // back: the returned block still starts where the snapshots expect it to.
  let heading = "## Environment"
  guard prompt.split_once(heading) is Some((prefix, body)) else {
    fail("composed prompt carries no environment block:\n\{prompt}")
  }
  (prefix.to_owned(), "\{heading}\{body}")
}

///|
async test "environment section names the cwd and appends the layout outline" {
  let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
    "OPENSEEK_GLOBAL_SKILLS_DIR": "no-global-skills",
  })
  let (_, section) = split_composed_prompt(
    configured_system_prompt(parsed, Deepseek(V4Flash)),
  )
  let cwd = @fs.realpath(".")
  // Normalise the machine-specific CWD so the snapshot is portable across
  // local dev and CI, while still asserting a stable contiguous layout block.
  let portable = section.replace_all(old=cwd, new="{cwd}")
  // Sibling order follows the directory walk, so pin the header and the
  // nesting (indentation) rather than the order of `cmd/`'s children.
  for
    needle in [
      "Project layout (directories; hidden, build, and vendored dirs omitted):\n",
      "\ncmd/\n", "\n  openseek/\n", "\n  viz_app/\n    e2e/\n",
    ] {
    assert_true(
      portable.contains(needle),
      msg="missing \{needle.escape()} in layout outline:\n\{portable}",
    )
  }
}

///|
async test "environment section reports empty directory layout" {
  @vfs.with_tmpdir(root => {
    let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env={
      "DEEPSEEK": "test-key",
      "OPENSEEK_GLOBAL_SKILLS_DIR": "\{root}/no-global-skills",
    })
    let (_, section) = split_composed_prompt(
      configured_system_prompt(parsed, Deepseek(V4Flash), workspace_root=root),
    )
    let resolved_root = @fs.realpath(root)
    let replaced = section.replace_all(old=resolved_root, new="{resolved_root}")
    inspect(
      replaced,
      content=(
        #|## Environment
        #|
        #|Working directory: {resolved_root}
        #|Relative paths resolve against it; treat it as the workspace root and stay inside it.
        #|Parent and sibling directories belong to other projects. Never pass a cwd you have not verified exists.
        #|Project layout (directories; hidden, build, and vendored dirs omitted):
        #|(empty directory): use `moon new` to create a new project here
      ),
    )
  })
}

///|
async test "environment section inline snapshot for deterministic layout" {
  @vfs.with_tmpdir(root => {
    @vfs.FileSystem({
      "a/one.txt": "x",
      "b/two.txt": "x",
      ".git/objects/o": "x",
      "node_modules/pkg/index.js": "x",
      "_build/out.log": "x",
    }).write_to(root)
    let resolved_root = @fs.realpath(root)
    let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env={
      "DEEPSEEK": "test-key",
      "OPENSEEK_GLOBAL_SKILLS_DIR": "\{root}/no-global-skills",
    })
    let (_, section) = split_composed_prompt(
      configured_system_prompt(parsed, Deepseek(V4Flash), workspace_root=root),
    )
    inspect(
      section,
      content=(
        $|## Environment
        $|
        $|Working directory: \{resolved_root}
        $|Relative paths resolve against it; treat it as the workspace root and stay inside it.
        $|Parent and sibling directories belong to other projects. Never pass a cwd you have not verified exists.
        $|Project layout (directories; hidden, build, and vendored dirs omitted):
        $|a/
        $|b/
      ),
    )
  })
}

///|
async test "configured system prompt can replace and append files" {
  @vfs.with_tmpdir(prefix="openseek-prompt-config-", dir => {
    let prompt_path = "\{dir}/prompt.md"
    let addendum_path = "\{dir}/addendum.md"
    @fs.write_file(prompt_path, "base prompt\n", create_mode=CreateOrTruncate)
    @fs.write_file(addendum_path, "addendum\n", create_mode=CreateOrTruncate)
    let parsed = @testkit.run_matches(
      argv=[
        "--system-prompt-file", prompt_path, "--system-prompt-addendum-file", addendum_path,
        "write", "MoonBit",
      ],
      // The pinned global-skills dir keeps the exact-text assertion below
      // machine-independent: without it, a developer's ~/.openseek/skills
      // would append a ## Skills section (Codex review).
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{dir}/no-global-skills",
      },
    )
    // Environment last: base and addendum form the cache-shared prefix; the
    // per-project cwd is the only divergence point.
    let (prefix, _) = split_composed_prompt(
      configured_system_prompt(parsed, Deepseek(V4Flash)),
    )
    assert_eq(prefix, "base prompt\n\n\naddendum\n\n\n")
  })
}

///|
async test "configured system prompt advertises global skills" {
  @vfs.with_tmpdir(prefix="openseek-global-skills-", dir => {
    @fs.mkdir("\{dir}/skills", recursive=true)
    @fs.write_file(
      "\{dir}/skills/release.md",
      (
        #|---
        #|name: release
        #|description: Cut a release.
        #|---
        #|steps
      ),
      create_mode=CreateOrTruncate,
    )
    let prompt_path = "\{dir}/prompt.md"
    @fs.write_file(prompt_path, "base\n", create_mode=CreateOrTruncate)
    let parsed = @testkit.run_matches(
      argv=["--system-prompt-file", prompt_path, "write", "MoonBit"],
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{dir}/skills",
      },
    )
    let prompt = configured_system_prompt(parsed, Deepseek(V4Flash))
    assert_true(prompt.contains("## Skills"))
    assert_true(
      prompt.contains(
        "release — Cut a release. (file: \{dir}/skills/release.md)",
      ),
    )
  })
}

///|
async test "AGENTS.md context is layered from ancestors to workspace" {
  @vfs.with_tmpdir(prefix="openseek-agents-prompt-", root => {
    let workspace = "\{root}/project/service"
    @fs.mkdir(workspace, recursive=true)
    @fs.write_file(
      "\{root}/AGENTS.md",
      "outer instructions",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{root}/project/AGENTS.md",
      "project instructions",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{workspace}/AGENTS.md",
      "service instructions",
      create_mode=CreateOrTruncate,
    )
    guard agents_prompt_section(workspace) is Some(section) else {
      fail("expected AGENTS.md context")
    }
    inspect(
      section,
      content=(
        $|Project-specific instructions and guidelines:
        $|
        $|<project_instructions path="\{root}/AGENTS.md">
        $|outer instructions
        $|</project_instructions>
        $|
        $|<project_instructions path="\{root}/project/AGENTS.md">
        $|project instructions
        $|</project_instructions>
        $|
        $|<project_instructions path="\{workspace}/AGENTS.md">
        $|service instructions
        $|</project_instructions>
      ),
    )
  })
}

///|
async test "AGENTS.md leading BOM is ignored without changing body content" {
  @vfs.with_tmpdir(prefix="openseek-agents-prompt-bom-", root => {
    let workspace = "\{root}/project"
    @fs.mkdir(workspace, recursive=true)
    @fs.write_file(
      "\{workspace}/AGENTS.md",
      "\u{FEFF}workspace instructions\u{FEFF}tail",
      create_mode=CreateOrTruncate,
    )
    guard agents_prompt_section(workspace) is Some(section) else {
      fail("expected AGENTS.md context")
    }
    assert_true(section.contains("\nworkspace instructions\u{FEFF}tail\n"))
    assert_false(section.contains("\n\u{FEFF}workspace instructions"))
  })
}

///|
async test "AGENTS.md directories are ignored" {
  @vfs.with_tmpdir(prefix="openseek-agents-directory-", root => {
    let workspace = "\{root}/project"
    @fs.mkdir(workspace, recursive=true)
    @fs.mkdir("\{workspace}/AGENTS.md")
    guard agents_prompt_section(workspace) is None else {
      fail("an AGENTS.md directory must not become prompt context")
    }
  })
}

///|
async test "configured system prompt uses the selected workspace root" {
  @vfs.with_tmpdir(prefix="openseek-prompt-workspace-", workspace => {
    let real_workspace = @fs.realpath(workspace)
    @fs.write_file(
      "\{workspace}/prompt.md",
      "workspace prompt\n",
      create_mode=CreateOrTruncate,
    )
    @fs.mkdir("\{workspace}/.openseek/skills", recursive=true)
    @fs.write_file(
      "\{workspace}/.openseek/skills/release.md",
      (
        #|---
        #|name: release
        #|description: Cut a workspace release.
        #|---
        #|steps
      ),
      create_mode=CreateOrTruncate,
    )
    let parsed = @testkit.run_matches(
      argv=[
        "--dir", workspace, "--system-prompt-file", "prompt.md", "write", "MoonBit",
      ],
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{workspace}/no-global-skills",
      },
    )
    let prompt = configured_system_prompt(
      parsed,
      Deepseek(V4Flash),
      workspace_root=real_workspace,
    )
    assert_true(prompt.has_prefix("workspace prompt"))
    assert_true(prompt.contains("Working directory: \{real_workspace}"))
    assert_true(
      prompt.contains(
        "release — Cut a workspace release. (file: \{real_workspace}/.openseek/skills/release.md)",
      ),
    )
  })
}

///|
async test "configured system prompt uses the selected built-in prompt" {
  let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  // Check prompt selection and composition, not the prompt's prose.
  let models : Array[@deepseek.Model] = [Deepseek(V4Flash), Deepseek(V4Pro)]
  for model in models {
    let (prefix, _) = split_composed_prompt(
      configured_system_prompt(parsed, model),
    )
    assert_eq(prefix, "\{@prompt.system_prompt_for_model(model)}\n\n")
  }
}
