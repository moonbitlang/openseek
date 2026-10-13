import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

// Keep PDF.js at its public viewer boundary. These tests exercise the host's
// resize, selection and lifetime handling without a worker, canvas or window.
async function fixture(t, width = 160) {
  const events = [], observers = [], frames = new Map();
  const hostListeners = new Map(), documentListeners = new Map(), timers = new Map();
  let frameId = 0;
  let timerId = 0;
  const container = { clientWidth: width, firstElementChild: {} };
  const host = { id: "pdf", dataset: {}, querySelector: () => container,
    addEventListener: (name, handler) => hostListeners.set(name, handler) };
  class EventBus {
    handlers = new Map();
    on(name, handler) {
      if (!this.handlers.has(name)) this.handlers.set(name, []);
      this.handlers.get(name).push(handler);
    }
    dispatch(name, value) { for (const handler of this.handlers.get(name) || []) handler(value); }
  }
  class PDFViewer {
    updates = 0;
    currentScale = 1;
    constructor({ container, eventBus }) { this.container = container; this.bus = eventBus; }
    setDocument(doc) {
      this.pagesCount = doc?.numPages || 0;
      if (doc) queueMicrotask(() => this.bus.dispatch("pagesinit", {}));
    }
    set currentScaleValue(value) {
      this.scaleValue = value;
      this.currentScale = value === "page-width" ? (container.clientWidth - 40) / 800 : Number(value);
      this.bus.dispatch("scalechanging", { scale: this.currentScale });
    }
    get currentScaleValue() { return this.scaleValue; }
    update() { this.updates++; }
  }
  class ResizeObserver {
    constructor(callback) { this.callback = callback; observers.push(this); }
    observe(target) { this.target = target; }
    disconnect() { this.disconnected = true; }
  }
  const sdk = {
    PDFViewer, EventBus, ResizeObserver,
    PDFLinkService: class { setViewer() {} setDocument() {} },
    PDFFindController: class {}, LinkTarget: { BLANK: 2 },
  };
  const core = {
    GlobalWorkerOptions: {}, version: "fixture",
    AnnotationMode: { ENABLE: 1 }, AnnotationEditorType: { DISABLE: -1 },
    getDocument: () => ({
      promise: Promise.resolve({ numPages: 1, fingerprints: ["fixture"] }),
      destroy: async () => {},
    }),
  };
  const context = vm.createContext({
    crypto: webcrypto, URL, Uint8Array, AbortController, ResizeObserver,
    setTimeout: callback => { timers.set(++timerId, callback); return timerId; },
    clearTimeout: id => timers.delete(id),
    document: { addEventListener: (name, handler) => documentListeners.set(name, handler) },
    requestAnimationFrame: callback => { frames.set(++frameId, callback); return frameId; },
    cancelAnimationFrame: id => frames.delete(id),
  });
  const synthetic = values => new vm.SyntheticModule(Object.keys(values), function () {
    for (const [name, value] of Object.entries(values)) this.setExport(name, value);
  }, { context });
  const coreModule = synthetic(core), viewerModule = synthetic(sdk);
  const source = await readFile(new URL("../../.mooncakes/Lampese/office-viewer/public/pdf-runtime.js", import.meta.url), "utf8");
  const runtime = new vm.SourceTextModule(source, {
    context,
    initializeImportMeta: meta => { meta.url = "https://fixture.test/pdf-runtime.js"; },
    importModuleDynamically: async () => {
      await viewerModule.link(() => {});
      await viewerModule.evaluate();
      return viewerModule;
    },
  });
  await runtime.link(() => coreModule);
  await runtime.evaluate();
  let resolveReady, rejectReady;
  const ready = new Promise((resolve, reject) => { resolveReady = resolve; rejectReady = reject; });
  const timeout = setTimeout(() => rejectReady(new Error("PDF runtime did not become ready")), 5000);
  t.after(() => clearTimeout(timeout));
  const session = runtime.namespace.mount(host, {
    file: "/report.pdf", bytes: new Uint8Array([37, 80, 68, 70]), zoom: 100, query: "",
    onState: raw => {
      const event = JSON.parse(raw);
      events.push(event);
      if (event.status === "ready") resolveReady();
      if (event.status === "error") rejectReady(new Error(event.message));
    },
    onSelection() {},
  });
  t.after(() => { if (session.alive) session.destroy(); });
  await ready;
  clearTimeout(timeout);
  assert.equal(host.dataset.pdfReady, "true");
  const flush = () => {
    const queued = [...frames.values()];
    frames.clear();
    for (const callback of queued) callback();
  };
  const resize = width => {
    container.clientWidth = width;
    for (const observer of observers) if (!observer.disconnected) observer.callback([{ target: container }]);
    flush();
  };
  const flushTimers = async () => {
    const queued = [...timers.values()];
    timers.clear();
    for (const callback of queued) await callback();
  };
  return { session, container, events, observers, frames, resize, flush, timers, flushTimers,
    emitHost: (name, event = {}) => hostListeners.get(name)?.(event),
    emitDocument: (name, event = {}) => documentListeners.get(name)?.(event) };
}

test("PDF fit width follows the panel as its opening animation grows", async t => {
  const { session, events, resize } = await fixture(t);
  assert.equal(session.viewer.currentScale, 0.15);
  resize(320);
  assert.equal(session.viewer.currentScaleValue, "page-width");
  assert.equal(session.viewer.currentScale, 0.35);
  assert.equal(events.filter(event => event.status === "scale").at(-1).zoom, 35);
  resize(163);
  session.apply(15, "invoice");
  assert.equal(session.viewer.currentScaleValue, "page-width");
  resize(480);
  assert.equal(session.viewer.currentScale, 0.55);
});

test("PDF resizing preserves manual zoom and resumes fitting after Fit width", async t => {
  const { session, resize } = await fixture(t);
  session.apply(75, "");
  const updates = session.viewer.updates;
  resize(480);
  assert.equal(session.viewer.currentScaleValue, "0.75");
  assert.equal(session.viewer.currentScale, 0.75);
  assert.ok(session.viewer.updates > updates);
  session.viewer.currentScaleValue = "page-width";
  resize(640);
  assert.equal(session.viewer.currentScale, 0.75);
  resize(320);
  assert.equal(session.viewer.currentScale, 0.35);
});

test("closing a PDF disconnects resize callbacks and cancels a queued repaint", async t => {
  const { session, observers, frames, flush } = await fixture(t);
  assert.equal(observers.length, 1);
  observers[0].callback([]);
  assert.equal(frames.size, 1);
  const updates = session.viewer.updates;
  session.destroy();
  assert.equal(observers[0].disconnected, true);
  assert.equal(frames.size, 0);
  flush();
  observers[0].callback([]);
  flush();
  assert.equal(session.viewer.updates, updates);
});

test("PDF pointer selection waits for release including outside the surface", async t => {
  const { session, timers, emitHost, emitDocument, flushTimers } = await fixture(t);
  let captures = 0;
  session.capture = async () => { captures++; };
  emitDocument("selectionchange");
  assert.equal(timers.size, 1);
  emitHost("pointerdown", { button: 0, pointerId: 7 });
  emitDocument("selectionchange");
  await flushTimers();
  assert.equal(captures, 0);
  // A different pointer cannot settle the active drag.
  emitDocument("pointerup", { pointerId: 8 });
  assert.equal(timers.size, 0);
  emitDocument("pointerup", { pointerId: 7 });
  assert.equal(timers.size, 1);
  await flushTimers();
  assert.equal(captures, 1);
  // Keyboard adjustments remain available once the drag has settled.
  emitHost("keyup");
  await flushTimers();
  assert.equal(captures, 2);
});

test("cancelled or retired PDF drags do not queue selection previews", async t => {
  const { session, timers, emitHost, emitDocument, flushTimers } = await fixture(t);
  let captures = 0;
  session.capture = async () => { captures++; };
  emitHost("pointerdown", { button: 0, pointerId: 4 });
  emitDocument("selectionchange");
  emitDocument("pointercancel", { pointerId: 4 });
  await flushTimers();
  assert.equal(captures, 0);
  emitDocument("selectionchange");
  assert.equal(timers.size, 1);
  session.destroy();
  await flushTimers();
  assert.equal(captures, 0);
});
