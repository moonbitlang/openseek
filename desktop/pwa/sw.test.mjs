// Runs sw.js against a fake ServiceWorkerGlobalScope and checks what each
// payload of the relay contract (docs/plans/web-push.md) shows.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const source = await readFile(new URL("./sw.js", import.meta.url), "utf8");

function worker({ windows = [] } = {}) {
  const listeners = new Map();
  const shown = [];
  const opened = [];
  const self = {
    location: { origin: "https://seekmoon.example" },
    addEventListener: (type, listener) => listeners.set(type, listener),
    skipWaiting: () => {},
    registration: {
      showNotification: async (title, options) => shown.push({ title, ...options }),
    },
    clients: {
      claim: async () => {},
      matchAll: async () => windows,
      openWindow: async (url) => opened.push(url),
    },
  };
  vm.runInNewContext(source, { self, URL, MessageChannel, setTimeout, clearTimeout });
  async function dispatch(type, event) {
    const pending = [];
    listeners.get(type)({ ...event, waitUntil: (promise) => pending.push(promise) });
    await Promise.all(pending);
  }
  return {
    shown,
    opened,
    push: (payload) =>
      dispatch("push", {
        data:
          payload === undefined
            ? null
            : {
                json: () => (typeof payload === "string" ? JSON.parse(payload) : payload),
              },
      }),
    click: (data) => dispatch("notificationclick", { notification: { close: () => {}, data } }),
  };
}

test("a finished run shows its status title, device and answer", async () => {
  const sw = worker();
  await sw.push({
    v: 1,
    kind: "finished",
    locale: "zh-Hans",
    url: "/device/d_1/chat/session/s1",
    device_name: "MacBook",
    status: "finished",
    answer: "  Done.  ",
  });
  assert.equal(sw.shown.length, 1);
  assert.equal(sw.shown[0].title, "任务已完成");
  assert.equal(sw.shown[0].body, "MacBook · Done.");
  assert.equal(sw.shown[0].tag, "/device/d_1/chat/session/s1");
  assert.equal(sw.shown[0].data.url, "/device/d_1/chat/session/s1");
});

test("finish statuses map to the window's titles", async () => {
  const sw = worker();
  const base = { v: 1, kind: "finished", locale: "en", url: "/device/d/chat/session/s" };
  await sw.push({ ...base, status: "max_steps_exhausted" });
  await sw.push({ ...base, status: "error" });
  await sw.push({ ...base, kind: "cloud_finished", url: "/cloud/session/c", status: "completed" });
  await sw.push({ ...base, kind: "cloud_finished", url: "/cloud/session/c", status: "failed" });
  assert.deepEqual(
    sw.shown.map((item) => item.title),
    ["Task stopped at the step limit", "Task failed", "Task finished", "Task failed"],
  );
  assert.equal(sw.shown[0].body, "The conversation is ready for you.");
});

test("an approval names the tool and what it asks for", async () => {
  const sw = worker();
  await sw.push({
    v: 1,
    kind: "approval",
    locale: "en",
    url: "/device/d/chat/session/s",
    tool: "mbtx",
    detail: "run this snippet with no sandbox policy",
  });
  assert.equal(sw.shown[0].title, "Permission required");
  assert.equal(sw.shown[0].body, "mbtx is asking permission to run this snippet with no sandbox policy");
});

test("long answers are cut at 180 code points", async () => {
  const sw = worker();
  await sw.push({ v: 1, kind: "finished", locale: "ja", url: "/cloud", status: "finished", answer: "月".repeat(200) });
  assert.equal(sw.shown[0].body, "月".repeat(180) + "…");
});

test("unknown locales fall back to English", async () => {
  const sw = worker();
  await sw.push({ v: 1, kind: "test", locale: "fr", url: "/cloud" });
  assert.equal(sw.shown[0].title, "Notifications are on");
});

test("an unreadable push still shows a notification", async () => {
  const sw = worker();
  await sw.push(undefined);
  await sw.push("not json");
  await sw.push({ v: 2, kind: "finished" });
  await sw.push({ v: 1, kind: "finished", locale: "en", url: "https://elsewhere.example/x", status: "finished" });
  assert.equal(sw.shown.length, 4);
  assert.deepEqual(
    sw.shown.slice(0, 3).map((item) => [item.title, item.tag]),
    [
      ["SeekMoon", "/cloud"],
      ["SeekMoon", "/cloud"],
      ["SeekMoon", "/cloud"],
    ],
  );
  // Only root-relative paths are followed.
  assert.equal(sw.shown[3].tag, "/cloud");
});

// An open window; `answer` is what its page replies to an open request, or
// undefined for a page that never replies.
function openWindow(answer) {
  const client = {
    url: "https://seekmoon.example/cloud",
    asked: [],
    navigated: [],
    focus: async () => {},
    navigate: async (url) => client.navigated.push(url),
    postMessage: (message, [port]) => {
      client.asked.push({ ...message });
      if (answer !== undefined) port.postMessage(answer);
    },
  };
  return client;
}

test("a click shows the link in place in an open console page", async () => {
  const client = openWindow(true);
  const sw = worker({ windows: [client] });
  await sw.click({ url: "/device/d/chat/session/s" });
  assert.deepEqual(client.asked, [{ type: "seekmoon.open", url: "/device/d/chat/session/s" }]);
  assert.deepEqual(client.navigated, []);
  assert.deepEqual(sw.opened, []);
});

test("a click navigates a page that declines or does not answer", async () => {
  for (const answer of [false, undefined]) {
    const client = openWindow(answer);
    const sw = worker({ windows: [client] });
    await sw.click({ url: "/device/d/chat/session/s" });
    assert.deepEqual(client.navigated, ["https://seekmoon.example/device/d/chat/session/s"]);
  }
});

test("a click with no open window opens one", async () => {
  const sw = worker();
  await sw.click({ url: "/cloud/session/c" });
  assert.deepEqual(sw.opened, ["https://seekmoon.example/cloud/session/c"]);
});
