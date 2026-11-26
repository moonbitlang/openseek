///|
async test "AGENTS.md discovery only reads the workspace" {
  @vfs.with_tmpdir(prefix="openseek-agents-prompt-", root => {
    let workspace = "\{root}/project/service"
    @fs.mkdir(workspace, recursive=true)
    @fs.write_text(
      "\{root}/AGENTS.md",
      "outer instructions",
      create_mode=CreateOrTruncate,
    )
    @fs.write_text(
      "\{root}/project/AGENTS.md",
      "project instructions",
      create_mode=CreateOrTruncate,
    )
    @fs.write_text(
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
        $|<project_instructions path="\{workspace}/AGENTS.md">
        $|service instructions
        $|</project_instructions>
      ),
    )
    @fs.remove("\{workspace}/AGENTS.md")
    assert_true(agents_prompt_section(workspace) is None)
  })
}

///|
async test "AGENTS.md leading BOM is ignored without changing body content" {
  @vfs.with_tmpdir(prefix="openseek-agents-prompt-bom-", root => {
    let workspace = "\{root}/project"
    @fs.mkdir(workspace, recursive=true)
    @fs.write_text(
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
async test "MEMORY.md reads workspace index, strips BOM, and ignores missing or directory" {
  @vfs.with_tmpdir(prefix="openseek-memory-prompt-", root => {
    let workspace = "\{root}/project"
    let mem_dir = "\{workspace}/.openseek/memory"
    @fs.mkdir(mem_dir, recursive=true)
    assert_true(memory_prompt_section(workspace) is None)
    // Directory named MEMORY.md is ignored.
    @fs.mkdir("\{mem_dir}/MEMORY.md")
    assert_true(memory_prompt_section(workspace) is None)
    @fs.remove("\{mem_dir}/MEMORY.md", recursive=true)
    // Blank file is ignored.
    @fs.write_text(
      "\{mem_dir}/MEMORY.md",
      "   \n\t\n",
      create_mode=CreateOrTruncate,
    )
    assert_true(memory_prompt_section(workspace) is None)
    // Normal file with UTF-8 BOM.
    @fs.write_text(
      "\{mem_dir}/MEMORY.md",
      "\u{FEFF}- Always run moon fmt before shipping (topics/shipping.md)",
      create_mode=CreateOrTruncate,
    )
    guard memory_prompt_section(workspace) is Some(section) else {
      fail("expected MEMORY.md section")
    }
    assert_true(
      section.contains("<project_memory path=\"\{mem_dir}/MEMORY.md\">"),
      msg=section,
    )
    assert_true(
      section.contains("\n- Always run moon fmt before shipping"),
      msg=section,
    )
    assert_false(section.contains("\u{FEFF}"), msg=section)
    assert_false(section.contains("[truncated"), msg=section)
  })
}

///|
test "truncate_memory enforces both line and UTF-8 byte ceilings safely" {
  // Line ceiling: 205 lines truncated to 200.
  let many = [ for i in 1..<=205 => "- item \{i}" ].join("\n")
  let by_lines = truncate_memory(
    many,
    max_lines=MemoryMaxLines,
    max_bytes=MemoryMaxBytes,
  )
  assert_true(by_lines.truncated)
  assert_eq(by_lines.shown_lines, 200)
  assert_eq(by_lines.total_lines, 205)
  assert_true(by_lines.body.contains("- item 200"))
  assert_false(by_lines.body.contains("- item 201"))
  // Byte ceiling with 3-byte UTF-8 Chinese chars: never splits a codepoint.
  let wide = String::make(100, '记')
  let by_bytes = truncate_memory(wide, max_lines=10, max_bytes=10)
  assert_true(by_bytes.truncated)
  assert_eq(by_bytes.shown_lines, 1)
  assert_eq(by_bytes.used_bytes, 9)
  assert_eq(by_bytes.body, "记记记")
}
