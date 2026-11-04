import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import fs from "node:fs/promises";
import { createServer } from "node:http";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
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
    browser: "SeekMoon.browser.tar.gz", android: "SeekMoon-android.apk",
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
    if (request.url === "/desktop/releases/latest.json") {
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


const ReleaseFiles = {
  "macos-arm64": "SeekMoon.app.zip",
  "macos-arm64-dmg": "SeekMoon.dmg",
  browser: "SeekMoon.browser.tar.gz",
  android: "SeekMoon-android.apk",
  "windows-x64": "SeekMoon-windows-x64-setup.exe",
};

function asset(name, bytes) {
  return { name, size: bytes.length, digest: `sha256:${createHash("sha256").update(bytes).digest("hex")}`, bytes };
}

// A release checkout with distinct bytes per artifact in dist/, publishing
// against an in-memory GitHub repository that `gh` reads and writes.
async function githubFixture(t, { published = false } = {}) {
  const release = new Release();
  release.dist = await fs.mkdtemp(join(tmpdir(), "openseek-release-github-"));
  t.after(() => fs.rm(release.dist, { recursive: true, force: true }));
  for (const file of Object.values(ReleaseFiles)) await fs.writeFile(join(release.dist, file), `built ${file}`);
  t.mock.method(release, "moduleVersion", async () => "0.1.9");
  t.mock.method(release, "repository", () => "owner/repo");
  t.mock.method(release, "unpackBrowser", async () => {});
  t.mock.method(release, "isPublished", async () => published);
  t.mock.method(release, "env", name => {
    assert.equal(name, "GITHUB_SHA");
    return "0123456789abcdef";
  });
  const releases = new Map();
  const github = args => {
    const [command, subcommand, tag] = args;
    if (command === "api") {
      const wanted = JSON.parse(args.at(-1).match(/== (".*")\)$/)[1]);
      return [...releases.values()].filter(release => release.tag_name === wanted)
        .map(release => `${JSON.stringify(release)}\n`).join("");
    }
    const found = releases.get(tag);
    switch (subcommand) {
      case "create":
        assert.equal(found, undefined);
        releases.set(tag, {
          tag_name: tag, target_commitish: args[args.indexOf("--target") + 1], draft: args.includes("--draft"), assets: [],
        });
        return "";
      case "upload": {
        assert.ok(found.draft, "public assets are never replaced");
        assert.ok(args.includes("--clobber"));
        const uploaded = asset(basename(args[3]), readFileSync(args[3]));
        found.assets = [...found.assets.filter(asset => asset.name !== uploaded.name), uploaded];
        return "";
      }
      case "download":
        for (const asset of found.assets) writeFileSync(join(args[args.indexOf("--dir") + 1], asset.name), asset.bytes);
        return "";
      case "edit":
        if (args.includes("--target")) {
          assert.ok(found.draft, "a public release's tag already exists");
          found.target_commitish = args[args.indexOf("--target") + 1];
          return "";
        }
        assert.ok(args.includes("--draft=false") && args.includes("--latest"));
        found.draft = false;
        return "";
      default:
        assert.fail(`unexpected gh ${args.join(" ")}`);
    }
  };
  const gh = t.mock.method(release, "gh", github);
  return { release, releases, gh, github };
}

function publicRelease(tag, bytesFor = file => Buffer.from(`canonical ${file}`)) {
  return {
    tag_name: tag, target_commitish: "0123456789abcdef", draft: false,
    assets: Object.values(ReleaseFiles).map(file => asset(file, bytesFor(file))),
  };
}

function ghCalls(gh, subcommand) {
  return gh.mock.calls.map(call => call.arguments[0]).filter(args => args[1] === subcommand);
}

test("upload attaches every artifact to a new draft tagged at the built commit, then stages the Browser", async t => {
  const { release, releases, gh } = await githubFixture(t);
  const stage = t.mock.method(release, "fetchJson", async (path, options) => {
    assert.equal(path, "/desktop/releases/v0.1.9/SeekMoon.browser.tar.gz?platform=browser");
    assert.equal(options.method, "PUT");
    assert.deepEqual(releases.get("v0.1.9").assets.map(asset => asset.name), Object.values(ReleaseFiles),
      "every asset is on GitHub before the API sees the Browser");
    return { sha256: createHash("sha256").update(options.body).digest("hex") };
  });
  await release.run("upload", "v0.1.9");
  const [create] = ghCalls(gh, "create");
  assert.equal(create[create.indexOf("--target") + 1], "0123456789abcdef");
  assert.deepEqual(releases.get("v0.1.9").assets.map(asset => asset.name), Object.values(ReleaseFiles));
  assert.equal(releases.get("v0.1.9").draft, true, "upload never makes a release public");
  assert.equal(stage.mock.callCount(), 1);

  // A retry of an unpublished release replaces the draft's provisional assets.
  await fs.writeFile(join(release.dist, "SeekMoon.dmg"), "rebuilt DMG");
  await release.run("upload", "v0.1.9");
  assert.equal(ghCalls(gh, "create").length, 1);
  assert.equal(releases.get("v0.1.9").assets.find(asset => asset.name === "SeekMoon.dmg").bytes.toString(), "rebuilt DMG");
});

test("upload refuses assets GitHub reports differently before staging the Browser", async t => {
  const { release, releases, gh, github } = await githubFixture(t);
  releases.set("v0.1.9", { tag_name: "v0.1.9", draft: true, assets: [] });
  gh.mock.mockImplementation(args => {
    const result = github(args);
    if (args[1] === "upload" && basename(args[3]) === "SeekMoon-android.apk") {
      releases.get("v0.1.9").assets.find(asset => asset.name === "SeekMoon-android.apk").digest = `sha256:${"b".repeat(64)}`;
    }
    return result;
  });
  const request = t.mock.method(release, "fetchJson", async () => assert.fail("must not stage the Browser"));
  await assert.rejects(release.upload("v0.1.9"), /GitHub asset does not match the built artifact: android/);
  assert.equal(request.mock.callCount(), 0);
});

test("upload moves an earlier commit's draft to the built commit before replacing its assets", async t => {
  const { release, releases, gh } = await githubFixture(t);
  releases.set("v0.1.9", { tag_name: "v0.1.9", target_commitish: "fedcba9876543210", draft: true, assets: [] });
  t.mock.method(release, "fetchJson", async (path, options) =>
    ({ sha256: createHash("sha256").update(options.body).digest("hex") }));
  await release.upload("v0.1.9");
  const [edit] = ghCalls(gh, "edit");
  assert.equal(edit[edit.indexOf("--target") + 1], "0123456789abcdef");
  const uploads = gh.mock.calls.map(call => call.arguments[0]);
  assert.ok(uploads.indexOf(edit) < uploads.findIndex(args => args[1] === "upload"), "the target moves before any asset");
  assert.equal(releases.get("v0.1.9").target_commitish, "0123456789abcdef");
  assert.deepEqual(releases.get("v0.1.9").assets.map(asset => asset.name), Object.values(ReleaseFiles));
});

test("upload refuses a public release built from another commit", async t => {
  const { release, releases, gh } = await githubFixture(t);
  releases.set("v0.1.9", { ...publicRelease("v0.1.9"), target_commitish: "fedcba9876543210" });
  const request = t.mock.method(release, "fetchJson", async () => assert.fail("must not stage the Browser"));
  await assert.rejects(release.upload("v0.1.9"),
    /v0\.1\.9 is public on GitHub from fedcba9876543210, not 0123456789abcdef/);
  assert.deepEqual(gh.mock.calls.map(call => call.arguments[0][0]), ["api"], "nothing is downloaded or changed");
  for (const file of Object.values(ReleaseFiles)) {
    assert.equal(await fs.readFile(join(release.dist, file), "utf8"), `built ${file}`);
  }
  assert.equal(request.mock.callCount(), 0);
});

test("upload adopts a public release's assets instead of replacing them with a rebuild", async t => {
  const { release, releases, gh } = await githubFixture(t, { published: true });
  releases.set("v0.1.9", publicRelease("v0.1.9"));
  const request = t.mock.method(release, "fetchJson", async () => assert.fail("must not replace the published Browser"));
  await release.upload("v0.1.9");
  assert.equal(ghCalls(gh, "create").length + ghCalls(gh, "upload").length, 0);
  for (const file of Object.values(ReleaseFiles)) {
    assert.equal(await fs.readFile(join(release.dist, file), "utf8"), `canonical ${file}`);
  }
  assert.equal(request.mock.callCount(), 0);
});

test("publish makes the release public and latest before the API publishes GitHub's digests", async t => {
  const { release, releases, gh } = await githubFixture(t);
  releases.set("v0.1.9", { ...publicRelease("v0.1.9", file => Buffer.from(`built ${file}`)), draft: true });
  let published;
  t.mock.method(release, "fetchJson", async (path, options) => {
    if (path === "/desktop/releases/v0.1.9/publish") {
      assert.equal(releases.get("v0.1.9").draft, false, "the API links only to public assets");
      const { platforms } = JSON.parse(options.body);
      published = { version: "0.1.9", platforms: Object.fromEntries(Object.entries(platforms).map(([platform, { file, sha256 }]) =>
        [platform, { url: `https://github.com/owner/repo/releases/download/v0.1.9/${file}`, sha256 }])) };
      return { published };
    }
    assert.equal(path, "/desktop/releases/latest.json");
    return published;
  });
  await release.run("publish", "v0.1.9");
  assert.deepEqual(Object.keys(published.platforms).sort(), Object.keys(ReleaseFiles).sort());
  assert.equal(published.platforms.android.sha256,
    createHash("sha256").update("built SeekMoon-android.apk").digest("hex"));
  assert.equal(ghCalls(gh, "edit").length, 1);
});

for (const scenario of [
  { name: "a missing asset", change: assets => assets.filter(asset => asset.name !== "SeekMoon-android.apk"), error: /has no SeekMoon-android\.apk/ },
  { name: "an asset without a digest", change: assets => assets.map(asset => ({ ...asset, digest: null })), error: /no SHA-256 digest/ },
  { name: "an asset other than the built one", change: assets => assets.map(asset => asset.name === "SeekMoon.dmg" ? { ...asset, size: 1 } : asset), error: /does not match the built artifact: macos-arm64-dmg/ },
]) {
  test(`publish refuses ${scenario.name} before making the release public`, async t => {
    const { release, releases, gh } = await githubFixture(t);
    const draft = { ...publicRelease("v0.1.9", file => Buffer.from(`built ${file}`)), draft: true };
    releases.set("v0.1.9", { ...draft, assets: scenario.change(draft.assets) });
    const request = t.mock.method(release, "fetchJson", async () => assert.fail("must not publish"));
    await assert.rejects(release.publish("v0.1.9", { fromCheckout: true }), scenario.error);
    assert.equal(ghCalls(gh, "edit").length, 0);
    assert.equal(request.mock.callCount(), 0);
  });
}

test("rollback republishes GitHub's digests without local archives", async t => {
  const { release, releases, gh } = await githubFixture(t);
  releases.set("v0.1.8", publicRelease("v0.1.8"));
  const local = t.mock.method(release, "localArtifact", async () => assert.fail("rollback reads no local archives"));
  let platforms, published;
  t.mock.method(release, "fetchJson", async (path, options) => {
    if (path === "/desktop/releases/v0.1.8/publish") {
      platforms = JSON.parse(options.body).platforms;
      published = { version: "0.1.8", platforms: Object.fromEntries(Object.entries(platforms).map(([platform, { file, sha256 }]) =>
        [platform, { url: `https://github.com/owner/repo/releases/download/v0.1.8/${file}`, sha256 }])) };
      return { published };
    }
    assert.equal(path, "/desktop/releases/latest.json");
    return published;
  });
  await release.run("rollback", "v0.1.8");
  assert.equal(local.mock.callCount(), 0);
  assert.equal(platforms.browser.sha256, createHash("sha256").update("canonical SeekMoon.browser.tar.gz").digest("hex"));
  assert.equal(ghCalls(gh, "edit")[0][2], "v0.1.8");
});

test("rollback refuses a version that has no GitHub release", async t => {
  const { release, gh } = await githubFixture(t);
  const request = t.mock.method(release, "fetchJson", async () => assert.fail("must not publish"));
  await assert.rejects(release.publish("v0.1.7", { fromCheckout: false }), /v0\.1\.7 has no GitHub release/);
  assert.equal(ghCalls(gh, "edit").length, 0);
  assert.equal(request.mock.callCount(), 0);
});

test("release lookup finds drafts by tag and refuses ambiguous tags", t => {
  const release = new Release();
  t.mock.method(release, "repository", () => "owner/repo");
  const lines = [];
  const gh = t.mock.method(release, "gh", () => lines.join("\n"));
  assert.equal(release.githubRelease("v0.1.9"), undefined);
  const [args] = gh.mock.calls[0].arguments;
  assert.ok(args.includes("--paginate"), "drafts and older releases may be past the first page");
  assert.equal(args.at(-1), '.[] | select(.tag_name == "v0.1.9")');
  lines.push(JSON.stringify({ tag_name: "v0.1.9", draft: true, assets: [] }));
  assert.equal(release.githubRelease("v0.1.9").draft, true);
  lines.push(JSON.stringify({ tag_name: "v0.1.9", draft: false, assets: [] }));
  assert.throws(() => release.githubRelease("v0.1.9"), /2 GitHub releases are tagged v0\.1\.9/);
});

test("public verification follows redirects and hashes the downloaded bytes", async t => {
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
      response.writeHead(200, { "content-length": bytes.length });
      response.end(corrupt ? Buffer.alloc(bytes.length) : bytes);
    }
  });
  const manifest = { platforms: {} };
  for (const [platform, file] of Object.entries(ReleaseFiles)) {
    await fs.writeFile(join(release.dist, file), bytes);
    manifest.platforms[platform] = { url: `${url}/redirect`, sha256 };
  }
  await release.verifyDownloads(manifest);
  corrupt = true;
  await assert.rejects(release.verifyDownloads(manifest), /download digest mismatch/);
});
