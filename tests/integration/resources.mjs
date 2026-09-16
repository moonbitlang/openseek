import assert from "node:assert/strict";
import { chmod, cp, mkdir, mkdtemp, rename, rm, symlink, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const [artifact, target = "native"] = process.argv.slice(2);
if (!artifact) throw new Error("usage: node tests/integration/resources.mjs <artifact> [native|wasm]");
await mkdir(".tmp", { recursive: true });
const root = await mkdtemp(resolve(".tmp/resources-"));
try {
  const cwd = join(root, "unrelated cwd");
  await mkdir(join(cwd, "share"), { recursive: true });
  await writeFile(join(cwd, "share/decoy"), "must not select cwd resources");
  let install = join(root, "安装 with spaces");
  await mkdir(join(install, "bin"), { recursive: true });
  const name = target === "wasm" ? "probe.wasm" : "probe.exe";
  await cp(resolve(artifact), join(install, "bin", name));
  if (target !== "wasm") await chmod(join(install, "bin", name), 0o755);
  for (const state of ["missing", "installed", "symlink", "relocated", "escape", "invalid"]) {
    if (state === "installed") {
      await mkdir(join(install, "share/doc/moonbit"), { recursive: true });
      await mkdir(join(install, "share/workflow"));
      await writeFile(join(install, "share/doc/moonbit/index.md"), "installation documentation");
      await writeFile(join(install, "share/workflow/probe.mbtx"), 'fn main { println("installation workflow") }');
    } else if (state === "symlink") {
      if (process.platform === "win32") continue; // Symlink creation needs privileges on Windows.
      await symlink(join(install, "bin", name), join(cwd, name));
    } else if (state === "relocated") {
      const moved = join(root, "moved 安装");
      await rename(install, moved);
      install = moved;
    } else if (state === "escape") {
      if (process.platform === "win32") continue; // Symlink creation needs privileges on Windows.
      await writeFile(join(cwd, "outside.mbtx"), 'fn main { println("escaped") }');
      await rm(join(install, "share/workflow/probe.mbtx"));
      await symlink(join(cwd, "outside.mbtx"), join(install, "share/workflow/probe.mbtx"));
    } else if (state === "invalid") {
      await rm(join(install, "share"), { recursive: true });
      await writeFile(join(install, "share"), "not a directory");
    }
    const executable = state === "symlink" ? join(cwd, name) : join(install, "bin", name);
    const command = target === "wasm" ? "moonrun" : executable;
    const args = target === "wasm" ? [executable] : [];
    // A stale override must have no effect, even when it points to a real tree.
    const child = spawnSync(command, args, {
      cwd, env: { ...process.env, OPENSEEK_REFERENCES: join(cwd, "share") },
      encoding: "utf8", timeout: 60000,
    });
    assert.equal(child.status, 0, child.stderr || child.error?.message);
    const result = JSON.parse(child.stdout.trim());
    if (state === "missing") {
      assert.equal(result.resources, null);
      assert.equal(result.document, null);
      assert.equal(result.workflow_error, true);
      assert.match(result.workflow, /needs bundled resources/);
    } else if (state === "invalid") {
      assert.match(result.error, /not a directory/);
    } else {
      assert.equal(result.resources, join(install, "share"));
      assert.equal(result.document, "installation documentation");
      assert.equal(result.workflow_error, state === "escape", result.workflow);
      if (state !== "escape") assert.match(result.workflow, /installation workflow/);
      else assert.match(result.workflow, /bundled script must remain inside @builtin/);
    }
    console.log(`${target}: ${state} resources passed`);
  }
} finally {
  await rm(root, { recursive: true, force: true });
}
