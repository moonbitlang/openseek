import assert from "node:assert/strict";
import fs from "node:fs/promises";
import { createServer } from "node:http";
import { syncBuiltinESMExports } from "node:module";
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

test("release verification recovers from a transient HTTP failure", async t => {
  let requests = 0;
  const url = await server(t, (_request, response) => {
    requests++;
    response.writeHead(requests === 1 ? 503 : 200, { "content-type": "application/json" });
    response.end(JSON.stringify({ version: "0.1.9" }));
  });
  const release = new Release();
  t.mock.method(release, "apiOrigin", () => url);
  assert.deepEqual(await release.fetchJson("/latest.json", { auth: false, retries: 3 }), { version: "0.1.9" });
  assert.equal(requests, 2);
});

test("transient retries are bounded and preserve the final error response", async t => {
  let requests = 0;
  const url = await server(t, (_request, response) => {
    requests++;
    response.writeHead(429, { "retry-after": "0" });
    response.end("rate limited");
  });
  const release = new Release();
  t.mock.method(release, "apiOrigin", () => url);
  await assert.rejects(release.fetchJson("/latest.json", { auth: false, retries: 2 }), /HTTP 429\nrate limited/);
  assert.equal(requests, 3);
});

test("permanent HTTP errors are not retried", async t => {
  let requests = 0;
  const url = await server(t, (_request, response) => {
    requests++;
    response.writeHead(401);
    response.end("unauthorized");
  });
  const response = await new Release().request(url, { retries: 3 });
  assert.equal(response.status, 401);
  assert.equal(await response.text(), "unauthorized");
  assert.equal(requests, 1);
});

test("mutating requests keep retries disabled by default", async t => {
  let requests = 0;
  const url = await server(t, (request, response) => {
    assert.equal(request.method, "POST");
    requests++;
    response.writeHead(503);
    response.end("unavailable");
  });
  const response = await new Release().request(url, { method: "POST", body: "{}" });
  assert.equal(response.status, 503);
  await response.body.cancel();
  assert.equal(requests, 1);
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
