import { execFileSync, spawn } from "node:child_process";
import { realpathSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, readFile, rm } from "node:fs/promises";
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

function moon(args, cwd, { capture = false } = {}) {
  return new Promise((resolveResult, reject) => {
    const child = spawn("moon", args, {
      cwd,
      env: { ...process.env, NO_COLOR: "1", MOON_WORK: "off", MOON_IGNORE_PREBUILD: "1" },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", chunk => {
      stdout += chunk;
      if (!capture) process.stdout.write(chunk);
    });
    child.stderr.pipe(process.stderr, { end: false });
    child.once("error", reject);
    child.once("close", (code, signal) => {
      if (signal) reject(new Error(`moon ${args.join(" ")} terminated by ${signal}`));
      else resolveResult({ code, stdout });
    });
  });
}

async function view(args, cwd) {
  const result = await moon(["view", ...args, "--json"], cwd, { capture: true });
  if (result.code !== 0) throw new Error(`moon view ${args.join(" ")} failed: ${result.stdout.trim()}`);
  const report = JSON.parse(result.stdout);
  if (report?.version !== 1 || report.status !== "success") {
    throw new Error(`Invalid moon view report for ${args.join(" ")}: ${result.stdout.trim()}`);
  }
  return report.result;
}

async function publicationPlan(staged, cwd) {
  const profile = await view(["moonbitlang"], cwd);
  if (profile?.username !== "moonbitlang" || !Array.isArray(profile.modules) ||
      !profile.modules.every(module => typeof module?.name === "string")) {
    throw new Error("Invalid moon view organization profile");
  }
  const publishedModules = new Set(profile.modules.map(module => module.name));
  const plan = [];
  for (const module of staged) {
    // These repository manifests use a top-level string version. Refuse an
    // absent/ambiguous declaration rather than guessing which version to skip.
    const manifest = await readFile(join(module.cwd, "moon.mod"), "utf8");
    const versions = [...manifest.matchAll(/^[ \t]*version[ \t]*=[ \t]*"([^"\r\n]+)"[ \t]*(?:\/\/[^\r\n]*)?\r?$/gm)];
    if (versions.length !== 1) throw new Error(`Expected one version declaration in ${module.name}/moon.mod`);
    const version = versions[0][1];
    let published = false;
    if (publishedModules.has(module.name)) {
      const releases = await view([module.name, "--versions"], cwd);
      if (!Array.isArray(releases) || !releases.every(release => typeof release?.version === "string")) {
        throw new Error(`Invalid moon view release list for ${module.name}`);
      }
      // Deprecated releases still occupy their version and must not be uploaded again.
      published = releases.some(release => release.version === version);
    }
    plan.push({ ...module, version, published });
  }
  return plan;
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
    // Finish every registry query before the first upload. A failed lookup is
    // never interpreted as an unpublished module or version.
    const plan = await publicationPlan(staged, temporary);
    if (plan.some(module => !module.published)) await updateRegistry(temporary);
    for (const module of plan) {
      if (module.published) {
        results.push(`${module.name}: already published`);
        continue;
      }
      console.log(`\nPublishing ${module.name}@${module.version}`);
      const result = await moon(["publish"], module.cwd);
      if (result.code === 0) {
        results.push(`${module.name}: published`);
      } else {
        results.push(`${module.name}: failed`);
        throw new Error(`Publishing ${module.name} failed`);
      }
      // Root publication validates against the registry, not the local member.
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
