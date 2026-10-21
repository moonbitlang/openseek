# Proton Desktop Applications

Proton builds native desktop applications with a web frontend and a MoonBit
native backend. Use it for MoonBit desktop tasks unless the existing project
or the user selects another framework.

## Start a project

Use `proton_cli new my-app --yes` to generate a working project. Read its
`README.md` and `AGENTS.md` before changing the generated code. For an existing
application, start with its instructions and `proton.project.json`.

The default `isomorphic` template contains a Rabbita web frontend, a Proton
native backend, and shared command definitions. The frontend handles the UI;
the backend implements native operations. Use
`proton_cli new my-app --template minimal --yes` for a single MoonBit module
with inline HTML.

From the generated project directory:

1. Run `moon update` to resolve dependencies.
2. Run `proton_cli cef setup` to prepare CEF, the embedded browser runtime.
3. Run `proton_cli dev` to launch the application during development.

Let the CLI manage the runtime and helper; do not assemble them by hand.

## Common commands

- `proton_cli dev`: start the configured frontend and native application.
- `proton_cli build`: build the frontend and native backend without launching.
- `proton_cli package --release`: create a release application package.
- `proton_cli doctor`: inspect the project configuration and local environment.

Use `moon check` and `moon test` for MoonBit code feedback, and launch the
application with `proton_cli dev` to check its UI and native behavior.

## Basic concepts and examples

Read [the small examples](examples.md) for a complete minimal window and a
page that calls a command, receives an event, and uses the clipboard extension.
The examples include package imports and expected behavior.

| Topic | Where to start |
| --- | --- |
| Application and windows | `@proton.html`, `url`, `file`, or `asset` selects the initial page; `WindowConfig` sets window options; use `..` for App configuration and `.` for `run`. See [windows](https://github.com/moonbit-community/proton/blob/main/website/content/en/introduction/application-api.md). |
| Frontend, backend, and shared types | The frontend renders the UI; the native backend performs host operations; shared command and event types connect them. Follow the generated isomorphic project and [Todo tutorial](https://github.com/moonbit-community/proton/blob/main/website/content/en/tutorial/isomorphic.md). |
| Commands and events | Commands request work and return a result. Events notify listeners without a response. See [examples](examples.md#commands-events-and-an-extension). |
| Extensions and capabilities | Extensions provide native operations; adding a dependency alone does not expose them to the page. Register the required capability on the App. See [capabilities](https://github.com/moonbit-community/proton/blob/main/website/content/en/tutorial/capabilities.md). |
| State and lifecycle | Keep application state in the backend when it must outlive a page. Use `setup`/`setup_window` and `context.add_cleanup` to attach and release resources, and dispose frontend subscriptions with their owner. The [Todo tutorial](https://github.com/moonbit-community/proton/blob/main/website/content/en/tutorial/isomorphic.md) demonstrates this. |
| Pages and resources | Use `asset` for packaged web files, declare shipped resources in the project configuration, and resolve native resource paths from `@proton.resource_dir()`. See [configuration](https://github.com/moonbit-community/proton/blob/main/website/content/en/configuration/project.md). |
| Packaging | `proton.project.json` describes the product and output formats; `proton_cli package` assembles them. See [packaging](https://github.com/moonbit-community/proton/blob/main/website/content/en/command-line-interface/packaging.md). |
| Debugging | Use browser DevTools for the page, terminal logs for the backend, and `doctor` for setup. See [debugging](https://github.com/moonbit-community/proton/blob/main/website/content/en/command-line-interface/debugging.md). |

For dialogs, filesystem access, menus, tray, notifications, global shortcuts,
multiple windows, and updates, consult the
[example catalog](https://github.com/moonbit-community/proton/blob/main/examples/Readme.md)
and [extension guide](https://github.com/moonbit-community/proton/blob/main/extensions/README.md).
Check the selected capability's platform support. These upstream guides track
`main`; confirm signatures against the dependencies in the current project.

## Project configuration

Proton CLI projects are configured by `proton.project.json`. Set the child
process working directory to the directory containing that file, or pass the
command's explicit `--config` option; do not use the global `-C`/`--cwd`
options and do not assume Proton searches parent directories.

In `proton.project.json`, `backend.path` must identify the exact MoonBit
working directory. Do not assume Proton searches parent directories for a
`moon.work` or `moon.mod` file.

## Find help

Read `proton_cli --help` for available commands and
`proton_cli <command> --help` before using unfamiliar options. If the CLI is
not installed, it can be invoked with `moonx moonbit-community/proton_cli`.

Use `moon ide doc` from the relevant MoonBit module to inspect imported Proton
APIs before guessing names or signatures. Query package aliases or symbols
from the generated code, for example `moon ide doc "@proton"` in the backend.
