# Add a builtin Wasm skill

Update these files from the repository root. Replace the angle-bracketed
placeholders with the skill's values.

| File | Change |
| --- | --- |
| `share/skills/<skill-id>/<entry.wasm>` | Add the Wasm executable. |
| `share/skills/<skill-id>/SKILL.md` | Add the skill's name, description, usage, and arguments. |
| `share/skills/manifest.json` | Append the registration below to the array. |
| `prompt/generated_default_prompt.mbt` | Regenerate with `just prompt`. |

```json
{
  "id": "<skill-id>",
  "version": "<version>",
  "entry": "<entry.wasm>"
}
```

`id` matches the skill directory name. `version` identifies the bundled
executable. `entry` is the Wasm path relative to the skill directory.

In `SKILL.md`, provide `name` and `description` frontmatter and explain how to
call `run_builtin_skill` using the registered ID:

```json
{"skill":"<skill-id>","args":["<argument>"]}
```

Describe the executable's arguments. Use `$OUTPUT_DIR/<filename>` for output
paths in `args`; the runner expands it to the result directory. Put supporting
files beside `SKILL.md`; the program finds that directory through
`OPENSEEK_SKILL_DIR`.

Run `just prompt`, then rebuild the application package using the commands in
[desktop/BUILD.md](../../desktop/BUILD.md). No MoonBit runner or tool-registration
changes are needed.
