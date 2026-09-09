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
    "windows-x64": "SeekMoon-windows-x64-setup.exe",
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

for (const scenario of [
  { name: "publish installs the NSIS artifact in the Windows manifest", fromCheckout: true, windowsFile: "SeekMoon-windows-x64-setup.exe" },
  { name: "rollback prefers NSIS when both Windows formats exist", fromCheckout: false, windowsFile: "SeekMoon-windows-x64-setup.exe" },
  { name: "rollback preserves a legacy Windows ZIP", fromCheckout: false, windowsFile: "SeekMoon-windows-x64.zip" },
  { name: "rollback supports releases predating Windows", fromCheckout: false, windowsFile: null },
]) {
  test(scenario.name, async t => {
    const release = new Release();
    const sha256 = "a".repeat(64);
    t.mock.method(release, "moduleVersion", async () => "0.1.9");
    const local = t.mock.method(release, "localArtifact", async () => ({ size: 123, sha256 }));
    const head = t.mock.method(release, "headObject", (_version, artifact) => {
      if (artifact.platform === "windows-x64" && (scenario.windowsFile === null ||
        (scenario.windowsFile.endsWith(".zip") && artifact.file.endsWith(".exe")))) {
        return { missing: true };
      }
      return { size: "123", sha256, crc64: "1" };
    });
    let published;
    t.mock.method(release, "fetchJson", async (path, options) => {
      if (path === "/desktop/releases/v0.1.9/publish") {
        assert.equal(options.method, "POST");
        const { platforms } = JSON.parse(options.body);
        published = { version: "0.1.9", platforms: Object.fromEntries(
          Object.entries(platforms).map(([platform, { file, sha256 }]) =>
            [platform, { url: `https://downloads.example.com/v0.1.9/${file}`, sha256 }])) };
        return { published };
      }
      assert.equal(path, "/desktop/releases/latest.json");
      return published;
    });
    await release.publish("v0.1.9", { fromCheckout: scenario.fromCheckout });
    if (scenario.windowsFile === null) {
      assert.equal(Object.hasOwn(published.platforms, "windows-x64"), false);
    } else {
      assert.deepEqual(published.platforms["windows-x64"], {
        url: `https://downloads.example.com/v0.1.9/${scenario.windowsFile}`, sha256,
      });
    }
    assert.equal(Object.keys(published.platforms).length, scenario.windowsFile === null ? 3 : 4);
    if (scenario.fromCheckout) {
      assert.equal(local.mock.calls.at(-1).arguments[0].file, "SeekMoon-windows-x64-setup.exe");
    } else {
      assert.equal(local.mock.callCount(), 0);
    }
    if (scenario.windowsFile?.endsWith(".exe")) {
      assert.equal(head.mock.calls.some(call => call.arguments[1].file === "SeekMoon-windows-x64.zip"), false);
    }
  });
}

test("rollback does not hide OSS failures by falling back to ZIP", async t => {
  const release = new Release();
  const error = new Error("OSS access denied");
  const head = t.mock.method(release, "headObject", (_version, artifact) => {
    if (artifact.platform === "windows-x64") throw error;
    return { size: "123", sha256: "a".repeat(64), crc64: "1" };
  });
  const request = t.mock.method(release, "fetchJson", async () => assert.fail("must not publish"));
  await assert.rejects(release.publish("v0.1.9", { fromCheckout: false }), actual => actual === error);
  assert.equal(request.mock.callCount(), 0);
  assert.equal(head.mock.calls.some(call => call.arguments[1].file === "SeekMoon-windows-x64.zip"), false);
});

test("upload sends the Windows installer to OSS as an executable download", async t => {
  const release = new Release();
  release.dist = await fs.mkdtemp(join(tmpdir(), "openseek-release-upload-"));
  t.after(() => fs.rm(release.dist, { recursive: true, force: true }));
  const bytes = Buffer.from("release artifact fixture");
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  for (const file of ["SeekMoon.app.zip", "SeekMoon.dmg", "SeekMoon.browser.tar.gz", "SeekMoon-windows-x64-setup.exe"]) {
    await fs.writeFile(join(release.dist, file), bytes);
  }
  t.mock.method(release, "moduleVersion", async () => "0.1.9");
  t.mock.method(release, "oss", () => ({ bucket: "test", region: "test", prefix: "releases" }));
  t.mock.method(release, "fetch", async () => new Response(null, { status: 404 }));
  t.mock.method(release, "verifyServed", async () => ({ sha256 }));
  t.mock.method(release, "fetchJson", async () => ({ sha256 }));
  t.mock.method(release, "unpackBrowser", async () => {});
  const commands = t.mock.method(release, "commandRun", () => {});
  await release.upload("v0.1.9");
  assert.equal(commands.mock.callCount(), 4);
  const [program, args] = commands.mock.calls.at(-1).arguments;
  assert.equal(program, "ossutil");
  assert.equal(args[args.indexOf("--content-type") + 1], "application/octet-stream");
  assert.equal(args.at(-2), join(release.dist, "SeekMoon-windows-x64-setup.exe"));
  assert.equal(args.at(-1), "oss://test/releases/v0.1.9/SeekMoon-windows-x64-setup.exe");
});
