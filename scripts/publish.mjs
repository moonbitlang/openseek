import { execFileSync, spawn } from "node:child_process";
import { realpathSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const modules = [
  { directory: "protocol", name: "moonbitlang/openseek_protocol" },
  { directory: "tools_sdk", name: "moonbitlang/openseek_tools" },
  { directory: ".", name: "moonbitlang/openseek" },
];

// These exclusions belong to the root module only. A repository-level
// .moonignore would also exclude the members when publishing them separately.
const rootExclusions = [
  "desktop", "editor", "protocol", "tools_sdk", "cmd/viz_app", "inspect", "scripts",
  "tests", "eval", "docs/plans", ".github", ".agents", ".codex",
  "moon.work", "justfile", "AGENTS.md", "agent-improvement-guide.md",
  "improvement.md", "shrink_package.md", "desktop-dev.html", "web/viz_app.js",
];
const generatedDirectories = new Set([
  "_build", "target", ".mooncakes", "node_modules", ".moonagent", ".repos",
  ".openseek", ".claude", ".proton", ".vscode", ".DS_Store",
]);

// Copy current tracked source, including each member's own ignore configuration.
// Independent directories have no ancestor Git checkout or workspace, so root
// packaging rules and local workspace overrides cannot leak into member releases.
export async function stageModules(repository, destination) {
  const deleted = new Set(execFileSync("git", ["ls-files", "--deleted", "-z"], {
    cwd: repository, encoding: "utf8",
  }).split("\0"));
  const files = execFileSync("git", ["ls-files", "-z"], {
    cwd: repository, encoding: "utf8",
  }).split("\0").filter(file => file && !deleted.has(file));
  const staged = [];
  for (const module of modules) {
    const cwd = join(destination, module.directory === "." ? "root" : module.directory);
    await mkdir(cwd, { recursive: true });
    for (const file of files) {
      if (file.split("/").some(part => generatedDirectories.has(part))) continue;
      let relative = file;
      if (module.directory === ".") {
        if (rootExclusions.some(path => file === path || file.startsWith(`${path}/`))) continue;
      } else {
        const prefix = `${module.directory}/`;
        if (!file.startsWith(prefix)) continue;
        relative = file.slice(prefix.length);
      }
      const target = join(cwd, relative);
      await mkdir(dirname(target), { recursive: true });
      // Materialize tracked README symlinks so the staged package is standalone.
      await copyFile(join(repository, file), target);
    }
    staged.push({ ...module, cwd });
  }
  return staged;
}

function moon(args, cwd) {
  return new Promise((resolveResult, reject) => {
    const child = spawn("moon", args, {
      cwd,
      env: { ...process.env, NO_COLOR: "1", MOON_WORK: "off", MOON_IGNORE_PREBUILD: "1" },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    for (const [stream, sink] of [[child.stdout, process.stdout], [child.stderr, process.stderr]]) {
      stream.setEncoding("utf8");
      stream.on("data", chunk => { output += chunk; sink.write(chunk); });
    }
    child.once("error", reject);
    child.once("close", (code, signal) => {
      if (signal) reject(new Error(`moon ${args.join(" ")} terminated by ${signal}`));
      else resolveResult({ code, output });
    });
  });
}

async function updateRegistry(cwd) {
  const result = await moon(["update"], cwd);
  if (result.code !== 0) throw new Error("moon update failed");
}

export async function publish(repository) {
  const temporary = await mkdtemp(join(tmpdir(), "openseek-publish-"));
  const results = [];
  try {
    const staged = await stageModules(repository, temporary);
    await updateRegistry(temporary);
    for (const module of staged) {
      console.log(`\nPublishing ${module.name}`);
      const result = await moon(["publish"], module.cwd);
      if (result.code === 0) {
        results.push(`${module.name}: published`);
      } else if (/^Server status: 409 Conflict, detail: [^\r\n]*the version you are attempting to upload \([^)]+\) is duplicated with an existing version/m.test(result.output)) {
        results.push(`${module.name}: already published`);
      } else {
        results.push(`${module.name}: failed`);
        throw new Error(`Publishing ${module.name} failed`);
      }
      // Root publication validates against the registry, not the local member.
      // Refresh even after a duplicate response (another run may have published it).
      if (module.directory === "protocol") await updateRegistry(temporary);
    }
  } finally {
    await rm(temporary, { recursive: true, force: true });
    if (results.length) console.log(`\n${results.join("\n")}`);
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  publish(repository).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
