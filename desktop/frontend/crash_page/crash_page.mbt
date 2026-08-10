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
  #|    #frontend-crash {
  #|      box-sizing: border-box;
  #|      display: grid;
  #|      min-height: 100vh;
  #|      place-items: center;
  #|      padding: 24px;
  #|      background: var(--paper, #fbfbf9);
  #|      color: var(--ink, #16171a);
  #|      font: 13.5px/1.55 var(--mono, "SF Mono", ui-monospace, Consolas, monospace);
  #|    }
  #|    body.frontend-crashed {
  #|      margin: 0;
  #|      background: var(--paper, #fbfbf9);
  #|    }
  #|    #frontend-crash .frontend-crash-card {
  #|      width: min(440px, 100%);
  #|      padding: 24px;
  #|      border: 1px solid var(--line, #e9e8e3);
  #|      border-radius: var(--radius, 9px);
  #|      background: var(--surface, #fff);
  #|      box-shadow: var(--shadow-pop, 0 8px 30px -8px rgb(20 23 26 / 22%));
  #|    }
  #|    #frontend-crash .frontend-crash-mark {
  #|      display: grid;
  #|      width: 36px;
  #|      height: 36px;
  #|      margin-bottom: 16px;
  #|      place-items: center;
  #|      border: 1px solid var(--del-line, #f2d4cf);
  #|      border-radius: var(--radius, 9px);
  #|      background: var(--del-bg, #fcefed);
  #|      color: var(--del, #c0453b);
  #|      font-size: 18px;
  #|      font-weight: 650;
  #|    }
  #|    #frontend-crash h1 {
  #|      margin: 0 0 8px;
  #|      color: var(--ink, #16171a);
  #|      font-size: 16px;
  #|      font-weight: 600;
  #|    }
  #|    #frontend-crash p {
  #|      margin: 0 0 18px;
  #|      color: var(--ink-2, #5c5f66);
  #|    }
  #|    #frontend-crash button {
  #|      padding: 6px 12px;
  #|      border: 1px solid var(--accent, #3b6ef5);
  #|      border-radius: var(--radius-sm, 6px);
  #|      background: var(--accent, #3b6ef5);
  #|      color: #fff;
  #|      font: inherit;
  #|      cursor: pointer;
  #|    }
  #|    #frontend-crash button:hover {
  #|      border-color: var(--accent-ink, #2a55cc);
  #|      background: var(--accent-ink, #2a55cc);
  #|    }
  #|    #frontend-crash button:focus-visible,
  #|    #frontend-crash summary:focus-visible {
  #|      outline: 2px solid var(--accent, #3b6ef5);
  #|      outline-offset: 2px;
  #|    }
  #|    #frontend-crash details {
  #|      margin-top: 20px;
  #|      padding-top: 14px;
  #|      border-top: 1px solid var(--line-2, #f0efea);
  #|      color: var(--ink-3, #9a9da4);
  #|      font-size: 12px;
  #|    }
  #|    #frontend-crash summary { cursor: pointer; }
  #|    #frontend-crash pre {
  #|      max-height: 240px;
  #|      overflow: auto;
  #|      padding: 12px;
  #|      border: 1px solid var(--line-2, #f0efea);
  #|      border-radius: var(--radius-sm, 6px);
  #|      background: var(--surface-2, #f6f6f3);
  #|      color: var(--code, #2b2f36);
  #|      font: 12px/1.5 var(--mono, "SF Mono", ui-monospace, Consolas, monospace);
  #|      white-space: pre-wrap;
  #|      word-break: break-word;
  #|    }
  #|  `;
  #|  document.head.append(style);
  #|
  #|  class OpenSeekCrashPage {
  #|    constructor() {
  #|      this.crashed = false;
  #|      window.addEventListener("error", (event) => {
  #|        this.show(event.error ?? event.message);
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
  #|      document.title = "OpenSeek stopped unexpectedly";
  #|      document.body.className = "frontend-crashed";
  #|      document.body.innerHTML = `
  #|        <main id="frontend-crash" role="alert">
  #|          <section class="frontend-crash-card">
  #|            <div class="frontend-crash-mark" aria-hidden="true">!</div>
  #|            <h1>OpenSeek stopped unexpectedly</h1>
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
  #|  new OpenSeekCrashPage();
  #|}
