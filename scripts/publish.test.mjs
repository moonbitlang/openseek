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

const protocol = "moonbitlang/openseek_protocol";
const sdk = "moonbitlang/openseek_tools";
const root = "moonbitlang/openseek";
const report = result => JSON.stringify({ version: 1, status: "success", result, messages: [] });

async function runFixture(t, { existing = {}, replies = {}, manifest } = {}) {
  const { base, repository } = await fixture(t);
  if (manifest !== undefined) await fs.writeFile(join(repository, "protocol/moon.mod"), manifest);
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
const existing = JSON.parse(process.env.EXISTING);
let key, result;
if (command[0] === 'view') {
  if (command.at(-1) !== '--json') throw new Error('Expected JSON query');
  key = command[1] === 'moonbitlang' ? 'profile' : command[1];
  if (key === 'profile') result = { username: 'moonbitlang', modules: Object.keys(existing).map(name => ({ name })) };
  else {
    if (command[2] !== '--versions' || !Object.hasOwn(existing, key)) throw new Error('Unexpected version query');
    result = existing[key];
  }
} else if (command[0] === 'update') {
  key = 'update-' + calls.filter(c => c.command[0] === 'update').length;
} else if (command[0] === 'publish') {
  key = path.basename(cwd);
  if (!fs.existsSync(path.join(cwd, 'moon.mod'))) throw new Error('Missing staged manifest');
} else throw new Error('Unexpected moon command');
const reply = JSON.parse(process.env.REPLIES)[key];
if (reply) {
  process.stdout.write(reply.stdout ?? '');
  process.stderr.write(reply.stderr ?? '');
  process.exitCode = reply.code ?? 0;
} else if (command[0] === 'view') console.log(JSON.stringify({ version: 1, status: 'success', result, messages: [] }));
else console.log('OK');
`, { mode: 0o755 });
  const result = spawnSync(process.execPath, [join(repository, "scripts/publish.mjs")], {
    cwd: repository,
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, CALL_LOG: log, REPLIES: JSON.stringify(replies), EXISTING: JSON.stringify(existing) },
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

const published = {
  [protocol]: [{ version: "0.1.3" }, { version: "0.1.2", yanked: true }],
  [sdk]: [{ version: "0.2.0" }],
  [root]: [{ version: "0.3.2" }],
};

test("publishes new modules in dependency order and refreshes after protocol", async t => {
  const { result, calls } = await runFixture(t);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(calls.map(c => c.command), [["view", "moonbitlang", "--json"], ["update"], ["publish"], ["update"], ["publish"], ["publish"]]);
  assert.deepEqual(calls.filter(c => c.command[0] === "publish").map(c => c.cwd.split("/").at(-1)), ["protocol", "tools_sdk", "root"]);
});

test("skips exact published versions, including older and yanked releases", async t => {
  const { result, calls } = await runFixture(t, { existing: published });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(calls.map(c => c.command), [
    ["view", "moonbitlang", "--json"],
    ...[protocol, sdk, root].map(name => ["view", name, "--versions", "--json"]),
  ]);
  for (const name of [protocol, sdk, root]) assert.ok(result.stdout.includes(`${name}: already published`));
});

test("publishes a missing exact version even when newer versions exist", async t => {
  const { result, calls } = await runFixture(t, { existing: { ...published, [root]: [{ version: "0.3.3" }] } });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(calls.slice(4).map(c => c.command), [["update"], ["publish"]]);
  assert.equal(calls.at(-1).cwd.split("/").at(-1), "root");
});

for (const [label, reply] of Object.entries({
  "query failure": { code: 1, stdout: '{"version":1,"status":"failure","result":null,"messages":[]}' },
  "nonzero exit with valid JSON": { code: 1, stdout: report({ username: "moonbitlang", modules: [] }) },
  "malformed JSON": { stdout: "not JSON" },
  "failure envelope": { stdout: '{"version":1,"status":"failure","result":null}' },
  "unsupported schema version": { stdout: '{"version":2,"status":"success","result":null}' },
  "wrong owner": { stdout: report({ username: "someone", modules: [] }) },
  "missing module list": { stdout: report({ username: "moonbitlang" }) },
  "invalid module entry": { stdout: report({ username: "moonbitlang", modules: [null] }) },
})) {
  test(`aborts before publication on profile ${label}`, async t => {
    const { result, calls } = await runFixture(t, { replies: { profile: reply } });
    assert.equal(result.status, 1);
    assert.equal(calls.length, 1);
  });
}

for (const reply of [{ code: 1, stderr: "HTTP 404" }, { stdout: report(null) }, { stdout: report([{ version: 123 }]) }]) {
  test(`aborts all publication on invalid release lookup: ${JSON.stringify(reply)}`, async t => {
    const { result, calls } = await runFixture(t, { existing: { [root]: [] }, replies: { [root]: reply } });
    assert.equal(result.status, 1);
    assert.ok(calls.every(c => c.command[0] === "view"));
  });
}

test("stderr diagnostics do not interfere with JSON parsing", async t => {
  const { result } = await runFixture(t, { replies: { profile: {
    stdout: report({ username: "moonbitlang", modules: [] }), stderr: "registry warning\n",
  } } });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /registry warning/);
});

for (const manifest of ['name = "example/module"\n', 'version = "0.1.2"\nversion = "0.1.3"\n']) {
  test(`rejects ambiguous or missing local version: ${JSON.stringify(manifest)}`, async t => {
    const { result, calls } = await runFixture(t, { manifest });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Expected one version declaration/);
    assert.ok(calls.every(c => c.command[0] === "view"));
  });
}

for (const failure of ["403 Forbidden", "409 Conflict: The version you are attempting to upload is duplicated with an existing version", "500 Internal Server Error", "moon check failed"]) {
  test(`stops on publish failure ${failure} without matching diagnostic text`, async t => {
    const { result, calls } = await runFixture(t, { replies: { protocol: { code: 1, stderr: failure } } });
    assert.equal(result.status, 1);
    assert.equal(calls.length, 3);
    assert.match(result.stdout, /moonbitlang\/openseek_protocol: failed/);
  });
}

test("reports partial publication and stops before root on an SDK failure", async t => {
  const { result, calls } = await runFixture(t, { replies: { tools_sdk: { code: 1, stderr: "connection reset" } } });
  assert.equal(result.status, 1);
  assert.equal(calls.length, 5);
  assert.match(result.stdout, /moonbitlang\/openseek_protocol: published/);
  assert.match(result.stdout, /moonbitlang\/openseek_tools: failed/);
});

for (const step of ["update-0", "update-1"]) {
  test(`stops when ${step} fails`, async t => {
    const { result, calls } = await runFixture(t, { replies: { [step]: { code: 1, stderr: "registry unavailable" } } });
    assert.equal(result.status, 1);
    assert.equal(calls.length, step === "update-0" ? 2 : 4);
    assert.match(result.stderr, /moon update failed/);
  });
}
