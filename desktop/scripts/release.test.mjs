import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import { createServer } from "node:http";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Release } from "./release.mjs";

async function server(t, respond) {
  const server = createServer(respond);
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  t.after(async () => {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  });
  return `http://127.0.0.1:${server.address().port}`;
}

test("release verification reads a successful JSON response", async t => {
  let requests = 0;
  const url = await server(t, (_request, response) => {
    requests++;
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify({ version: "0.1.9" }));
  });
  const release = new Release();
  t.mock.method(release, "apiOrigin", () => url);
  assert.deepEqual(await release.fetchJson("/latest.json", { auth: false }), { version: "0.1.9" });
  assert.equal(requests, 1);
});

for (const status of [401, 429, 503]) {
  test(`HTTP ${status} fails immediately without retrying`, async t => {
    let requests = 0;
    const url = await server(t, (_request, response) => {
      requests++;
      response.writeHead(status, { "retry-after": "0" });
      response.end("request failed");
    });
    const release = new Release();
    t.mock.method(release, "apiOrigin", () => url);
    await assert.rejects(release.fetchJson("/latest.json", { auth: false }), new RegExp(`HTTP ${status}\\nrequest failed`));
    assert.equal(requests, 1);
  });
}

test("network failures propagate without retrying", async t => {
  const error = new TypeError("connection reset");
  const request = t.mock.method(globalThis, "fetch", async () => { throw error; });
  const release = new Release();
  t.mock.method(release, "apiOrigin", () => "http://localhost");
  await assert.rejects(release.fetchJson("/latest.json", { auth: false }), actual => actual === error);
  assert.equal(request.mock.callCount(), 1);
});

test("response-body failures propagate without retrying", async t => {
  const error = new TypeError("response stream interrupted");
  const request = t.mock.method(globalThis, "fetch", async () => new Response(new ReadableStream({
    start(controller) { controller.error(error); },
  }), { status: 200 }));
  const release = new Release();
  t.mock.method(release, "apiOrigin", () => "http://localhost");
  await assert.rejects(release.fetchJson("/latest.json", { auth: false }), actual => actual === error);
  assert.equal(request.mock.callCount(), 1);
});

test("mutating requests fail without retrying", async t => {
  let requests = 0;
  const url = await server(t, (request, response) => {
    assert.equal(request.method, "POST");
    requests++;
    response.writeHead(503);
    response.end("unavailable");
  });
  const release = new Release();
  t.mock.method(release, "apiOrigin", () => url);
  await assert.rejects(release.fetchJson("/publish", { auth: false, method: "POST", body: "{}" }), /HTTP 503/);
  assert.equal(requests, 1);
});

test("verify distinguishes missing Location, non-redirects, and wrong destinations", async t => {
  const release = new Release();
  release.dist = await fs.mkdtemp(join(tmpdir(), "openseek-release-"));
  t.after(() => fs.rm(release.dist, { recursive: true, force: true }));
  t.mock.method(release, "moduleVersion", async () => "0.1.9");
  const files = {
    "macos-arm64": "SeekMoon.app.zip",
    "macos-arm64-dmg": "SeekMoon.dmg",
    browser: "SeekMoon.browser.tar.gz",
    "windows-x64": "SeekMoon-windows-x64.zip",
  };
  const bytes = Buffer.from("release artifact fixture");
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  for (const file of Object.values(files)) await fs.writeFile(join(release.dist, file), bytes);
  const manifest = { version: "0.1.9", platforms: {} };
  let status = 302;
  let headers = {};
  const url = await server(t, (request, response) => {
    if (request.method === "HEAD") {
      response.writeHead(200, { "content-length": String(bytes.length), "x-oss-meta-sha256": sha256, "x-oss-hash-crc64ecma": "1" });
      response.end();
    } else if (request.url === "/desktop/releases/latest.json") {
      response.end(JSON.stringify(manifest));
    } else if (request.url === "/browser/releases/current.json") {
      response.end(JSON.stringify({ version: "0.1.9" }));
    } else if (request.url === "/console/") {
      response.writeHead(status, headers);
      response.end();
    } else {
      response.writeHead(404);
      response.end();
    }
  });
  for (const [platform, file] of Object.entries(files)) {
    manifest.platforms[platform] = { url: `${url}/v0.1.9/${file}`, sha256 };
  }
  t.mock.method(release, "apiOrigin", () => url);
  await assert.rejects(release.verify("v0.1.9"), /redirect is missing Location: HTTP 302/);
  status = 200;
  await assert.rejects(release.verify("v0.1.9"), /did not redirect: HTTP 200/);
  status = 302;
  headers = { location: "/console/releases/v0.1.8/index.html" };
  await assert.rejects(release.verify("v0.1.9"), /did not select \/console\/releases\/v0\.1\.9\/index\.html/);
});

test("artifact checks preserve non-missing filesystem errors", async t => {
  const error = Object.assign(new Error("permission denied"), { code: "EACCES" });
  const mocked = t.mock.method(fs, "stat", async () => { throw error; });
  syncBuiltinESMExports();
  t.after(() => { mocked.mock.restore(); syncBuiltinESMExports(); });
  await assert.rejects(new Release().localArtifact({ file: "SeekMoon.app.zip" }), actual => actual === error);
});

test("missing artifacts have a useful message and retain the filesystem cause", async t => {
  const error = Object.assign(new Error("no such file"), { code: "ENOENT" });
  const mocked = t.mock.method(fs, "stat", async () => { throw error; });
  syncBuiltinESMExports();
  t.after(() => { mocked.mock.restore(); syncBuiltinESMExports(); });
  await assert.rejects(new Release().localArtifact({ file: "SeekMoon.app.zip" }), actual => {
    assert.match(actual.message, /artifact not found: .*SeekMoon\.app\.zip/);
    assert.equal(actual.cause, error);
    return true;
  });
});
