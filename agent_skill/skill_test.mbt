///|
async fn write_skill(path : String, text : String) -> Unit {
  @fs.write_file(path, text, create_mode=CreateOrTruncate)
}

///|
async test "discovery reads flat files and SKILL.md directories, sorted" {
  @vfs.with_tmpdir(prefix="openseek-skills-", dir => {
    write_skill(
      "\{dir}/zeta.md",
      (
        #|---
        #|name: zeta-protocol
        #|description: How to zeta.
        #|---
        #|Body text.
      ),
    )
    @fs.mkdir("\{dir}/alpha", recursive=true)
    write_skill(
      "\{dir}/alpha/SKILL.md",
      (
        #|---
        #|description: Alpha steps.
        #|---
        #|Steps.
      ),
    )
    // No frontmatter at all: still listed under its file stem.
    write_skill("\{dir}/bare.md", "Just instructions, no header.")
    // A dotted directory name survives intact ("node.js", not "node").
    @fs.mkdir("\{dir}/node.js", recursive=true)
    write_skill("\{dir}/node.js/SKILL.md", "Node skill body.")
    // A non-skill directory and a stray file are ignored.
    @fs.mkdir("\{dir}/not-a-skill", recursive=true)
    write_skill("\{dir}/notes.txt", "not markdown")
    let skills = @agent_skill.discover_skills(dir)
    assert_eq(skills.length(), 4)
    let prompt = @agent_skill.skills_prompt_section(skills).unwrap()
    // Sorted by name (String order is length-first, so "bare" precedes
    // "alpha"); the SKILL.md layout names itself after its directory
    // ("node.js", not "node").
    inspect(
      prompt,
      content=(
        $|## Skills
        $|
        $|Reusable skills are available. When a task matches one, read its file through mbtx (filename="@builtin/read.mbtx", args=[the file path]) BEFORE doing the work, then follow it. Listed skill files are pre-approved reads even when they sit outside the working directory.
        $|- bare — (no description) (file: \{dir}/bare.md)
        $|- alpha — Alpha steps. (file: \{dir}/alpha/SKILL.md)
        $|- node.js — (no description) (file: \{dir}/node.js/SKILL.md)
        $|- zeta-protocol — How to zeta. (file: \{dir}/zeta.md)
      ),
    )
  })
}

///|
async test "a malformed frontmatter never hides the skill" {
  @vfs.with_tmpdir(prefix="openseek-skills-malformed-", dir => {
    // Opening --- with no closing fence: keys still parse until EOF.
    write_skill(
      "\{dir}/open.md",
      (
        #|---
        #|name: still-found
        #|no colon line
      ),
    )
    let skills = @agent_skill.discover_skills(dir)
    assert_eq(skills.length(), 1)
    assert_eq(skills[0].name(), "still-found")
  })
}

///|
async test "workspace skills shadow same-named global skills on merge" {
  @vfs.with_tmpdir(prefix="openseek-skills-global-", global_dir => {
    @vfs.with_tmpdir(prefix="openseek-skills-workspace-", workspace_dir => {
      write_skill(
        "\{global_dir}/deploy.md",
        (
          #|---
          #|description: Generic deploy steps.
          #|---
        ),
      )
      write_skill("\{global_dir}/lint.md", "Global lint steps.")
      write_skill(
        "\{workspace_dir}/deploy.md",
        (
          #|---
          #|description: This project's deploy steps.
          #|---
        ),
      )
      write_skill("\{workspace_dir}/triage.md", "Workspace triage steps.")
      let merged = @agent_skill.merge_skills(
        @agent_skill.discover_skills(global_dir),
        overrides=@agent_skill.discover_skills(workspace_dir),
      )
      // "deploy" appears once — the workspace copy; "lint" survives from the
      // global library; everything stays name-sorted across both sources.
      assert_eq(merged.length(), 3)
      assert_eq(merged[0].name(), "lint")
      assert_eq(merged[0].path(), "\{global_dir}/lint.md")
      assert_eq(merged[1].name(), "deploy")
      assert_eq(merged[1].description(), "This project's deploy steps.")
      assert_eq(merged[1].path(), "\{workspace_dir}/deploy.md")
      assert_eq(merged[2].name(), "triage")
    })
  })
}

///|
async test "a missing skills directory is an empty library" {
  let skills = @agent_skill.discover_skills("/nonexistent/openseek-skills")
  assert_eq(skills.length(), 0)
  assert_true(@agent_skill.skills_prompt_section(skills) is None)
}

///|
async test "the prompt section lists usage, names, and paths" {
  @vfs.with_tmpdir(prefix="openseek-skills-prompt-", dir => {
    write_skill(
      "\{dir}/release.md",
      (
        #|---
        #|name: release
        #|description: Cut a release of this project.
        #|---
        #|1. bump version
      ),
    )
    let skills = @agent_skill.discover_skills(dir)
    guard @agent_skill.skills_prompt_section(skills) is Some(section) else {
      fail("expected a section")
    }
    inspect(
      section,
      content=(
        $|## Skills
        $|
        $|Reusable skills are available. When a task matches one, read its file through mbtx (filename="@builtin/read.mbtx", args=[the file path]) BEFORE doing the work, then follow it. Listed skill files are pre-approved reads even when they sit outside the working directory.
        $|- release — Cut a release of this project. (file: \{dir}/release.md)
      ),
    )
  })
}
