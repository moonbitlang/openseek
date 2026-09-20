import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { stageModules } from "./publish.mjs";

async function fixture(t) {
  const base = await fs.mkdtemp(join(tmpdir(), "publish-test-"));
  t.after(() => fs.rm(base, { recursive: true, force: true }));
  const repository = join(base, "repository");
  await fs.mkdir(repository);
  const files = {
    "moon.mod": 'name = "moonbitlang/openseek"\nversion = "0.3.2"\n',
    "moon.work": 'members = [".", "protocol", "tools_sdk"]\n',
    "protocol/moon.mod": 'name = "moonbitlang/openseek_protocol"\nversion = "0.1.2"\n',
    "protocol/source.mbt": "protocol source",
    "protocol/.moonignore": "private.txt\n",
    "tools_sdk/moon.mod": 'name = "moonbitlang/openseek_tools"\nversion = "0.2.0"\n',
    "tools_sdk/source.mbt": "tools source",
    "README.mbt.md": "readme",
    "prompt/generated_default_prompt.mbt": "generated prompt",
    "share/workflow/check.mbtx": "runtime resource",
    "removed.mbt": "removed tracked file",
    "editor/moon.mod": "nested member",
    "desktop/backend/moon.mod": "nested member",
    "cmd/viz_app/moon.mod": "nested member",
    "inspect/moon.mod": "nested member",
    "scripts/moon.mod": "nested member",
    "tests/fixture.txt": "development fixture",
    "eval/fixture.txt": "development fixture",
    ".github/workflows/ci.yml": "CI config",
    "protocol/_build/generated.mbt": "tracked build output",
    "node_modules/example/index.js": "tracked dependency",
  };
  for (const [file, content] of Object.entries(files)) {
    await fs.mkdir(join(repository, file, ".."), { recursive: true });
    await fs.writeFile(join(repository, file), content);
  }
  await fs.symlink("README.mbt.md", join(repository, "README.md"));
  await fs.copyFile(new URL("./publish.mjs", import.meta.url), join(repository, "scripts/publish.mjs"));
  execFileSync("git", ["init", "-q"], { cwd: repository });
  execFileSync("git", ["add", "-f", "."], { cwd: repository });
  await fs.rm(join(repository, "removed.mbt"));
  await fs.writeFile(join(repository, "untracked-secret.txt"), "must not ship");
  return { base, repository };
}

test("staging isolates members, excludes development files, and keeps runtime sources", async t => {
  const { base, repository } = await fixture(t);
  const staged = await stageModules(repository, join(base, "staged"));
  assert.deepEqual(staged.map(module => module.directory), ["protocol", "tools_sdk", "."]);
  for (const module of staged) {
    assert.match(await fs.readFile(join(module.cwd, "moon.mod"), "utf8"), new RegExp(module.name));
    await assert.rejects(fs.stat(join(module.cwd, ".git")), { code: "ENOENT" });
  }
  assert.equal(await fs.readFile(join(staged[0].cwd, ".moonignore"), "utf8"), "private.txt\n");
  assert.equal(await fs.readFile(join(staged[0].cwd, "source.mbt"), "utf8"), "protocol source");
  const root = staged[2].cwd;
  for (const excluded of ["protocol", "tools_sdk", "editor", "desktop", "cmd/viz_app", "inspect", "scripts", "tests", "eval", ".github", "moon.work", "node_modules", "removed.mbt", "untracked-secret.txt"]) {
    await assert.rejects(fs.stat(join(root, excluded)), { code: "ENOENT" });
  }
  await assert.rejects(fs.stat(join(staged[0].cwd, "_build")), { code: "ENOENT" });
  assert.equal(await fs.readFile(join(root, "share/workflow/check.mbtx"), "utf8"), "runtime resource");
  assert.equal(await fs.readFile(join(root, "prompt/generated_default_prompt.mbt"), "utf8"), "generated prompt");
  assert.equal(await fs.readFile(join(root, "README.md"), "utf8"), "readme");
  assert.equal((await fs.lstat(join(root, "README.md"))).isSymbolicLink(), false);
});

async function runFixture(t, replies = {}) {
  const { base, repository } = await fixture(t);
  const bin = join(base, "bin");
  const log = join(base, "calls.jsonl");
  await fs.mkdir(bin);
  await fs.writeFile(join(bin, "moon"), `#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const command = process.argv.slice(2);
const cwd = process.cwd();
const calls = fs.existsSync(process.env.CALL_LOG) ? fs.readFileSync(process.env.CALL_LOG, 'utf8').trim().split('\\n').map(JSON.parse) : [];
const entry = { command, cwd, workspace: process.env.MOON_WORK, prebuild: process.env.MOON_IGNORE_PREBUILD };
fs.appendFileSync(process.env.CALL_LOG, JSON.stringify(entry) + '\\n');
const key = command[0] === 'update' ? 'update-' + calls.filter(c => c.command[0] === 'update').length : path.basename(cwd);
if (command[0] === 'publish' && !fs.existsSync(path.join(cwd, 'moon.mod'))) throw new Error('Missing staged manifest');
const reply = JSON.parse(process.env.REPLIES)[key];
if (reply) { console.error(reply); process.exit(1); }
console.log('OK');
`, { mode: 0o755 });
  const result = spawnSync(process.execPath, [join(repository, "scripts/publish.mjs")], {
    cwd: repository,
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, CALL_LOG: log, REPLIES: JSON.stringify(replies) },
    encoding: "utf8",
  });
  const calls = (await fs.readFile(log, "utf8")).trim().split("\n").map(JSON.parse);
  for (const call of calls) {
    await assert.rejects(fs.stat(call.cwd), { code: "ENOENT" });
    assert.equal(call.workspace, "off");
    assert.equal(call.prebuild, "1");
  }
  return { result, calls };
}

// Actual Mooncakes response recorded during the PR's live dry-run verification.
const duplicate = "Server status: 409 Conflict, detail: Version Error: The version you are attempting to upload (0.1.1) is duplicated with an existing version (0.1.1). Please select a different version to publish.";

for (const replies of [{}, { protocol: duplicate, tools_sdk: duplicate }, { protocol: duplicate, tools_sdk: duplicate, root: duplicate }]) {
  test(`publishes in dependency order and refreshes after protocol (${Object.keys(replies).length} duplicate versions)`, async t => {
    const { result, calls } = await runFixture(t, replies);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(calls.map(c => c.command), [["update"], ["publish"], ["update"], ["publish"], ["publish"]]);
    assert.deepEqual(calls.filter(c => c.command[0] === "publish").map(c => c.cwd.split("/").at(-1)), ["protocol", "tools_sdk", "root"]);
    assert.match(result.stdout, replies.root ? /moonbitlang\/openseek: already published/ : /moonbitlang\/openseek: published/);
    if (replies.protocol) assert.match(result.stdout, /moonbitlang\/openseek_protocol: already published/);
  });
}

for (const failure of ["Server status: 403 Forbidden", "Server status: 409 Conflict, detail: unrelated conflict", "Server status: 500 Internal Server Error", "moon check failed"]) {
  test(`stops on ${failure} and cleans staging`, async t => {
    const { result, calls } = await runFixture(t, { protocol: failure });
    assert.equal(result.status, 1);
    assert.equal(calls.length, 2);
    assert.match(result.stdout, /moonbitlang\/openseek_protocol: failed/);
  });
}

test("reports partial publication and stops before root on an SDK failure", async t => {
  const { result, calls } = await runFixture(t, { tools_sdk: "connection reset" });
  assert.equal(result.status, 1);
  assert.equal(calls.length, 4);
  assert.match(result.stdout, /moonbitlang\/openseek_protocol: published/);
  assert.match(result.stdout, /moonbitlang\/openseek_tools: failed/);
});

for (const step of ["update-0", "update-1"]) {
  test(`stops when ${step} fails`, async t => {
    const { result, calls } = await runFixture(t, { [step]: "registry unavailable" });
    assert.equal(result.status, 1);
    assert.equal(calls.length, step === "update-0" ? 1 : 3);
    assert.match(result.stderr, /moon update failed/);
  });
}
