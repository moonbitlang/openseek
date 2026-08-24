// The desktop crash page lives in the generated JavaScript bundle instead of
// an HTML shell. Both `desktop-dev.html` and packaged `index.html` load this
// entry point, so they install exactly the same last-resort error handler.

///|
/// We **must not** write this part in rabbita, as we want to catch **all** unhandled
/// JavaScript exception raised from inside rabbita.
pub extern "js" fn install() -> Unit =
  #|() => {
  #|  const style = document.createElement("style");
  #|  style.id = "openseek-crash-page-style";
  #|  style.textContent = `
  #|    /* Follow the app palette when it loaded. Literal fallbacks keep this
  #|       last-resort page readable when the stylesheet itself failed. */
  #|    #frontend-crash {
  #|      box-sizing: border-box;
  #|      display: grid;
  #|      min-height: 100vh;
  #|      place-items: center;
  #|      padding: 24px;
  #|      background: var(--color-bg-canvas, #fbfbf9);
  #|      color: var(--color-text-primary, #16171a);
  #|      font: var(--font-size-md, 14px)/var(--line-height-relaxed, 1.6)
  #|        var(--font-family-sans, ui-sans-serif, system-ui, -apple-system,
  #|          BlinkMacSystemFont, "Segoe UI", sans-serif);
  #|      font-weight: var(--font-weight-regular, 450);
  #|    }
  #|    body.frontend-crashed {
  #|      margin: 0;
  #|      background: var(--color-bg-canvas, #fbfbf9);
  #|    }
  #|    #frontend-crash .frontend-crash-card {
  #|      width: min(440px, 100%);
  #|      padding: 24px;
  #|      border: 1px solid var(--color-border, #e9e8e3);
  #|      border-radius: var(--radius-md, 9px);
  #|      background: var(--color-bg-surface, #fff);
  #|      box-shadow: var(--shadow-overlay, 0 8px 30px -8px rgb(20 23 26 / 22%));
  #|    }
  #|    #frontend-crash .frontend-crash-mark {
  #|      display: grid;
  #|      width: 36px;
  #|      height: 36px;
  #|      margin-bottom: 16px;
  #|      place-items: center;
  #|      border: 1px solid var(--color-danger-border, #f2d4cf);
  #|      border-radius: var(--radius-md, 9px);
  #|      background: var(--color-danger-soft, #fcefed);
  #|      color: var(--color-danger, #c0453b);
  #|      font-size: 18px;
  #|      font-weight: 600;
  #|    }
  #|    #frontend-crash h1 {
  #|      margin: 0 0 8px;
  #|      color: var(--color-text-primary, #16171a);
  #|      font-size: var(--font-size-lg, 17px);
  #|      font-weight: 600;
  #|    }
  #|    #frontend-crash p {
  #|      margin: 0 0 18px;
  #|      color: var(--color-text-secondary, #5c5f66);
  #|    }
  #|    #frontend-crash button {
  #|      padding: 6px 12px;
  #|      border: 1px solid var(--color-accent, #3b6ef5);
  #|      border-radius: var(--radius-sm, 6px);
  #|      background: var(--color-accent, #3b6ef5);
  #|      color: var(--color-on-accent, #fff);
  #|      font: inherit;
  #|      cursor: pointer;
  #|    }
  #|    #frontend-crash button:hover {
  #|      border-color: var(--color-accent-strong, #2a55cc);
  #|      background: var(--color-accent-strong, #2a55cc);
  #|    }
  #|    #frontend-crash button:focus-visible,
  #|    #frontend-crash summary:focus-visible {
  #|      outline: 2px solid var(--color-focus-ring, #3b6ef5);
  #|      outline-offset: 2px;
  #|    }
  #|    #frontend-crash details {
  #|      margin-top: 20px;
  #|      padding-top: 14px;
  #|      border-top: 1px solid var(--color-border-subtle, #f0efea);
  #|      color: var(--color-text-muted, #9a9da4);
  #|      font-size: var(--font-size-sm, 13px);
  #|    }
  #|    #frontend-crash summary { cursor: pointer; }
  #|    #frontend-crash pre {
  #|      max-height: 240px;
  #|      overflow: auto;
  #|      padding: 12px;
  #|      border: 1px solid var(--color-border-subtle, #f0efea);
  #|      border-radius: var(--radius-sm, 6px);
  #|      background: var(--color-bg-subtle, #f6f6f3);
  #|      color: var(--color-code, #2b2f36);
  #|      font: 400 var(--font-size-sm, 13px)/var(--line-height-normal, 1.5)
  #|        var(--font-family-mono, ui-monospace, SFMono-Regular, Menlo, Monaco,
  #|          Consolas, "Liberation Mono", "Courier New", monospace);
  #|      white-space: pre-wrap;
  #|      word-break: break-word;
  #|    }
  #|  `;
  #|  document.head.append(style);
  #|
  #|  class SeekMoonCrashPage {
  #|    constructor() {
  #|      this.crashed = false;
  #|      window.addEventListener("error", (event) => {
  #|        // Browser diagnostics such as ResizeObserver loop notifications
  #|        // are delivered as `error` events without an exception object.
  #|        // Keep them visible for diagnosis, but reserve the crash page for
  #|        // actual uncaught JavaScript exceptions.
  #|        if (event.error == null) {
  #|          console.warn(event.message);
  #|          return;
  #|        }
  #|        this.show(event.error);
  #|      });
  #|      window.addEventListener("unhandledrejection", (event) => {
  #|        this.show(event.reason);
  #|      });
  #|    }
  #|
  #|    show(reason) {
  #|      // The first uncaught failure is closest to the cause. Later callbacks
  #|      // may still fail after the application DOM has been replaced.
  #|      if (this.crashed) return;
  #|      this.crashed = true;
  #|
  #|      let detail;
  #|      if (reason instanceof Error) {
  #|        detail = reason.stack || `${reason.name}: ${reason.message}`;
  #|      } else if (typeof reason === "string") {
  #|        detail = reason;
  #|      } else {
  #|        try {
  #|          detail = JSON.stringify(reason, null, 2);
  #|        } catch {
  #|          detail = String(reason);
  #|        }
  #|      }
  #|      if (!detail) detail = "Unknown JavaScript error";
  #|
  #|      document.title = "SeekMoon stopped unexpectedly";
  #|      document.body.className = "frontend-crashed";
  #|      document.body.innerHTML = `
  #|        <main id="frontend-crash" role="alert">
  #|          <section class="frontend-crash-card">
  #|            <div class="frontend-crash-mark" aria-hidden="true">!</div>
  #|            <h1>SeekMoon stopped unexpectedly</h1>
  #|            <p>Reload the page to continue. Unsaved input may be lost.</p>
  #|            <button id="frontend-crash-reload" type="button">Reload</button>
  #|            <details>
  #|              <summary>Error details</summary>
  #|              <pre id="frontend-crash-detail"></pre>
  #|            </details>
  #|          </section>
  #|        </main>`;
  #|      // Exception text must never be interpreted as HTML.
  #|      document.getElementById("frontend-crash-detail").textContent = detail;
  #|      document
  #|        .getElementById("frontend-crash-reload")
  #|        .addEventListener("click", () => window.location.reload());
  #|    }
  #|  }
  #|
  #|  new SeekMoonCrashPage();
  #|}
