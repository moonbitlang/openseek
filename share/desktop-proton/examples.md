# Small Proton examples

These examples use Proton 0.3.3 APIs. Start with a generated **minimal**
project (`proton_cli new my-app --template minimal --yes`) and work from its
directory. Keep its `proton.project.json`, including the application identity.
In an existing project, preserve its entry and imports rather than replacing
them wholesale. Keep Proton module versions consistent with that project.

## A minimal window

The generated `app/moon.pkg` imports `moonbit-community/proton` and
`moonbitlang/async`, and declares a native executable. Replace `app/main.mbt`
with:

```moonbit
///|
async fn main {
  @proton.html(
    "Hello Proton",
    "<!doctype html><html lang='en'><meta charset='utf-8'><title>Hello</title><h1>Hello from MoonBit</h1></html>",
    width=800,
    height=600,
    debug=true,
  )
  .load_config()
  .run_or_abort()
}
```

Run `moon check --target native`, then `proton_cli dev`. A window should show
the heading. The builder configures the window; `load_config()` reads the
project configuration, and `run_or_abort()` runs the application.

Use `@proton.url` for a web URL, `@proton.file` for a local HTML file, or
`@proton.asset` for a packaged page. For a MoonBit web UI, start with the
default isomorphic template instead of growing a large inline HTML string.

## Commands, events, and an extension

This example asks the backend to create a greeting, receives a notification,
and copies the returned greeting through the clipboard extension. Plain
JavaScript keeps the frontend/native boundary visible; the default template
shows the equivalent typed MoonBit/Rabbita organization.

For a project using Proton 0.3.3, add these entries to the existing `import`
block in `moon.mod`, preserving its other dependencies:

```text
"moonbit-community/proton_contract@0.3.3",
"moonbit-community/proton_ext@0.3.3",
```

Use these imports and executable settings in `app/moon.pkg`:

```text
import {
  "moonbitlang/async",
  "moonbitlang/core/json",
  "moonbit-community/proton",
  "moonbit-community/proton_contract",
  "moonbit-community/proton_ext/clipboard",
}

supported_targets = "native"

pkgtype(kind: "executable")
```

Replace `app/main.mbt` with:

```moonbit
///|
struct GreetRequest {
  name : String
} derive(FromJson, ToJson)

///|
let greet : @proton_contract.Command[GreetRequest, String] =
  @proton_contract.command("greet")

///|
let greeted : @proton_contract.Event[String] =
  @proton_contract.event("greeted")

///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html lang="en">
    #|<meta charset="utf-8">
    #|<title>Greeting and clipboard</title>
    #|<label>Name <input id="name" value="Ada"></label>
    #|<button id="greet">Greet and copy</button>
    #|<p id="result" role="status"></p>
    #|<p id="event"></p>
    #|<script>
    #|  let unsubscribe;
    #|  document.querySelector("#greet").onclick = async () => {
    #|    const result = document.querySelector("#result");
    #|    try {
    #|      const bridge = window.__MoonBit__;
    #|      if (!unsubscribe) {
    #|        unsubscribe = bridge.app.on("greeted", ({ payload }) => {
    #|          document.querySelector("#event").textContent = "Event: " + payload;
    #|        });
    #|      }
    #|      const message = await bridge.app.greet({
    #|        name: document.querySelector("#name").value
    #|      });
    #|      await bridge.core.invokeOp("ext:clipboard/writeText", { text: message });
    #|      result.textContent = "Copied: " + message;
    #|    } catch (error) {
    #|      result.textContent = String(error);
    #|    }
    #|  };
    #|  window.addEventListener("pagehide", () => {
    #|    unsubscribe?.();
    #|    unsubscribe = undefined;
    #|  });
    #|</script>
    #|</html>
  @proton.html("Greeting and clipboard", html, debug=true)
  .load_config()
  .capability(@clipboard.capability())
  .commands(fn(registrar) raise {
    registrar.bind(greet, (context, request) => {
      let message = "Hello, " + request.name + "!"
      context.emit_to_caller(greeted, message)
      message
    })
  })
  .run_or_abort()
}
```

Run `moon update`, `moon check --target native`, and `proton_cli dev`.
Click **Greet and copy**: the page should show `Copied: Hello, Ada!` and
`Event: Hello, Ada!`; pasting should produce `Hello, Ada!`. This action replaces
the system clipboard. If copying fails, the page displays the error.

- **Command:** the descriptor defines the request and response types;
  `registrar.bind` supplies the backend handler. The frontend awaits its result.
- **Event:** `emit_to_caller` notifies the calling page. Subscribe before
  requesting work and unsubscribe when the page or owning component leaves.
  The event and command response are separate deliveries; do not depend on
  their arrival order. Background notifications use window event emitters;
  follow the generated Todo project's ready/close lifecycle for that pattern.
- **Extension:** `.capability(@clipboard.capability())` installs and grants the
  clipboard operations. This example calls the extension route directly;
  application commands use the separate `bridge.app` interface.

Open the app through Proton: an ordinary browser has no `window.__MoonBit__`
native bridge. Expected application outcomes belong in command response data;
keep exception handling for bridge and operation failures.
