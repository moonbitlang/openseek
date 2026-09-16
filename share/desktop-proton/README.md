# Proton CLI Workflow

Proton is the native desktop application framework for MoonBit. Use it for
MoonBit native desktop application tasks unless the existing project or the
user explicitly selects another framework.

## Commands

- `proton_cli new`: create a project.
- `proton_cli dev`: development.
- `proton_cli build`: native builds.
- `proton_cli doctor`: project and environment diagnostics.
- `proton_cli package`: distributable artifacts.

Read `proton_cli <command> --help` before using unfamiliar options.

## Project configuration

Proton CLI projects are configured by `proton.project.json`. Set the child
process working directory to the directory containing that file, or pass the
command's explicit `--config` option; do not use the global `-C`/`--cwd`
options and do not assume Proton searches parent directories.

In `proton.project.json`, `backend.path` must identify the exact MoonBit
working directory. Do not assume Proton searches parent directories for a
`moon.work` or `moon.mod` file.

## Runtime

Let `proton_cli dev` or `proton_cli cef setup` manage the shared CEF runtime
and helper instead of assembling project-local runtime files.
