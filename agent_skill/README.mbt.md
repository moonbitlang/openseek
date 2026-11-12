# agent_skill

Workspace skills: markdown playbooks the agent pulls into context on demand.

A skill is a markdown file under `.openseek/skills/` — either `<name>.md` or
`<name>/SKILL.md` for skills that ship companion files — with optional
frontmatter:

```markdown
---
name: release
description: How to cut a release of this project.
---
1. Bump the version in moon.mod
2. ...
```

The engine discovers skills at startup and appends a `## Skills` section to
the system prompt listing each skill's name, description, and path, with the
instruction to read the file through `mbtx` and `@builtin/read.mbtx` before doing matching work. The body stays
out of the prompt until the model decides it is relevant, so a large skill
library costs a few listing lines per request, not its full text. Frontmatter
is YAML, read the way the skill registry validates it when a skill is
published, so quoted values, comments and block-scalar descriptions list as
their YAML values. Missing, unclosed or malformed frontmatter falls back to the
file stem and an empty description; a missing directory is simply an empty
library.

Libraries feed the listing in order: any `--skills-dir` given, the user-level
(global) one under `$HOME/.openseek/skills` (`%USERPROFILE%/.openseek/skills`
on Windows; override with `--global-skills-dir` /
`OPENSEEK_GLOBAL_SKILLS_DIR`), and the workspace one under `.openseek/skills`.
`merge_skills` combines them, each shadowing same-named skills of the ones
before it, so a project can specialize a shared playbook without renaming it.

A `<name>/SKILL.md` skill may keep an `mcp.json` beside it naming MCP servers
it brings; `Skill::mcp_config_path` is its path. The engine connects those servers
when a script first reaches them (see the repository README).
