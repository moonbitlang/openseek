import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile, readFile, chmod, rm, symlink, rename, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { execFileSync } from "node:child_process";
import { launcher, packageHeadless } from "./package.mjs";
import { checkElf, inventory, validateManifest, verifyTree } from "./manifest.mjs";

const unix = { skip: process.platform === "win32" ? "POSIX package filesystem" : false };

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "headless-manifest-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const seed = "toolchains/moonbit/linux-arm64";
  for (const path of ["bin/openseek", "bin/moonrun", "bin/rg", "lib/openseek.wasm",
    "share/doc/moonbit/index.md", "web/viz/index.html", "web/viz/viz_app.js", `${seed}/bin/moon`, `${seed}/bin/moonc`,
    `${seed}/bin/moonx`, `${seed}/bin/moonrun`, `${seed}/lib/core/moon.mod`, `${seed}/.openseek-moonbit-seed-version`]) {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), path, { mode: 0o644 });
    await chmod(join(root, path), path.includes("bin/") || path.startsWith("libexec/") ? 0o755 : 0o644);
  }
  const manifest = { schema_version: 1, build_id: "test-build", platform: "linux-arm64", protocol_version: 1,
    data_schema_version: 1, runtime_requirements: { os: "Linux", libc: "glibc", minimum_glibc: "2.35" }, moonbit_version: "test-version", resource_sha256: "a".repeat(64), files: await inventory(root) };
  return { root, manifest };
}

test("manifest verification rejects changed bytes, modes, extra files and links", unix, async t => {
  const { root, manifest } = await fixture(t);
  await verifyTree(root, manifest);
  const path = join(root, "bin/rg");
  const original = await readFile(path);
  await writeFile(path, "bad!!!");
  await assert.rejects(verifyTree(root, manifest), /checksum/);
  await writeFile(path, original);
  await chmod(path, 0o644);
  await assert.rejects(verifyTree(root, manifest), /permissions/);
  await chmod(path, 0o755);
  await writeFile(join(root, "extra"), "extra");
  await assert.rejects(verifyTree(root, manifest), /file set/);
  await rm(join(root, "extra"));
  await rm(path);
  await symlink("../lib/openseek.wasm", path);
  await assert.rejects(verifyTree(root, manifest), /regular files/);
});

test("manifest rejects ambiguous paths, incomplete resources and GUI payloads", unix, async t => {
  const { manifest } = await fixture(t);
  for (const path of ["../escape", "/absolute", "a//b", "a/./b", "a\\b", "a\nb", "manifest.json"]) {
    const files = [...manifest.files, { ...manifest.files[0], path }];
    assert.throws(() => validateManifest({ ...manifest, files }), /Invalid/);
  }
  assert.throws(() => validateManifest({ ...manifest, files: [...manifest.files, manifest.files[0]] }), /duplicate/);
  assert.throws(() => validateManifest({ ...manifest, files: manifest.files.map(file => file.path === "bin/rg" ? { ...file, mode: 0o644 } : file) }), /not executable/);
  assert.throws(() => validateManifest({ ...manifest, files: manifest.files.filter(file => file.path !== "bin/moonrun") }), /missing/);
  assert.throws(() => validateManifest({ ...manifest, files: [...manifest.files, { ...manifest.files[0], path: "web/frontend.js" }] }), /GUI/);
});

test("architecture validation rejects the other ELF architecture and non-executables", () => {
  const elf = Buffer.alloc(64);
  elf.set([127, 69, 76, 70, 2, 1]);
  elf.writeUInt16LE(3, 16);
  elf.writeUInt16LE(183, 18);
  checkElf(elf, "linux-arm64", "fixture");
  assert.throws(() => checkElf(elf, "linux-x64", "fixture"), /ELF executable/);
  elf.writeUInt16LE(1, 16);
  assert.throws(() => checkElf(elf, "linux-arm64", "fixture"), /ELF executable/);
  assert.throws(() => checkElf(Buffer.from("#!/bin/sh"), "linux-x64", "fixture"), /ELF executable/);
});

test("relocated launcher preserves argv and explicit resource paths through shell quoting", unix, async t => {
  const parent = await mkdtemp(join(tmpdir(), "headless-launch-"));
  t.after(() => rm(parent, { recursive: true, force: true }));
  const initial = join(parent, "initial");
  await mkdir(join(initial, "bin"), { recursive: true });
  await writeFile(join(initial, "bin/openseek"), launcher("test-build", "linux-arm64"), { mode: 0o755 });
  await writeFile(join(initial, "bin/moonrun"), `#!${process.execPath}\nconsole.log(JSON.stringify({argv:process.argv.slice(2),env:process.env}));\n`, { mode: 0o755 });
  let moved = join(parent, "moved ' package $literal");
  await rename(initial, moved);
  moved = await realpath(moved);
  const args = ["app-server", "daemon", "start", "--data-dir", "/tmp/a b '$literal"];
  const prepared = join(parent, "prepared toolchain/bin");
  const seed = join(moved, "toolchains/moonbit/linux-arm64/bin");
  for (const [bin, identity] of [[prepared, "prepared"], [seed, "seed"]]) {
    await mkdir(bin, { recursive: true });
    await writeFile(join(bin, "moon"), `#!/bin/sh\nprintf '%s' '${identity}'\n`, { mode: 0o755 });
  }
  await writeFile(join(moved, "bin/moonrun"), `#!${process.execPath}\nconst {execFileSync}=require('node:child_process'); console.log(JSON.stringify({argv:process.argv.slice(2),env:process.env,selected:execFileSync('moon',[],{encoding:'utf8'})}));\n`, { mode: 0o755 });
  const reply = JSON.parse(execFileSync(join(moved, "bin/openseek"), args, {
    encoding: "utf8", env: { ...process.env, PATH: prepared + ":/usr/bin:/bin" },
  }));
  assert.equal(reply.selected, "prepared");
  assert.deepEqual(reply.argv, [join(moved, "lib/openseek.wasm"), "--", ...args]);
  assert.equal(reply.env.OPENSEEK_HOST_MOONBIT_SEED_DIR, join(moved, "toolchains/moonbit/linux-arm64"));
  assert.equal(reply.env.OPENSEEK_HOST_ENGINE, join(moved, "bin/openseek"));
  assert.equal(reply.env.OPENSEEK_HOST_BUILD_ID, "test-build");
  assert.ok(reply.env.PATH.startsWith(join(moved, "bin") + ":"));
});


test("packaging rejects corrupted vendor input and preserves an existing output", unix, async t => {
  const root = await mkdtemp(join(tmpdir(), "headless-publish-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  await writeFile(join(root, "wasm"), Buffer.from([0, 97, 115, 109, 1, 0, 0, 0]));
  await writeFile(join(root, "moonbit-linux-x86_64.tar.gz"), "corrupted archive");
  const args = { platform: "linux-x64", buildId: "test-build",
    vendorDir: root, output: join(root, "output"), wasm: join(root, "wasm"), viz: join(root, "unused") };
  await assert.rejects(packageHeadless(args), /Vendor checksum mismatch/);
  await assert.rejects(readFile(join(args.output, "manifest.json")), { code: "ENOENT" });
  await mkdir(args.output);
  await writeFile(join(args.output, "keep"), "existing package");
  await assert.rejects(packageHeadless(args), /Output already exists/);
  assert.equal(await readFile(join(args.output, "keep"), "utf8"), "existing package");
});

// Desktop pin bumps must also refresh the executable SDK shipped to SSH hosts.
test("headless vendor SDK follows the desktop toolchain pin", async () => {
  const lock = JSON.parse(await readFile(new URL("./vendors.json", import.meta.url), "utf8"));
  const version = (await readFile(new URL("../../desktop/.moonbit-version", import.meta.url), "utf8")).trim();
  assert.equal(lock.moonbit_version, version);
});
