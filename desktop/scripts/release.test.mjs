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

test("verify checks the current Browser bundle the API serves", async t => {
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
  await fs.mkdir(join(release.dist, "browser/assets"), { recursive: true });
  const documents = new Map([
    ["/cloud", "packaged document"],
    ["/assets/frontend.js", "packaged frontend"],
  ]);
  await fs.writeFile(join(release.dist, "browser/index.html"), "packaged document");
  await fs.writeFile(join(release.dist, "browser/assets/frontend.js"), "packaged frontend");
  const manifest = { version: "0.1.9", platforms: {} };
  let current = "0.1.8";
  const url = await server(t, (request, response) => {
    if (request.method === "HEAD") {
      response.writeHead(200, { "content-length": String(bytes.length), "x-oss-meta-sha256": sha256, "x-oss-hash-crc64ecma": "1" });
      response.end();
    } else if (request.url === "/desktop/releases/latest.json") {
      response.end(JSON.stringify(manifest));
    } else if (request.url === "/browser/releases/current.json") {
      response.end(JSON.stringify({ version: current }));
    } else if (request.url.startsWith("/v0.1.9/")) {
      response.end(bytes);
    } else if (documents.has(request.url)) {
      response.end(documents.get(request.url));
    } else {
      response.writeHead(404);
      response.end();
    }
  });
  for (const [platform, file] of Object.entries(files)) {
    manifest.platforms[platform] = { url: `${url}/v0.1.9/${file}`, sha256 };
  }
  t.mock.method(release, "apiOrigin", () => url);
  await assert.rejects(release.verify("v0.1.9"), /browser current\.json version 0\.1\.8 is not 0\.1\.9/);
  current = "0.1.9";
  await release.verify("v0.1.9");
  documents.set("/assets/frontend.js", "previous frontend");
  await assert.rejects(release.verify("v0.1.9"), /served assets\/frontend\.js does not match/);
  documents.delete("/cloud");
  await assert.rejects(release.verify("v0.1.9"), /GET \/cloud failed: HTTP 404/);
});

test("artifact checks preserve non-missing filesystem errors", async t => {
  const error = Object.assign(new Error("permission denied"), { code: "EACCES" });
  const mocked = t.mock.method(fs, "stat", async () => { throw error; });
  syncBuiltinESMExports();
  t.after(() => { mocked.mock.restore(); syncBuiltinESMExports(); });
  await assert.rejects(new Release().localArtifact({ file: "SeekMoon.app.zip" }), actual => actual === error);
});

async function stampFixture(t) {
  const release = new Release();
  const repo = await fs.mkdtemp(join(tmpdir(), "openseek-release-stamp-"));
  release.desktop = join(repo, "desktop");
  release.dist = join(release.desktop, "dist");
  t.after(() => fs.rm(repo, { recursive: true, force: true }));
  await fs.mkdir(join(release.desktop, "backend/ssh"), { recursive: true });
  await fs.writeFile(join(repo, "moon.mod"), 'name = "moonbitlang/openseek"\nversion = "0.8.2"\n');
  await fs.writeFile(join(release.desktop, "backend/ssh/version.mbt"), '///|\nconst CliRelease = "0.7.1"\n');
  return release;
}

test("stamp aligns Desktop versions while taking SSH's CLI version from the root manifest", async t => {
  const release = await stampFixture(t);
  // Each member with the sibling modules its manifest pins.
  const members = {
    backend: ["openseek_desktop"],
    app: ["openseek_desktop", "openseek_desktop/backend"],
    frontend: ["openseek_desktop"],
  };
  await fs.writeFile(join(release.desktop, "moon.mod"), 'name = "openseek_desktop"\nversion = "0.1.5"\n');
  for (const [member, pins] of Object.entries(members)) {
    await fs.mkdir(join(release.desktop, member), { recursive: true });
    const imports = pins.map(pin => `"${pin}@0.1.5"`).join(", ");
    await fs.writeFile(
      join(release.desktop, member, "moon.mod"),
      `name = "openseek_desktop/${member}"\nversion = "0.1.5"\nimport { ${imports} }\n`,
    );
  }
  await fs.writeFile(
    join(release.desktop, "proton.project.json"),
    JSON.stringify({ package: { version: "0.1.5" } }),
  );
  await release.stamp("0.2.0");
  assert.equal(await release.moduleVersion(), "0.2.0");
  for (const [member, pins] of Object.entries(members)) {
    const module = await fs.readFile(join(release.desktop, member, "moon.mod"), "utf8");
    assert.match(module, /^version = "0\.2\.0"$/m);
    for (const pin of pins) assert.ok(module.includes(`"${pin}@0.2.0"`), `${member} pins ${pin}`);
    assert.ok(!module.includes("@0.1.5"), `${member} keeps no stale pin`);
  }
  const config = JSON.parse(await fs.readFile(join(release.desktop, "proton.project.json"), "utf8"));
  assert.equal(config.package.version, "0.2.0");
  assert.equal(await fs.readFile(join(release.desktop, "backend/ssh/version.mbt"), "utf8"), '///|\nconst CliRelease = "0.8.2"\n');
  assert.match(await fs.readFile(join(release.desktop, "../moon.mod"), "utf8"), /^version = "0\.8\.2"$/m);
  await fs.writeFile(join(release.desktop, "../moon.mod"), 'version = "0.8.3"\n');
  await release.stamp("0.2.1");
  assert.equal(await fs.readFile(join(release.desktop, "backend/ssh/version.mbt"), "utf8"), '///|\nconst CliRelease = "0.8.3"\n');
  assert.equal(await release.moduleVersion(), "0.2.1");
});

for (const scenario of [
  { name: "missing CLI version", file: "../moon.mod", content: 'name = "moonbitlang/openseek"\n', error: /could not read CLI version/ },
  { name: "missing patch target", file: "backend/ssh/version.mbt", content: '///|\nconst Renamed = "0.7.1"\n', error: /expected one CliRelease constant/ },
]) {
  test(`stamp rejects ${scenario.name} instead of retaining a stale version`, async t => {
    const release = await stampFixture(t);
    await fs.writeFile(join(release.desktop, scenario.file), scenario.content);
    const source = join(release.desktop, "backend/ssh/version.mbt");
    const before = await fs.readFile(source, "utf8");
    await assert.rejects(release.stamp("0.2.0"), scenario.error);
    assert.equal(await fs.readFile(source, "utf8"), before);
  });
}

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
    t.mock.method(release, "headS3Object", () => ({ size: "123", sha256 }));
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
  t.mock.method(release, "headS3Object", () => ({ size: "123", sha256: "a".repeat(64) }));
  const head = t.mock.method(release, "headObject", (_version, artifact) => {
    if (artifact.platform === "windows-x64") throw error;
    return { size: "123", sha256: "a".repeat(64), crc64: "1" };
  });
  const request = t.mock.method(release, "fetchJson", async () => assert.fail("must not publish"));
  await assert.rejects(release.publish("v0.1.9", { fromCheckout: false }), actual => actual === error);
  assert.equal(request.mock.callCount(), 0);
  assert.equal(head.mock.calls.some(call => call.arguments[1].file === "SeekMoon-windows-x64.zip"), false);
});

test("separate upload stages send identical installers without requiring AWS credentials during OSS uploads", async t => {
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
  let credentialsReady = false;
  t.mock.method(release, "s3", () => {
    assert.ok(credentialsReady, "AWS credentials are acquired after OSS uploads finish");
    return { bucket: "mirror", region: "us-west-2", prefix: "releases" };
  });
  t.mock.method(release, "headS3Object", () => ({ size: String(bytes.length), sha256 }));
  t.mock.method(release, "fetch", async () => new Response(null, { status: 404 }));
  t.mock.method(release, "verifyServed", async () => ({ sha256 }));
  const stage = t.mock.method(release, "fetchJson", async () => {
    assert.equal(commands.mock.callCount(), 8, "all artifacts reach S3 before staging the Browser");
    return { sha256 };
  });
  t.mock.method(release, "unpackBrowser", async () => {});
  const commands = t.mock.method(release, "commandRun", () => {});
  await release.run("upload-oss", "v0.1.9");
  assert.equal(commands.mock.callCount(), 4);
  assert.ok(commands.mock.calls.every(call => call.arguments[0] === "ossutil"));
  assert.equal(stage.mock.callCount(), 0);
  const [program, args] = commands.mock.calls.at(-1).arguments;
  assert.equal(program, "ossutil");
  assert.equal(args[args.indexOf("--content-type") + 1], "application/octet-stream");
  assert.equal(args.at(-2), join(release.dist, "SeekMoon-windows-x64-setup.exe"));
  assert.equal(args.at(-1), "oss://test/releases/v0.1.9/SeekMoon-windows-x64-setup.exe");
  credentialsReady = true;
  await release.run("upload-s3");
  assert.equal(commands.mock.callCount(), 8);
  assert.ok(commands.mock.calls.slice(4).every(call => call.arguments[0] === "aws"));
  assert.equal(stage.mock.callCount(), 1);
  const [s3Program, s3Args] = commands.mock.calls.at(-1).arguments;
  assert.equal(s3Program, "aws");
  assert.equal(s3Args[2], join(release.dist, "SeekMoon-windows-x64-setup.exe"));
  assert.equal(s3Args[3], "s3://mirror/releases/v0.1.9/SeekMoon-windows-x64-setup.exe");
  assert.equal(s3Args[s3Args.indexOf("--metadata") + 1], `sha256=${sha256}`);
  assert.equal(s3Args[s3Args.indexOf("--content-type") + 1], "application/octet-stream");
  assert.equal(s3Args[s3Args.indexOf("--cache-control") + 1], "public, max-age=31536000, immutable");
});

test("release CI acquires AWS credentials after every OSS and Actions artifact transfer", async () => {
  const workflow = await fs.readFile(new URL("../../.github/workflows/desktop-release.yml", import.meta.url), "utf8");
  const publish = workflow.slice(workflow.indexOf("\n  release-publish:"));
  const steps = publish.split(/^      - /m).slice(1);
  const credentials = steps.findIndex(step => step.includes("uses: aws-actions/configure-aws-credentials@"));
  const oss = steps.findIndex(step => step.includes('release.mjs upload-oss "v$RELEASE_VERSION"'));
  const s3 = steps.findIndex(step => step.includes('release.mjs upload-s3 "v$RELEASE_VERSION"'));
  const publication = steps.findIndex(step => step.includes('release.mjs publish "v$RELEASE_VERSION"'));
  assert.ok(oss >= 0 && oss < credentials);
  assert.equal(s3, credentials + 1);
  assert.equal(publication, s3 + 1);
  for (const [index, step] of steps.entries()) {
    if (/uses: actions\/(?:upload|download)-artifact@/.test(step)) {
      assert.ok(index < credentials, "artifact transfers must not consume the AWS session");
    }
    assert.ok(!step.includes('release.mjs upload "'), "CI uses the separate storage stages");
  }
});

test("publish refuses missing, inaccessible or mismatching S3 objects before API publication", async t => {
  const release = new Release();
  const expected = { size: "123", sha256: "a".repeat(64), crc64: "1" };
  t.mock.method(release, "moduleVersion", async () => "0.1.9");
  t.mock.method(release, "localArtifact", async () => expected);
  t.mock.method(release, "headObject", () => expected);
  const request = t.mock.method(release, "fetchJson", async () => assert.fail("must not publish"));
  const head = t.mock.method(release, "headS3Object", () => ({ size: "123", sha256: "b".repeat(64) }));
  await assert.rejects(release.publish("v0.1.9", { fromCheckout: true }), /S3 object does not match/);
  head.mock.mockImplementation(() => ({ size: "1", sha256: expected.sha256 }));
  await assert.rejects(release.publish("v0.1.9", { fromCheckout: true }), /S3 object does not match/);
  for (const error of [new Error("S3 404"), new Error("S3 access denied")]) {
    head.mock.mockImplementation(() => { throw error; });
    await assert.rejects(release.publish("v0.1.9", { fromCheckout: true }), actual => actual === error);
  }
  assert.equal(request.mock.callCount(), 0);
});

test("published retry restores all OSS bytes before the separate S3 stage", async t => {
  const release = new Release();
  t.mock.method(release, "moduleVersion", async () => "0.1.9");
  t.mock.method(release, "oss", () => ({ bucket: "test", region: "test", prefix: "releases" }));
  t.mock.method(release, "s3", () => ({}));
  t.mock.method(release, "fetch", async () => new Response(null, { status: 200 }));
  const restored = new Set();
  t.mock.method(release, "commandRun", (program, args) => {
    assert.equal(program, "ossutil");
    assert.match(args.at(-2), /^oss:\/\//);
    restored.add(args.at(-1));
  });
  const canonical = { size: 123, sha256: "a".repeat(64) };
  t.mock.method(release, "localArtifact", async artifact => {
    assert.ok(restored.has(join(release.dist, artifact.file)));
    return canonical;
  });
  t.mock.method(release, "verifyServed", async (_version, _artifact, local) => assert.equal(local, canonical));
  const mirror = t.mock.method(release, "uploadS3Artifact", (_version, _artifact, local) => {
    assert.equal(restored.size, 4);
    assert.equal(local, canonical);
  });
  t.mock.method(release, "unpackBrowser", async () => {});
  t.mock.method(release, "fetchJson", async () => assert.fail("must not replace the published Browser"));
  await release.uploadOss("v0.1.9");
  assert.equal(mirror.mock.callCount(), 0);
  await release.uploadS3("v0.1.9");
  assert.equal(mirror.mock.callCount(), 4);
});

test("S3 upload failure stops before staging the Browser on the API", async t => {
  const release = new Release();
  t.mock.method(release, "moduleVersion", async () => "0.1.9");
  t.mock.method(release, "oss", () => ({ bucket: "test", region: "test", prefix: "releases" }));
  t.mock.method(release, "s3", () => ({}));
  t.mock.method(release, "fetch", async () => new Response(null, { status: 404 }));
  t.mock.method(release, "commandRun", () => {});
  t.mock.method(release, "localArtifact", async () => ({ size: 123, sha256: "a".repeat(64), path: "fixture" }));
  t.mock.method(release, "verifyServed", async () => {});
  t.mock.method(release, "uploadS3Artifact", () => { throw new Error("S3 unavailable"); });
  const request = t.mock.method(release, "fetchJson", async () => assert.fail("must not stage Browser"));
  await assert.rejects(release.uploadS3("v0.1.9"), /S3 unavailable/);
  assert.equal(request.mock.callCount(), 0);
});

test("S3 stage refuses local bytes changed since the OSS stage", async t => {
  const release = new Release();
  t.mock.method(release, "moduleVersion", async () => "0.1.9");
  t.mock.method(release, "s3", () => ({}));
  t.mock.method(release, "fetch", async () => new Response(null, { status: 404 }));
  t.mock.method(release, "localArtifact", async () => ({ size: 123, sha256: "b".repeat(64), path: "fixture" }));
  t.mock.method(release, "headObject", () => ({ size: "123", sha256: "a".repeat(64), crc64: "1" }));
  const commands = t.mock.method(release, "commandRun", () => assert.fail("must not upload different bytes to S3"));
  const request = t.mock.method(release, "fetchJson", async () => assert.fail("must not stage Browser"));
  await assert.rejects(release.run("upload-s3", "v0.1.9"), /OSS object does not match the built artifact/);
  assert.equal(commands.mock.callCount(), 0);
  assert.equal(request.mock.callCount(), 0);
});

for (const provider of ["oss", "amz"]) {
  test(`public verification follows redirects and hashes ${provider} downloads`, async t => {
    const release = new Release();
    release.dist = await fs.mkdtemp(join(tmpdir(), "openseek-download-"));
    t.after(() => fs.rm(release.dist, { recursive: true, force: true }));
    const bytes = Buffer.from("canonical release bytes");
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    let corrupt = false;
    const url = await server(t, (request, response) => {
      if (request.url === "/redirect") {
        response.writeHead(302, { location: "/object" });
        response.end();
      } else {
        response.writeHead(200, { "content-length": bytes.length, [`x-${provider}-meta-sha256`]: sha256 });
        response.end(request.method === "HEAD" ? undefined : corrupt ? Buffer.alloc(bytes.length) : bytes);
      }
    });
    const manifest = { platforms: {} };
    for (const [platform, file] of Object.entries({
      "macos-arm64": "SeekMoon.app.zip", "macos-arm64-dmg": "SeekMoon.dmg",
      browser: "SeekMoon.browser.tar.gz", "windows-x64": "SeekMoon-windows-x64-setup.exe",
    })) {
      await fs.writeFile(join(release.dist, file), bytes);
      manifest.platforms[platform] = { url: `${url}/redirect`, sha256 };
    }
    await release.verifyDownloads(manifest);
    corrupt = true;
    await assert.rejects(release.verifyDownloads(manifest), /download digest mismatch/);
  });
}
