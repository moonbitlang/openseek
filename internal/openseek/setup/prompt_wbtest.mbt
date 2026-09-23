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
